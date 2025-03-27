// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1

import "./imports/Ownable.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

interface IMFPRouter {
    function createBuyOrder(address listingAddress, BuyOrderDetails memory details) external payable;
    function createSellOrder(address listingAddress, SellOrderDetails memory details) external payable;
    function settleBuyOrders(address listingAddress) external;
    function settleSellOrders(address listingAddress) external;
    function settleBuyLiquid(address listingAddress) external;
    function settleSellLiquid(address listingAddress) external;
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
        uint256 listingId, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint256 timestamp, uint256 matchedOrderId, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        uint256 listingId, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint256 timestamp, uint256 matchedOrderId, uint8 status
    );
    function prices(uint256 listingId) external view returns (uint256);
    function transact(uint256 listingId, address tokenAddress, uint256 amount, address recipient) external;
}

contract Multihopper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Data
    address public routerAddress;
    mapping(uint256 => StalledHop) public hopID;
    mapping(address => uint256[]) public hopsByAddress;
    uint256[] public totalHops;
    uint256 private nextHopId;

    struct HopRequest {
        uint256 numListings;
        address[] listingAddresses;
        uint256[] impactPricePercents; // e.g., 500 = 5%
        address startToken;
        address endToken;
        uint8 settleType; // 0 = settleOrders, 1 = settleLiquid
    }

    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice; // Normalized, calculated from impact
        uint256 maxPrice; // Normalized, calculated from impact
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount; // Normalized
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus; // 0 = active, 1 = stalled, 2 = completed
    }

    // Events
    event HopCreated(uint256 indexed hopId, address indexed maker, uint256 numListings);
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event HopCanceled(uint256 indexed hopId);
    event AllHopsCanceled(address indexed maker, uint256 count);

    // Helper Functions
    function getTokenDecimals(address token) internal view returns (uint8) {
        if (token == address(0)) return 18;
        return IERC20(token).decimals();
    }

    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        uint8 decimals = this.getTokenDecimals(token);
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - decimals);
        else return amount * 10**(decimals - 18);
    }

    function computeRoute(address[] memory listingAddresses, address startToken, address endToken)
        internal view returns (uint256[] memory indices, bool[] memory isBuy)
    {
        require(listingAddresses.length > 0 && listingAddresses.length <= 4, "Invalid listing count");
        indices = new uint256[](listingAddresses.length);
        isBuy = new bool[](listingAddresses.length);
        address currentToken = startToken;
        uint256 pathLength = 0;

        // Simple DFS-like path finding with reordering
        for (uint256 i = 0; i < listingAddresses.length; i++) {
            IMFPListing listing = IMFPListing(listingAddresses[i]);
            address tokenA = listing.tokenA();
            address tokenB = listing.tokenB();
            if (currentToken == tokenA) {
                indices[pathLength] = i;
                isBuy[pathLength] = false; // Sell A for B
                currentToken = tokenB;
                pathLength++;
            } else if (currentToken == tokenB) {
                indices[pathLength] = i;
                isBuy[pathLength] = true; // Buy A with B
                currentToken = tokenA;
                pathLength++;
            }
            if (currentToken == endToken) break;
        }
        require(currentToken == endToken, "No valid route to endToken");

        // Resize arrays to actual path length
        assembly { mstore(indices, pathLength) mstore(isBuy, pathLength) }
        return (indices, isBuy);
    }

    function calculateImpactPrice(address listing, uint256 listingId, uint256 impactPercent, bool isBuy)
        internal view returns (uint256)
    {
        uint256 currentPrice = IMFPListing(listing).prices(listingId);
        if (isBuy) {
            return currentPrice + (currentPrice * impactPercent / 10000); // e.g., 5% = 500
        } else {
            return currentPrice - (currentPrice * impactPercent / 10000);
        }
    }

    function checkOrderStatus(address listing, uint256 orderId, bool isBuy)
        internal view returns (uint256 pending, uint256 filled, uint8 status)
    {
        if (isBuy) {
            (, , , , pending, filled, , , status) = IMFPListing(listing).buyOrders(orderId);
        } else {
            (, , , , pending, filled, , , status) = IMFPListing(listing).sellOrders(orderId);
        }
    }

    function safeSettle(address listing, uint256 orderId, bool isBuy, uint8 settleType)
        internal returns (bool success)
    {
        IMFPRouter router = IMFPRouter(routerAddress);
        bytes memory data;
        if (isBuy) {
            data = settleType == 0
                ? abi.encodeWithSelector(router.settleBuyOrders.selector, listing)
                : abi.encodeWithSelector(router.settleBuyLiquid.selector, listing);
        } else {
            data = settleType == 0
                ? abi.encodeWithSelector(router.settleSellOrders.selector, listing)
                : abi.encodeWithSelector(router.settleSellLiquid.selector, listing);
        }
        (success, ) = address(router).call(data);
    }

    // Main Functions
    function setRouter(address _routerAddress) external onlyOwner {
        require(_routerAddress != address(0), "Invalid router address");
        require(routerAddress == address(0), "Router already set");
        routerAddress = _routerAddress;
    }

    function hop(HopRequest memory request) external payable nonReentrant {
        require(routerAddress != address(0), "Router not set");
        require(request.numListings > 0 && request.numListings <= 4, "Invalid numListings");
        require(request.numListings == request.listingAddresses.length &&
                request.numListings == request.impactPricePercents.length, "Array length mismatch");

        IMFPRouter router = IMFPRouter(routerAddress);
        uint256 hopId = nextHopId++;
        uint256 actionCount = 0;

        // Compute route
        (uint256[] memory indices, bool[] memory isBuy) = this.computeRoute(
            request.listingAddresses, request.startToken, request.endToken
        );
        actionCount += 2 * request.numListings; // Token queries

        address currentToken = request.startToken;
        uint256 principal = msg.value > 0 ? msg.value : request.impactPricePercents[0]; // Assume first amount if ETH
        address recipient;

        for (uint256 i = 0; i < indices.length && actionCount < 100; i++) {
            uint256 idx = indices[i];
            address listing = request.listingAddresses[idx];
            IMFPListing listingContract = IMFPListing(listing);
            uint256 listingId = 0; // Assuming single listingId per contract
            bool buy = isBuy[i];
            recipient = (i == indices.length - 1) ? msg.sender : address(this);

            // Calculate price limits
            uint256 priceLimit = this.calculateImpactPrice(listing, listingId, request.impactPricePercents[idx], buy);
            actionCount += 2; // Price query and calc

            // Create order
            if (buy) {
                IMFPRouter.BuyOrderDetails memory details = IMFPRouter.BuyOrderDetails(
                    recipient, this.denormalizeForToken(principal, currentToken), priceLimit, 0
                );
                if (currentToken == address(0)) {
                    router.createBuyOrder{value: principal}(listing, details);
                } else {
                    IERC20(currentToken).safeTransferFrom(msg.sender, address(this), principal);
                    IERC20(currentToken).safeApprove(routerAddress, principal);
                    router.createBuyOrder(listing, details);
                }
            } else {
                IMFPRouter.SellOrderDetails memory details = IMFPRouter.SellOrderDetails(
                    recipient, this.denormalizeForToken(principal, currentToken), 0, priceLimit
                );
                if (currentToken == address(0)) {
                    router.createSellOrder{value: principal}(listing, details);
                } else {
                    IERC20(currentToken).safeTransferFrom(msg.sender, address(this), principal);
                    IERC20(currentToken).safeApprove(routerAddress, principal);
                    router.createSellOrder(listing, details);
                }
            }
            actionCount += 1; // Order creation

            // Get order ID
            uint256[] memory pendingOrders = listingContract.makerPendingOrders(buy ? recipient : msg.sender);
            uint256 orderId = pendingOrders[pendingOrders.length - 1];
            actionCount += 1; // Query

            // Attempt settlement
            bool success = this.safeSettle(listing, orderId, buy, request.settleType);
            actionCount += 1; // Settlement

            // Check status
            (uint256 pending, uint256 filled, uint8 status) = this.checkOrderStatus(listing, orderId, buy);
            actionCount += 1; // Query

            if (pending > 0 || !success) {
                // Stall hop
                hopID[hopId] = StalledHop({
                    stage: uint8(i),
                    currentListing: listing,
                    orderID: orderId,
                    minPrice: buy ? 0 : priceLimit,
                    maxPrice: buy ? priceLimit : 0,
                    hopMaker: msg.sender,
                    remainingListings: new address[](indices.length - i - 1),
                    principalAmount: principal,
                    startToken: request.startToken,
                    endToken: request.endToken,
                    settleType: request.settleType,
                    hopStatus: 1
                });
                for (uint256 j = i + 1; j < indices.length; j++) {
                    hopID[hopId].remainingListings[j - i - 1] = request.listingAddresses[indices[j]];
                }
                hopsByAddress[msg.sender].push(hopId);
                emit HopCreated(hopId, msg.sender, request.numListings);
                this.continueHop(); // Trigger continuation
                return;
            }

            // Update for next stage
            principal = filled;
            currentToken = buy ? listingContract.tokenA() : listingContract.tokenB();
            actionCount += 1; // Token query
        }

        // Hop completed
        hopID[hopId].hopStatus = 2;
        hopsByAddress[msg.sender].push(hopId);
        totalHops.push(hopId);
        emit HopCreated(hopId, msg.sender, request.numListings);
        this.continueHop();
    }

    function continueHop() external nonReentrant {
        uint256[] storage userHops = hopsByAddress[msg.sender];
        uint256 processed = 0;
        uint256 actionCount = 0;

        for (uint256 i = 0; i < userHops.length && processed < 20 && actionCount < 100; i++) {
            StalledHop storage hop = hopID[userHops[i]];
            if (hop.hopStatus != 1) continue;

            (uint256 pending, uint256 filled, uint8 status) = this.checkOrderStatus(
                hop.currentListing, hop.orderID, hop.maxPrice > 0
            );
            actionCount += 1;

            if (pending > 0 || status != 2) continue;

            processed++;
            uint256 nextStage = hop.stage + 1;
            if (nextStage >= hop.remainingListings.length + hop.stage + 1) {
                hop.hopStatus = 2;
                totalHops.push(userHops[i]);
                emit HopContinued(userHops[i], nextStage);
                continue;
            }

            address nextListing = hop.remainingListings[0];
            bool isBuy = hop.endToken == IMFPListing(nextListing).tokenA();
            uint256 priceLimit = this.calculateImpactPrice(nextListing, 0, 500, isBuy); // Placeholder impact
            actionCount += 2;

            IMFPRouter router = IMFPRouter(routerAddress);
            if (isBuy) {
                IMFPRouter.BuyOrderDetails memory details = IMFPRouter.BuyOrderDetails(
                    msg.sender, this.denormalizeForToken(filled, hop.startToken), priceLimit, 0
                );
                router.createBuyOrder(nextListing, details);
            } else {
                IMFPRouter.SellOrderDetails memory details = IMFPRouter.SellOrderDetails(
                    msg.sender, this.denormalizeForToken(filled, hop.startToken), 0, priceLimit
                );
                router.createSellOrder(nextListing, details);
            }
            actionCount += 1;

            uint256[] memory pendingOrders = IMFPListing(nextListing).makerPendingOrders(msg.sender);
            uint256 orderId = pendingOrders[pendingOrders.length - 1];
            actionCount += 1;

            bool success = this.safeSettle(nextListing, orderId, isBuy, hop.settleType);
            actionCount += 1;

            (pending, filled, status) = this.checkOrderStatus(nextListing, orderId, isBuy);
            actionCount += 1;

            if (pending > 0 || !success) {
                hop.currentListing = nextListing;
                hop.orderID = orderId;
                hop.stage = uint8(nextStage);
                hop.principalAmount = filled;
                address[] memory newRemaining = new address[](hop.remainingListings.length - 1);
                for (uint256 j = 1; j < hop.remainingListings.length; j++) {
                    newRemaining[j - 1] = hop.remainingListings[j];
                }
                hop.remainingListings = newRemaining;
                emit HopContinued(userHops[i], nextStage);
            } else {
                hop.hopStatus = 2;
                totalHops.push(userHops[i]);
                emit HopContinued(userHops[i], nextStage);
            }
        }

        // Prune completed hops
        for (uint256 i = userHops.length; i > 0 && actionCount < 100; i--) {
            if (hopID[userHops[i - 1]].hopStatus == 2) {
                userHops[i - 1] = userHops[userHops.length - 1];
                userHops.pop();
                actionCount += 1;
            }
        }
    }

    function cancelHop(uint256 hopId) external nonReentrant {
        StalledHop storage hop = hopID[hopId];
        require(hop.hopMaker == msg.sender, "Not hop maker");
        require(hop.hopStatus == 1, "Hop not stalled");

        IMFPRouter router = IMFPRouter(routerAddress);
        IMFPListing listing = IMFPListing(hop.currentListing);
        bool isBuy = hop.maxPrice > 0;

        router.clearSingleOrder(hop.currentListing, hop.orderID, isBuy);

        (uint256 pending, uint256 filled, ) = this.checkOrderStatus(hop.currentListing, hop.orderID, isBuy);
        if (filled > 0) {
            address targetToken = isBuy ? listing.tokenA() : listing.tokenB();
            uint256 rawFilled = this.denormalizeForToken(filled, targetToken);
            listing.transact(0, targetToken, rawFilled, msg.sender);
        }
        if (hop.stage < hop.remainingListings.length + hop.stage) {
            address principalToken = isBuy ? listing.tokenB() : listing.tokenA();
            uint256 rawPending = this.denormalizeForToken(pending, principalToken);
            if (rawPending > 0) {
                listing.transact(0, principalToken, rawPending, msg.sender);
            }
        }

        hop.hopStatus = 2;
        for (uint256 i = 0; i < hopsByAddress[msg.sender].length; i++) {
            if (hopsByAddress[msg.sender][i] == hopId) {
                hopsByAddress[msg.sender][i] = hopsByAddress[msg.sender][hopsByAddress[msg.sender].length - 1];
                hopsByAddress[msg.sender].pop();
                break;
            }
        }
        emit HopCanceled(hopId);
    }

    function cancelAll() external nonReentrant {
        uint256[] storage userHops = hopsByAddress[msg.sender];
        uint256 canceled = 0;
        uint256 actionCount = 0;

        for (uint256 i = userHops.length; i > 0 && canceled < 100 && actionCount < 100; i--) {
            uint256 hopId = userHops[i - 1];
            StalledHop storage hop = hopID[hopId];
            if (hop.hopStatus == 1) {
                this.cancelHop(hopId);
                canceled++;
                actionCount += 5; // Approx actions per cancel
            }
        }
        emit AllHopsCanceled(msg.sender, canceled);
    }
}