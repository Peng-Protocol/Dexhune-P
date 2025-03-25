// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

// Version: 0.0.2

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

contract MFPRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public listingAgent;
    mapping(uint256 => uint256) public liquidityIndexCount; // listingId -> next index

    // Structs
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = price, 4 = dayStart
        uint256 index;    // orderId or balance index (0 for x, 1 for y)
        uint256 value;    // principal or amount (18 decimals)
        address addr;     // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for buy orders (18 decimals)
        uint256 minPrice; // for buy orders (18 decimals)
    }
    struct SellOrderDetails {
        address recipient;
        uint256 amount;   // Native decimals
        uint256 maxPrice; // Maximum price (18 decimals)
        uint256 minPrice; // Minimum price (18 decimals)
    }
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;   // Native decimals
        uint256 maxPrice; // 18 decimals
        uint256 minPrice; // 18 decimals
    }
    
    // Events
    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);

    constructor() {
        _transferOwnership(msg.sender);
    }

    function setAgent(address _agent) external onlyOwner {
        listingAgent = _agent;
    }

    function createBuyOrder(address listingAddress, BuyOrderDetails memory details) external payable nonReentrant {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);

        address tokenA = IMFPListing(listingAddress).tokenA();
        uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
        uint256 normalizedAmount = normalize(details.amount, decimals);
        uint256 fee = (normalizedAmount * 5) / 10000; // 0.05% fee
        uint256 principal = normalizedAmount - fee;

        if (tokenA == address(0)) {
            require(msg.value == details.amount, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: details.amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenA).safeTransferFrom(msg.sender, listingAddress, details.amount);
        }

        uint256 orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, details.amount)));
        UpdateType[] memory updates = new UpdateType[](2);
        updates[0] = UpdateType(1, orderId, principal, msg.sender, details.recipient, details.maxPrice, details.minPrice);
        updates[1] = UpdateType(0, 0, normalizedAmount, address(0), address(0), 0, 0); // Update xBalance
        IMFPListing(listingAddress).update(listingId, updates);
        emit OrderCreated(orderId, true, msg.sender);
    }

    function createSellOrder(address listingAddress, SellOrderDetails memory details) external payable nonReentrant {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);

        address tokenB = IMFPListing(listingAddress).tokenB();
        uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
        uint256 normalizedAmount = normalize(details.amount, decimals);
        uint256 fee = (normalizedAmount * 5) / 10000; // 0.05% fee
        uint256 principal = normalizedAmount - fee;

        if (tokenB == address(0)) {
            require(msg.value == details.amount, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: details.amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenB).safeTransferFrom(msg.sender, listingAddress, details.amount);
        }

        uint256 orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, details.amount)));
        UpdateType[] memory updates = new UpdateType[](2);
        updates[0] = UpdateType(2, orderId, principal, msg.sender, details.recipient, details.maxPrice, details.minPrice);
        updates[1] = UpdateType(0, 1, normalizedAmount, address(0), address(0), 0, 0); // Update yBalance
        IMFPListing(listingAddress).update(listingId, updates);
        emit OrderCreated(orderId, false, msg.sender);
    }

    function clearSingleOrder(uint256 orderId, address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        
        (address buyMaker, , , , uint256 buyPending, , , uint8 buyStatus) = listing.buyOrders(orderId);
        (address sellMaker, , , , uint256 sellPending, , , uint8 sellStatus) = listing.sellOrders(orderId);

        if (buyMaker == msg.sender && buyStatus == 1) {
            UpdateType[] memory updates = new UpdateType[](1);
            updates[0] = UpdateType(1, orderId, 0, msg.sender, address(0), 0, 0); // Cancel buy order
            listing.update(listingId, updates);
            listing.transact(listingId, listing.tokenA(), buyPending, msg.sender);
            emit OrderCancelled(orderId);
        } else if (sellMaker == msg.sender && sellStatus == 1) {
            UpdateType[] memory updates = new UpdateType[](1);
            updates[0] = UpdateType(2, orderId, 0, msg.sender, address(0), 0, 0); // Cancel sell order
            listing.update(listingId, updates);
            listing.transact(listingId, listing.tokenB(), sellPending, msg.sender);
            emit OrderCancelled(orderId);
        } else {
            revert("Order not cancellable");
        }
    }

    function clearOrders(address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.makerPendingOrders(msg.sender);
        
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            clearSingleOrder(pendingOrders[i], listingAddress);
        }
    }

    function settleBuyOrders(address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingBuyOrders(listingId);
        (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);

        UpdateType[] memory updates = new UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (, address recipient, uint256 maxPrice, , , uint256 pending, , , uint8 status) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0) {
                uint256 price = listing.prices(listingId);
                if (price <= maxPrice && pending <= yBalance) {
                    updates[updateCount] = UpdateType(1, pendingOrders[i], pending, recipient, address(0), 0, 0);
                    yBalance -= pending;
                    updateCount++;
                }
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(listingId, updates);
            for (uint256 i = 0; i < updateCount; i++) {
                (, address recipient, , , , , , , ) = listing.buyOrders(updates[i].index);
                listing.transact(listingId, tokenB, updates[i].value, recipient);
            }
            (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);
            (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) = IMFPLiquidity(listing.liquidityAddresses(listingId)).liquidityDetails(listingId);
            IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, listing.tokenA(), listing.tokenB(), xBalance, yBalance, xLiquid, yLiquid);
        }
    }

    function settleSellOrders(address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingSellOrders(listingId);
        (uint256 xBalance, , , ) = listing.volumeBalances(listingId);

        UpdateType[] memory updates = new UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (, address recipient, uint256 maxPrice, uint256 minPrice, uint256 pending, , , uint8 status) = listing.sellOrders(pendingOrders[i]);
            uint256 price = listing.prices(listingId);
            if (status == 1 && pending > 0 && pending <= xBalance && price >= minPrice && price <= maxPrice) {
                updates[updateCount] = UpdateType(2, pendingOrders[i], pending, recipient, address(0), 0, 0);
                xBalance -= pending;
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(listingId, updates);
            for (uint256 i = 0; i < updateCount; i++) {
                (, address recipient, , , , , , , ) = listing.sellOrders(updates[i].index);
                listing.transact(listingId, tokenA, updates[i].value, recipient);
            }
            (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);
            (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) = IMFPLiquidity(listing.liquidityAddresses(listingId)).liquidityDetails(listingId);
            IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, listing.tokenA(), listing.tokenB(), xBalance, yBalance, xLiquid, yLiquid);
        }
    }

    function settleBuyLiquid(address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses(listingId);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        (uint256 xLiquid, , , ) = liquidity.liquidityDetails(listingId);

        uint256[] memory pendingOrders = listing.pendingSellOrders(listingId);
        UpdateType[] memory updates = new UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (, address recipient, , , uint256 pending, , , uint8 status) = listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending <= xLiquid) {
                updates[updateCount] = UpdateType(2, pendingOrders[i], pending, recipient, address(0), 0, 0);
                xLiquid -= pending;
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(listingId, updates);
            UpdateType[] memory liqUpdates = new UpdateType[](1);
            liqUpdates[0] = UpdateType(0, 0, xLiquid, address(0), address(0), 0, 0);
            liquidity.update(listingId, liqUpdates);
            for (uint256 i = 0; i < updateCount; i++) {
                (, address recipient, , , , , , , ) = listing.sellOrders(updates[i].index);
                liquidity.transact(listingId, listing.tokenA(), updates[i].value, recipient);
            }
            (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);
            (, uint256 yLiquid, uint256 xFees, uint256 yFees) = liquidity.liquidityDetails(listingId);
            IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, listing.tokenA(), listing.tokenB(), xBalance, yBalance, xLiquid, yLiquid);
        }
    }

    function settleSellLiquid(address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses(listingId);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        (, uint256 yLiquid, , ) = liquidity.liquidityDetails(listingId);

        uint256[] memory pendingOrders = listing.pendingBuyOrders(listingId);
        UpdateType[] memory updates = new UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (, address recipient, uint256 maxPrice, , , uint256 pending, , , uint8 status) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending <= yLiquid && listing.prices(listingId) <= maxPrice) {
                updates[updateCount] = UpdateType(1, pendingOrders[i], pending, recipient, address(0), 0, 0);
                yLiquid -= pending;
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(listingId, updates);
            UpdateType[] memory liqUpdates = new UpdateType[](1);
            liqUpdates[0] = UpdateType(0, 1, yLiquid, address(0), address(0), 0, 0);
            liquidity.update(listingId, liqUpdates);
            for (uint256 i = 0; i < updateCount; i++) {
                (, address recipient, , , , , , , ) = listing.buyOrders(updates[i].index);
                liquidity.transact(listingId, listing.tokenB(), updates[i].value, recipient);
            }
            (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);
            (uint256 xLiquid, , uint256 xFees, uint256 yFees) = liquidity.liquidityDetails(listingId);
            IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, listing.tokenA(), listing.tokenB(), xBalance, yBalance, xLiquid, yLiquid);
        }
    }

    function xDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddresses(listingId);
        address tokenA = IMFPListing(listingAddress).tokenA();
        uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (tokenA == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            (bool success, ) = liquidityAddress.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenA).safeTransferFrom(msg.sender, liquidityAddress, amount);
        }

        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        uint256 index = liquidity.liquidityIndexCount(listingId);
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, normalizedAmount, msg.sender, address(0), 0, 0);
        liquidity.update(listingId, updates);
        liquidityIndexCount[listingId]++;
    }

    function yDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddresses(listingId);
        address tokenB = IMFPListing(listingAddress).tokenB();
        uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (tokenB == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            (bool success, ) = liquidityAddress.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(tokenB).safeTransferFrom(msg.sender, liquidityAddress, amount);
        }

        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        uint256 index = liquidity.liquidityIndexCount(listingId);
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, normalizedAmount, msg.sender, address(0), 0, 0);
        liquidity.update(listingId, updates);
        liquidityIndexCount[listingId]++;
    }

    function xWithdraw(address listingAddress, uint256 amount, uint256 index, bool withLoss) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddresses(listingId);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        (address depositor, uint256 xRatio, uint256 xAllocation, , ) = liquidity.xLiquiditySlots(listingId, index);
        (, , uint256 xFees, ) = liquidity.liquidityDetails(listingId);
        address tokenA = IMFPListing(listingAddress).tokenA();
        uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        
        require(depositor == msg.sender, "Not depositor");
        uint256 withdrawAmount = normalizedAmount;
        uint256 newAllocation = xAllocation;

        if (normalizedAmount > xAllocation && withLoss) {
            uint256 deficit = normalizedAmount - xAllocation;
            require(xFees >= deficit, "Insufficient fees for loss");
            withdrawAmount = xAllocation + deficit;
            newAllocation = 0;
            UpdateType[] memory updates = new UpdateType[](2);
            updates[0] = UpdateType(2, index, 0, msg.sender, address(0), 0, 0); // Zero allocation
            updates[1] = UpdateType(1, 0, xFees - deficit, address(0), address(0), 0, 0); // Reduce fees
            liquidity.update(listingId, updates);
        } else {
            require(xAllocation >= normalizedAmount, "Insufficient allocation");
            newAllocation = xAllocation - normalizedAmount;
            UpdateType[] memory updates = new UpdateType[](1);
            updates[0] = UpdateType(2, index, newAllocation, msg.sender, address(0), 0, 0);
            liquidity.update(listingId, updates);
        }
        liquidity.transact(listingId, tokenA, withdrawAmount, msg.sender);

        // Sync MFP-Agent
        (uint256 xBalance, uint256 yBalance, , ) = IMFPListing(listingAddress).volumeBalances(listingId);
        (, uint256 yLiquid, , uint256 yFees) = liquidity.liquidityDetails(listingId);
        IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, tokenA, IMFPListing(listingAddress).tokenB(), xBalance, yBalance, newAllocation, yLiquid);
    }

    function yWithdraw(address listingAddress, uint256 amount, uint256 index, bool withLoss) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddresses(listingId);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        (address depositor, , uint256 yAllocation, , ) = liquidity.yLiquiditySlots(listingId, index);
        (, , , uint256 yFees) = liquidity.liquidityDetails(listingId);
        address tokenB = IMFPListing(listingAddress).tokenB();
        uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        
        require(depositor == msg.sender, "Not depositor");
        uint256 withdrawAmount = normalizedAmount;
        uint256 newAllocation = yAllocation;

        if (normalizedAmount > yAllocation && withLoss) {
            uint256 deficit = normalizedAmount - yAllocation;
            require(yFees >= deficit, "Insufficient fees for loss");
            withdrawAmount = yAllocation + deficit;
            newAllocation = 0;
            UpdateType[] memory updates = new UpdateType[](2);
            updates[0] = UpdateType(3, index, 0, msg.sender, address(0), 0, 0);
            updates[1] = UpdateType(1, 1, yFees - deficit, address(0), address(0), 0, 0);
            liquidity.update(listingId, updates);
        } else {
            require(yAllocation >= normalizedAmount, "Insufficient allocation");
            newAllocation = yAllocation - normalizedAmount;
            UpdateType[] memory updates = new UpdateType[](1);
            updates[0] = UpdateType(3, index, newAllocation, msg.sender, address(0), 0, 0);
            liquidity.update(listingId, updates);
        }
        liquidity.transact(listingId, tokenB, withdrawAmount, msg.sender);

        // Sync MFP-Agent
        (uint256 xBalance, uint256 yBalance, , ) = IMFPListing(listingAddress).volumeBalances(listingId);
        (uint256 xLiquid, , uint256 xFees, ) = liquidity.liquidityDetails(listingId);
        IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, IMFPListing(listingAddress).tokenA(), tokenB, xBalance, yBalance, xLiquid, newAllocation);
    }

    function claimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddresses(listingId);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        (, , uint256 xFees, uint256 yFees) = liquidity.liquidityDetails(listingId);
        (address xDepositor, uint256 xRatio, , , ) = liquidity.xLiquiditySlots(listingId, liquidityIndex);
        (, uint256 yRatio, , , ) = liquidity.yLiquiditySlots(listingId, liquidityIndex);
        address tokenA = IMFPListing(listingAddress).tokenA();
        address tokenB = IMFPListing(listingAddress).tokenB();

        require(xDepositor == msg.sender, "Not depositor");
        uint256 xFeeShare = (xFees * xRatio) / 1e18;
        uint256 yFeeShare = (yFees * yRatio) / 1e18;

        if (xFeeShare > 0 || yFeeShare > 0) {
            UpdateType[] memory updates = new UpdateType[](2);
            updates[0] = UpdateType(1, 0, xFees - xFeeShare, address(0), address(0), 0, 0);
            updates[1] = UpdateType(1, 1, yFees - yFeeShare, address(0), address(0), 0, 0);
            liquidity.update(listingId, updates);
            if (xFeeShare > 0) liquidity.transact(listingId, tokenA, xFeeShare, msg.sender);
            if (yFeeShare > 0) liquidity.transact(listingId, tokenB, yFeeShare, msg.sender);
            emit FeesClaimed(listingId, liquidityIndex, xFeeShare, yFeeShare);

            (uint256 xBalance, uint256 yBalance, , ) = IMFPListing(listingAddress).volumeBalances(listingId);
            (uint256 xLiquid, uint256 yLiquid, , ) = liquidity.liquidityDetails(listingId);
            IMFP(listingAgent).writeValidationSlot(listingId, listingAddress, tokenA, tokenB, xBalance, yBalance, xLiquid, yLiquid);
        }
    }

    function transferLiquidity(uint256 listingId, uint256 liquidityIndex, address newDepositor) external nonReentrant {
        address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddresses(listingId);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);
        (address xDepositor, , , , ) = liquidity.xLiquiditySlots(listingId, liquidityIndex);
        require(xDepositor == msg.sender, "Not depositor");

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(4, liquidityIndex, 0, newDepositor, address(0), 0, 0);
        liquidity.update(listingId, updates);
    }

    // Decimal normalization helpers
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / (10 ** (18 - decimals));
        return amount * (10 ** (decimals - 18));
    }
}

