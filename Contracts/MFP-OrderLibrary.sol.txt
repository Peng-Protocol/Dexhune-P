// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4
// Changes:
// - Added PrepData struct to reduce stack depth in prepSellOrder and prepBuyOrder.
// - Moved BuyOrderDetails and SellOrderDetails to IMFPOrderLibrary interface for visibility.
// - No other functional changes beyond approved fixes.

import "./imports/SafeERC20.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IMFPListing {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function buyOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 createdAt, uint256 lastFillAt,
        uint256 pending, uint256 filled, uint256 maxPrice, uint256 minPrice, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 createdAt, uint256 lastFillAt,
        uint256 pending, uint256 filled, uint256 maxPrice, uint256 minPrice, uint8 status
    );
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function pendingBuyOrders(uint256 listingId) external view returns (uint256[] memory);
    function pendingSellOrders(uint256 listingId) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
}

interface IMFPLiquidity {
    function addFees(address caller, bool isX, uint256 fee) external;
}

library MFPOrderLibrary {
    using SafeERC20 for IERC20;

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IMFPListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    struct PrepData {
        uint256 normalized;
        uint256 fee;
        uint256 principal;
        uint256 orderId;
        IMFPListing.UpdateType[] updates;
        address token;
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    // Helper functions
    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient ETH amount");
            (bool success, ) = target.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, target, amount);
        }
        uint256 postBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(address token, uint256 amount) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        normalized = amount;
        if (decimals != 18) {
            if (decimals < 18) normalized = amount * (10 ** (uint256(18) - uint256(decimals)));
            else normalized = amount / (10 ** (uint256(decimals) - uint256(18)));
        }
        fee = (normalized * 5) / 10000; // 0.05% fee
        principal = normalized - fee;
    }

    function _createOrderUpdate(
        uint8 updateType,
        uint256 orderId,
        uint256 principal,
        address maker,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice
    ) internal pure returns (IMFPListing.UpdateType[] memory) {
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](1);
        updates[0] = IMFPListing.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        return updates;
    }

    // Prep functions
    function prepBuyOrder(
        address listingAddress,
        IMFPOrderLibrary.BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external view returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.tokenA();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, details.amount)));
        prepData.updates = _createOrderUpdate(
            1, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function prepSellOrder(
        address listingAddress,
        IMFPOrderLibrary.SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external view returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.tokenB();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, details.amount)));
        prepData.updates = _createOrderUpdate(
            2, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    // Execute functions
    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IMFPListing listing = IMFPListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses(0);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);

        uint256 receivedPrincipal = _transferToken(prep.token, listingAddress, prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        listing.update(proxy, prep.updates);
        liquidity.addFees(proxy, true, prep.fee);

        IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
        (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) = listing.volumeBalances(0);
        historicalUpdate[0] = IMFPListing.UpdateType(
            3, 0, listing.prices(0), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, true, msg.sender);
    }

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IMFPListing listing = IMFPListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses(0);
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);

        uint256 receivedPrincipal = _transferToken(prep.token, listingAddress, prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        listing.update(proxy, prep.updates);
        liquidity.addFees(proxy, false, prep.fee);

        IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
        (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) = listing.volumeBalances(0);
        historicalUpdate[0] = IMFPListing.UpdateType(
            3, 0, listing.prices(0), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, false, msg.sender);
    }

    // Clear functions
    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        address refundTo;
        uint256 refundAmount;
        address token;
        if (isBuy) {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenA();
        } else {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenB();
        }

        if (refundAmount > 0) {
            listing.transact(proxy, token, refundAmount, refundTo);
        }

        IMFPListing.UpdateType[] memory updates = _createOrderUpdate(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0);
        listing.update(proxy, updates);
        emit OrderCancelled(orderId);
    }

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory buyOrders = listing.pendingBuyOrders(0);
        uint256[] memory sellOrders = listing.pendingSellOrders(0);

        uint256 totalOrders = buyOrders.length + sellOrders.length;
        if (totalOrders == 0) return;

        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](totalOrders);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < buyOrders.length; i++) {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(buyOrders[i]);
            if (status == 1 || status == 2) {
                address refundTo = recipient != address(0) ? recipient : maker;
                if (pending > 0) {
                    listing.transact(proxy, listing.tokenA(), pending, refundTo);
                }
                updates[updateCount] = _createOrderUpdate(1, buyOrders[i], 0, address(0), address(0), 0, 0)[0];
                updateCount++;
                emit OrderCancelled(buyOrders[i]);
            }
        }

        for (uint256 i = 0; i < sellOrders.length; i++) {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(sellOrders[i]);
            if (status == 1 || status == 2) {
                address refundTo = recipient != address(0) ? recipient : maker;
                if (pending > 0) {
                    listing.transact(proxy, listing.tokenB(), pending, refundTo);
                }
                updates[updateCount] = _createOrderUpdate(2, sellOrders[i], 0, address(0), address(0), 0, 0)[0];
                updateCount++;
                emit OrderCancelled(sellOrders[i]);
            }
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }
}

interface IMFPOrderLibrary {
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    struct SellOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IMFPListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    function prepBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external view returns (OrderPrep memory);

    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external view returns (OrderPrep memory);

    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;

    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external;

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy
    ) external;
}