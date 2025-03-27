// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1

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
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function buyOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint256 timestamp,
        uint256 blockNumber,
        uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint256 timestamp,
        uint256 blockNumber,
        uint8 status
    );
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

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    function createBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        address tokenA = listing.tokenA();
        (uint256 orderId, IMFPListing.UpdateType[] memory updates, uint256 fee) = _prepareOrder(
            listingAddress, tokenA, details.amount, 1, details.recipient, details.maxPrice, details.minPrice, proxy
        );
        listing.update(proxy, updates);

        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        liquidity.addFees(proxy, true, fee);

        IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
        (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) = listing.volumeBalances(0);
        historicalUpdate[0] = IMFPListing.UpdateType(
            3, 0, listing.prices(0), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(orderId, true, msg.sender);
    }

    function createSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        address tokenB = listing.tokenB();
        (uint256 orderId, IMFPListing.UpdateType[] memory updates, uint256 fee) = _prepareOrder(
            listingAddress, tokenB, details.amount, 2, details.recipient, details.maxPrice, details.minPrice, proxy
        );
        listing.update(proxy, updates);

        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        liquidity.addFees(proxy, false, fee);

        IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
        (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) = listing.volumeBalances(0);
        historicalUpdate[0] = IMFPListing.UpdateType(
            3, 0, listing.prices(0), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(orderId, false, msg.sender);
    }

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

    function _transferToken(
        address token,
        address target,
        uint256 amount,
        address proxy
    ) internal returns (uint256) {
        uint256 preBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            (bool success, ) = target.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, target, amount);
        }
        uint256 postBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(
        address token,
        uint256 amount
    ) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        normalized = amount; // Assuming external normalization for simplicity
        if (decimals != 18) {
            if (decimals < 18) normalized = amount * 10**(18 - decimals);
            else normalized = amount / 10**(decimals - 18);
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

    function _prepareOrder(
        address listingAddress,
        address token,
        uint256 amount,
        uint8 updateType,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice,
        address proxy
    ) internal returns (uint256 orderId, IMFPListing.UpdateType[] memory updates, uint256 fee) {
        uint256 receivedAmount = _transferToken(token, listingAddress, amount, proxy);
        (uint256 normalizedAmount, uint256 fee_, uint256 principal) = _normalizeAndFee(token, receivedAmount);
        orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, amount)));
        updates = _createOrderUpdate(updateType, orderId, principal, msg.sender, recipient, maxPrice, minPrice);
        return (orderId, updates, fee_);
    }
}