// Interfaces
interface IMFP {
    function writeValidationSlot(uint256 listingId, address listingAddress, address tokenA, address tokenB, uint256 xBalance, uint256 yBalance, uint256 xLiquid, uint256 yLiquid) external;
    function isValidListing(address listingAddress) external view returns (bool);
    function getListingId(address listingAddress) external view returns (uint256);
    function listingValidationByIndex(uint256 listingId) external view returns (address listingAddress, address, address, uint256, uint256, uint256, uint256, uint256);
}

interface IMFPListing {
    function update(uint256 listingId, UpdateType[] memory updates) external;
    function transact(uint256 listingId, address token, uint256 amount, address recipient) external payable;
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function buyOrders(uint256 orderId) external view returns (address, address, uint256, uint256, uint256, uint256, uint256, uint8);
    function sellOrders(uint256 orderId) external view returns (address, address, uint256, uint256, uint256, uint256, uint8);
    function volumeBalances(uint256 listingId) external view returns (uint256, uint256, uint256, uint256);
    function pendingBuyOrders(uint256 listingId) external view returns (uint256[] memory);
    function pendingSellOrders(uint256 listingId) external view returns (uint256[] memory);
    function makerPendingOrders(address maker) external view returns (uint256[] memory);
    function prices(uint256 listingId) external view returns (uint256);
}

interface IMFPLiquidity {
    function update(uint256 listingId, UpdateType[] memory updates) external;
    function transact(uint256 listingId, address token, uint256 amount, address recipient) external payable;
    function liquidityDetails(uint256 listingId) external view returns (uint256, uint256, uint256, uint256);
    function xLiquiditySlots(uint256 listingId, uint256 index) external view returns (address, uint256, uint256, uint256, uint256);
    function yLiquiditySlots(uint256 listingId, uint256 index) external view returns (address, uint256, uint256, uint256, uint256);
    function liquidityIndexCount(uint256 listingId) external view returns (uint256);
}

// Assume IERC20 includes decimals() function
interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}