// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.7

import "./imports/Ownable.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

interface IMFPRouter {
    function buyOrder(address listingAddress, BuyOrderDetails memory details) external payable;
    function sellOrder(address listingAddress, SellOrderDetails memory details) external payable;
    function settleBuy(address listingAddress) external;
    function settleSell(address listingAddress) external;
    function buyLiquid(address listingAddress) external;
    function sellLiquid(address listingAddress) external;
    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) external;

    struct BuyOrderDetails {
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct SellOrderDetails {
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
    }
}

interface IMFPListing {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function makerPendingOrders(address maker) external view returns (uint256[] memory);
    function buyOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function prices(uint256 listingId) external view returns (uint256);
    function transact(address caller, address tokenAddress, uint256 amount, address recipient) external;
    function getNextOrderId(uint256 listingId) external view returns (uint256);
}

contract Multihopper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public routerAddress;
    mapping(uint256 => StalledHop) public hopID;
    mapping(address => uint256[]) public hopsByAddress;
    uint256[] public totalHops;
    uint256 private nextHopId;

    struct HopRequest {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents;
        address startToken;
        address endToken;
        uint8 settleType; // 0 = settleOrders, 1 = settleLiquid
    }

    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus; // 0 = active, 1 = stalled, 2 = completed
    }

    struct StallData {
        uint256 hopId;
        address listing;
        uint256 orderId;
        bool isBuy;
        uint256 pending;
        uint256 filled;
        uint8 status;
    }

    struct HopPrepData {
        uint256 hopId;
        uint256[] indices;
        bool[] isBuy;
        address currentToken;
        uint256 principal;
    }

    struct HopExecutionData {
        address listing;
        bool isBuy;
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        address currentToken;
    }

    struct StallExecutionData {
        address listing;
        bool isBuy;
        address recipient;
        uint256 priceLimit;
        uint256 principal;
        uint8 settleType;
    }

    event HopCreated(uint256 indexed hopId, address indexed maker, uint256 numListings);
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event HopCanceled(uint256 indexed hopId);
    event AllHopsCanceled(address indexed maker, uint256 count);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);

    function getTokenDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) return 18;
        return IERC20(token).decimals();
    }

    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        uint8 decimals = getTokenDecimals(token);
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - uint8(decimals));
        else return amount * 10**(uint8(decimals) - 18);
    }

    function computeRoute(address[] memory listingAddresses, address startToken, address endToken)
        internal view returns (uint256[] memory indices, bool[] memory isBuy)
    {
        require(listingAddresses.length > 0 && listingAddresses.length <= 4, "Invalid listing count");
        indices = new uint256[](listingAddresses.length);
        isBuy = new bool[](listingAddresses.length);
        address currentToken = startToken;
        uint256 pathLength = 0;

        for (uint256 i = 0; i < listingAddresses.length; i++) {
            IMFPListing listing = IMFPListing(listingAddresses[i]);
            address tokenA = listing.tokenA();
            address tokenB = listing.tokenB();
            if (currentToken == tokenA) {
                indices[pathLength] = i;
                isBuy[pathLength] = false;
                currentToken = tokenB;
                pathLength++;
            } else if (currentToken == tokenB) {
                indices[pathLength] = i;
                isBuy[pathLength] = true;
                currentToken = tokenA;
                pathLength++;
            }
            if (currentToken == endToken) break;
        }
        require(currentToken == endToken, "No valid route to endToken");
        assembly { mstore(indices, pathLength) mstore(isBuy, pathLength) }
        return (indices, isBuy);
    }

    function calculateImpactPrice(address listing, uint256 listingId, uint256 impactPercent, bool isBuy)
        internal view returns (uint256)
    {
        uint256 currentPrice = IMFPListing(listing).prices(listingId);
        if (isBuy) return currentPrice + (currentPrice * impactPercent / 10000);
        else return currentPrice - (currentPrice * impactPercent / 10000);
    }

    function checkOrderStatus(address listing, uint256 orderId, bool isBuy)
        internal view returns (uint256 pending, uint256 filled, uint8 status)
    {
        if (isBuy) {
            (, , , , pending, filled, status) = IMFPListing(listing).buyOrders(orderId);
        } else {
            (, , , , pending, filled, status) = IMFPListing(listing).sellOrders(orderId);
        }
    }

    function safeSettle(address listing, uint256 orderId, bool isBuy, uint8 settleType)
        internal returns (bool success)
    {
        IMFPRouter router = IMFPRouter(routerAddress);
        bytes memory data;
        if (isBuy) {
            data = settleType == 0
                ? abi.encodeWithSelector(router.settleBuy.selector, listing)
                : abi.encodeWithSelector(router.buyLiquid.selector, listing);
        } else {
            data = settleType == 0
                ? abi.encodeWithSelector(router.settleSell.selector, listing)
                : abi.encodeWithSelector(router.sellLiquid.selector, listing);
        }
        (success, ) = address(router).call(data);
    }

    function setRouter(address _routerAddress) external onlyOwner {
        require(_routerAddress != address(0), "Invalid router address");
        routerAddress = _routerAddress;
    }

    function prepHop(HopRequest memory request) internal view returns (HopPrepData memory) {
        require(routerAddress != address(0), "Router not set");
        require(request.numListings > 0 && request.numListings <= 4, "Invalid numListings");
        require(request.numListings == request.listingAddresses.length &&
                request.numListings == request.impactPricePercents.length, "Array length mismatch");

        uint256 hopId = nextHopId;
        (uint256[] memory indices, bool[] memory isBuy) = computeRoute(
            request.listingAddresses, request.startToken, request.endToken
        );

        return HopPrepData({
            hopId: hopId,
            indices: indices,
            isBuy: isBuy,
            currentToken: request.startToken,
            principal: msg.value > 0 ? msg.value : request.impactPricePercents[0]
        });
    }

    function processHopStep(
        HopExecutionData memory execData,
        IMFPRouter router,
        address sender,
        uint8 settleType
    ) internal returns (uint256 orderId, bool success, uint256 pending, uint256 filled, uint8 status) {
        IMFPListing listingContract = IMFPListing(execData.listing);
        orderId = listingContract.getNextOrderId(0); // Fetch before order creation
        if (execData.isBuy) {
            IMFPRouter.BuyOrderDetails memory details = IMFPRouter.BuyOrderDetails(
                execData.recipient, denormalizeForToken(execData.principal, execData.currentToken), execData.priceLimit, 0
            );
            if (execData.currentToken == address(0)) {
                router.buyOrder{value: execData.principal}(execData.listing, details);
            } else {
                IERC20(execData.currentToken).safeTransferFrom(sender, address(this), execData.principal);
                IERC20(execData.currentToken).safeApprove(address(router), execData.principal);
                router.buyOrder(execData.listing, details);
            }
        } else {
            IMFPRouter.SellOrderDetails memory details = IMFPRouter.SellOrderDetails(
                execData.recipient, denormalizeForToken(execData.principal, execData.currentToken), 0, execData.priceLimit
            );
            if (execData.currentToken == address(0)) {
                router.sellOrder{value: execData.principal}(execData.listing, details);
            } else {
                IERC20(execData.currentToken).safeTransferFrom(sender, address(this), execData.principal);
                IERC20(execData.currentToken).safeApprove(address(router), execData.principal);
                router.sellOrder(execData.listing, details);
            }
        }
        uint256[] memory pendingOrders = listingContract.makerPendingOrders(execData.isBuy ? execData.recipient : sender);
        orderId = pendingOrders[pendingOrders.length - 1]; // Confirm orderId after creation
        success = safeSettle(execData.listing, orderId, execData.isBuy, settleType);
        (pending, filled, status) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
    }

    function executeHop(HopPrepData memory prepData, HopRequest memory request) internal {
        IMFPRouter router = IMFPRouter(routerAddress);
        HopExecutionData memory execData = HopExecutionData({
            listing: address(0),
            isBuy: false,
            recipient: address(0),
            priceLimit: 0,
            principal: prepData.principal,
            currentToken: prepData.currentToken
        });

        for (uint256 i = 0; i < prepData.indices.length; i++) {
            execData.listing = request.listingAddresses[prepData.indices[i]];
            execData.isBuy = prepData.isBuy[i];
            execData.recipient = (i == prepData.indices.length - 1) ? msg.sender : address(this);
            execData.priceLimit = calculateImpactPrice(execData.listing, 0, request.impactPricePercents[prepData.indices[i]], execData.isBuy);

            (uint256 orderId, bool success, uint256 pending, uint256 filled, uint8 status) = processHopStep(
                execData, router, msg.sender, request.settleType
            );

            if (pending > 0 || !success) {
                hopID[prepData.hopId] = StalledHop({
                    stage: uint8(i),
                    currentListing: execData.listing,
                    orderID: orderId, // Store confirmed orderId
                    minPrice: execData.isBuy ? 0 : execData.priceLimit,
                    maxPrice: execData.isBuy ? execData.priceLimit : 0,
                    hopMaker: msg.sender,
                    remainingListings: new address[](prepData.indices.length - i - 1),
                    principalAmount: execData.principal,
                    startToken: request.startToken,
                    endToken: request.endToken,
                    settleType: request.settleType,
                    hopStatus: 1
                });
                for (uint256 j = i + 1; j < prepData.indices.length; j++) {
                    hopID[prepData.hopId].remainingListings[j - i - 1] = request.listingAddresses[prepData.indices[j]];
                }
                hopsByAddress[msg.sender].push(prepData.hopId);
                return;
            }

            execData.principal = filled;
            execData.currentToken = execData.isBuy ? IMFPListing(execData.listing).tokenA() : IMFPListing(execData.listing).tokenB();
        }

        hopID[prepData.hopId].hopStatus = 2;
        hopsByAddress[msg.sender].push(prepData.hopId);
        totalHops.push(prepData.hopId);
    }

    function hop(HopRequest memory request) external payable nonReentrant {
        HopPrepData memory prepData = prepHop(request);
        executeHop(prepData, request);
        emit HopCreated(prepData.hopId, msg.sender, request.numListings);
    }

    function prepStalls() internal returns (StallData[] memory) {
        uint256[] storage userHops = hopsByAddress[msg.sender];
        StallData[] memory stalls = new StallData[](userHops.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userHops.length && count < 20; i++) {
            StalledHop storage hop = hopID[userHops[i]];
            if (hop.hopStatus != 1) continue;

            (uint256 pending, uint256 filled, uint8 status) = checkOrderStatus(
                hop.currentListing, hop.orderID, hop.maxPrice > 0
            );
            stalls[count] = StallData({
                hopId: userHops[i],
                listing: hop.currentListing,
                orderId: hop.orderID,
                isBuy: hop.maxPrice > 0,
                pending: pending,
                filled: filled,
                status: status
            });
            count++;
        }

        assembly { mstore(stalls, count) }
        emit StallsPrepared(count > 0 ? stalls[0].hopId : 0, count);
        return stalls;
    }

    function processStallStep(
        StallExecutionData memory execData,
        IMFPRouter router,
        address startToken
    ) internal returns (uint256 orderId, bool success, uint256 pending, uint256 filled, uint8 status) {
        IMFPListing listingContract = IMFPListing(execData.listing);
        orderId = listingContract.getNextOrderId(0); // Fetch before order creation
        if (execData.isBuy) {
            IMFPRouter.BuyOrderDetails memory details = IMFPRouter.BuyOrderDetails(
                execData.recipient, denormalizeForToken(execData.principal, startToken), execData.priceLimit, 0
            );
            router.buyOrder(execData.listing, details);
        } else {
            IMFPRouter.SellOrderDetails memory details = IMFPRouter.SellOrderDetails(
                execData.recipient, denormalizeForToken(execData.principal, startToken), 0, execData.priceLimit
            );
            router.sellOrder(execData.listing, details);
        }
        uint256[] memory pendingOrders = listingContract.makerPendingOrders(execData.recipient);
        orderId = pendingOrders[pendingOrders.length - 1]; // Confirm orderId after creation
        success = safeSettle(execData.listing, orderId, execData.isBuy, execData.settleType);
        (pending, filled, status) = checkOrderStatus(execData.listing, orderId, execData.isBuy);
    }

    function executeStalls(StallData[] memory stalls) internal {
        IMFPRouter router = IMFPRouter(routerAddress);
        uint256 count = 0;
        uint256[] storage userHops = hopsByAddress[msg.sender];
        StallExecutionData memory execData = StallExecutionData({
            listing: address(0),
            isBuy: false,
            recipient: msg.sender,
            priceLimit: 0,
            principal: 0,
            settleType: 0
        });

        for (uint256 i = 0; i < stalls.length; i++) {
            StalledHop storage hop = hopID[stalls[i].hopId];
            if (hop.hopStatus != 1 || stalls[i].pending > 0 || stalls[i].status != 3) continue;

            count++;
            uint256 nextStage = uint256(hop.stage) + 1;
            if (nextStage >= hop.remainingListings.length + uint256(hop.stage) + 1) {
                hop.hopStatus = 2;
                totalHops.push(stalls[i].hopId);
                emit HopContinued(stalls[i].hopId, uint8(nextStage));
                continue;
            }

            execData.listing = hop.remainingListings[0];
            execData.isBuy = hop.endToken == IMFPListing(execData.listing).tokenA();
            execData.priceLimit = calculateImpactPrice(execData.listing, 0, 500, execData.isBuy);
            execData.principal = stalls[i].filled;
            execData.settleType = hop.settleType;

            (uint256 orderId, bool success, uint256 pending, uint256 filled, uint8 status) = processStallStep(
                execData, router, hop.startToken
            );

            if (pending > 0 || !success) {
                hop.currentListing = execData.listing;
                hop.orderID = orderId; // Store confirmed orderId for new stalled order
                hop.stage = uint8(nextStage);
                hop.principalAmount = filled;
                address[] memory newRemaining = new address[](hop.remainingListings.length - 1);
                for (uint256 j = 1; j < hop.remainingListings.length; j++) {
                    newRemaining[j - 1] = hop.remainingListings[j];
                }
                hop.remainingListings = newRemaining;
            } else {
                hop.hopStatus = 2;
                totalHops.push(stalls[i].hopId);
            }
            emit HopContinued(stalls[i].hopId, uint8(nextStage));
        }

        emit StallsExecuted(count > 0 ? stalls[0].hopId : 0, count);
        for (uint256 i = userHops.length; i > 0; i--) {
            if (hopID[userHops[i - 1]].hopStatus == 2) {
                userHops[i - 1] = userHops[userHops.length - 1];
                userHops.pop();
            }
        }
    }

    function continueHop() public nonReentrant {
        StallData[] memory stalls = prepStalls();
        if (stalls.length > 0) {
            executeStalls(stalls);
        }
    }

    function _cancelHop(uint256 hopId) internal {
        StalledHop storage hop = hopID[hopId];
        require(hop.hopMaker == msg.sender, "Not hop maker");
        require(hop.hopStatus == 1, "Hop not stalled");

        IMFPRouter router = IMFPRouter(routerAddress);
        IMFPListing listing = IMFPListing(hop.currentListing);
        bool isBuy = hop.maxPrice > 0;

        router.clearSingleOrder(hop.currentListing, hop.orderID, isBuy);
        (uint256 pending, uint256 filled, ) = checkOrderStatus(hop.currentListing, hop.orderID, isBuy);
        if (filled > 0) {
            address targetToken = isBuy ? listing.tokenA() : listing.tokenB();
            uint256 rawFilled = denormalizeForToken(filled, targetToken);
            listing.transact(msg.sender, targetToken, rawFilled, msg.sender);
        }
        if (pending > 0) {
            address principalToken = isBuy ? listing.tokenB() : listing.tokenA();
            uint256 rawPending = denormalizeForToken(pending, principalToken);
            listing.transact(msg.sender, principalToken, rawPending, msg.sender);
        }

        hop.hopStatus = 2;
        uint256[] storage userHops = hopsByAddress[msg.sender];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] == hopId) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
                break;
            }
        }
        emit HopCanceled(hopId);
    }

    function cancelHop(uint256 hopId) external nonReentrant {
        _cancelHop(hopId);
    }

    function cancelAll() external nonReentrant {
        uint256[] storage userHops = hopsByAddress[msg.sender];
        uint256 canceled = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < 100; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop storage hop = hopID[hopId];
            if (hop.hopStatus == 1) {
                _cancelHop(hopId);
                canceled++;
            }
        }
        emit AllHopsCanceled(msg.sender, canceled);
    }
}