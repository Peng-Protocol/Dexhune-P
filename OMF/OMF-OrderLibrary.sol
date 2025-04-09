// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.9 (Updated)
// Changes:
// - Added tax-on-transfer adjustment via adjustOrder (from v0.0.6).
// - Replaced block.timestamp with order counter (from v0.0.6).
// - Fixed adjustOrder to overwrite original orderId (from v0.0.6).
// - Updated prep$Order to return orderId (from v0.0.6).
// - Aligned with OMFListingTemplate v0.0.7 status codes (from v0.0.7).
// - Removed nextOrderId input, added prep/execute split, normalization, events, refunds, historical updates (from v0.0.8).
// - Fetch orderId from OMFListingTemplate.nextOrderId() (new in v0.0.9).
// - Added missing SafeERC20 import to fix DeclarationError (previous revision).
// - Fixed stack-too-deep in executeBuyOrder/executeSellOrder: Added ExecutionState struct and helper functions (previous revision).
// - Fixed DeclarationError "state" visibility: Refactored ExecutionState initialization (this revision).

import "./imports/SafeERC20.sol";

interface IOMF {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IOMFListing {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function token0() external view returns (address);
    function baseToken() external view returns (address);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function listingPriceView() external view returns (uint256);
    function buyOrders(uint256 orderId) external view returns (
        address makerAddress, address recipientAddress, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address makerAddress, address recipientAddress, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function nextOrderId() external returns (uint256);
}

interface IOMFLiquidity {
    function addFees(address caller, bool isX, uint256 fee) external;
}

interface IOMFOrderLibrary {
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

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IOMFListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    function prepBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory);

    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory);

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

    function adjustOrder(
        address listing,
        bool isBuy,
        uint256 actualAmount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external;
}

library OMFOrderLibrary {
    using SafeERC20 for IERC20;

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IOMFListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    struct PrepData {
        uint256 normalized;
        uint256 fee;
        uint256 principal;
        uint256 orderId;
        IOMFListing.UpdateType[] updates;
        address token;
    }

    struct ExecutionState {
        IOMFListing listing;
        IOMFLiquidity liquidity;
        address liquidityAddress;
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    // Helper functions
    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = IERC20(token).balanceOf(target);
        IERC20(token).safeTransferFrom(msg.sender, target, amount);
        uint256 postBalance = IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(address token, uint256 amount) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = IERC20(token).decimals();
        normalized = amount;
        if (decimals != 18) {
            if (decimals < 18) normalized = amount * (10 ** (18 - decimals));
            else normalized = amount / (10 ** (decimals - 18));
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
    ) internal pure returns (IOMFListing.UpdateType[] memory) {
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](1);
        updates[0] = IOMFListing.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        return updates;
    }

    // Prep functions
    function prepBuyOrder(
        address listingAddress,
        IOMFOrderLibrary.BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory) { // Not view due to nextOrderId() call
        require(listingAgent != address(0), "Agent not set");
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.token0();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = listing.nextOrderId(); // Fetch from listing
        prepData.updates = _createOrderUpdate(
            1, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function prepSellOrder(
        address listingAddress,
        IOMFOrderLibrary.SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (OrderPrep memory) { // Not view due to nextOrderId() call
        require(listingAgent != address(0), "Agent not set");
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.baseToken();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = listing.nextOrderId(); // Fetch from listing
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
        IOMFListing listing = IOMFListing(listingAddress);
        address liquidityAddr = listing.liquidityAddresses(0);
        ExecutionState memory state = ExecutionState(listing, IOMFLiquidity(liquidityAddr), liquidityAddr);
        processExecuteBuyOrder(prep, state, proxy);
    }

    function processExecuteBuyOrder(
        OrderPrep memory prep,
        ExecutionState memory state,
        address proxy
    ) internal {
        uint256 receivedPrincipal = _transferToken(prep.token, address(state.listing), prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, state.liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        state.listing.update(proxy, prep.updates);
        state.liquidity.addFees(proxy, true, prep.fee);

        IOMFListing.UpdateType[] memory historicalUpdate = new IOMFListing.UpdateType[](1);
        (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) = state.listing.listingVolumeBalancesView();
        historicalUpdate[0] = IOMFListing.UpdateType(
            3, 0, state.listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        state.listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, true, msg.sender);
    }

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        address liquidityAddr = listing.liquidityAddresses(0);
        ExecutionState memory state = ExecutionState(listing, IOMFLiquidity(liquidityAddr), liquidityAddr);
        processExecuteSellOrder(prep, state, proxy);
    }

    function processExecuteSellOrder(
        OrderPrep memory prep,
        ExecutionState memory state,
        address proxy
    ) internal {
        uint256 receivedPrincipal = _transferToken(prep.token, address(state.listing), prep.principal);
        require(receivedPrincipal >= prep.principal, "Principal transfer failed");

        uint256 receivedFee = _transferToken(prep.token, state.liquidityAddress, prep.fee);
        require(receivedFee >= prep.fee, "Fee transfer failed");

        state.listing.update(proxy, prep.updates);
        state.liquidity.addFees(proxy, false, prep.fee);

        IOMFListing.UpdateType[] memory historicalUpdate = new IOMFListing.UpdateType[](1);
        (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) = state.listing.listingVolumeBalancesView();
        historicalUpdate[0] = IOMFListing.UpdateType(
            3, 0, state.listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        state.listing.update(proxy, historicalUpdate);

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
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);

        address refundTo;
        uint256 refundAmount;
        address token;
        if (isBuy) {
            (address maker, address recipient, , , uint256 pending, , uint8 status) = listing.buyOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.token0();
        } else {
            (address maker, address recipient, , , uint256 pending, , uint8 status) = listing.sellOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.baseToken();
        }

        if (refundAmount > 0) {
            listing.transact(proxy, token, refundAmount, refundTo);
        }

        IOMFListing.UpdateType[] memory updates = _createOrderUpdate(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0);
        listing.update(proxy, updates);
        emit OrderCancelled(orderId);
    }

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy
    ) external {
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IOMFListing listing = IOMFListing(listingAddress);
        uint256[] memory buyOrders = listing.pendingBuyOrdersView();
        uint256[] memory sellOrders = listing.pendingSellOrdersView();

        uint256 totalOrders = buyOrders.length + sellOrders.length;
        if (totalOrders == 0) return;

        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](totalOrders);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < buyOrders.length; i++) {
            (address maker, address recipient, , , uint256 pending, , uint8 status) = listing.buyOrders(buyOrders[i]);
            if (status == 1 || status == 2) {
                address refundTo = recipient != address(0) ? recipient : maker;
                if (pending > 0) {
                    listing.transact(proxy, listing.token0(), pending, refundTo);
                }
                updates[updateCount] = _createOrderUpdate(1, buyOrders[i], 0, address(0), address(0), 0, 0)[0];
                updateCount++;
                emit OrderCancelled(buyOrders[i]);
            }
        }

        for (uint256 i = 0; i < sellOrders.length; i++) {
            (address maker, address recipient, , , uint256 pending, , uint8 status) = listing.sellOrders(sellOrders[i]);
            if (status == 1 || status == 2) {
                address refundTo = recipient != address(0) ? recipient : maker;
                if (pending > 0) {
                    listing.transact(proxy, listing.baseToken(), pending, refundTo);
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

    // Retained for backward compatibility (optional)
    function adjustOrder(
        address listing,
        bool isBuy,
        uint256 actualAmount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        IOMFListing listingContract = IOMFListing(listing);
        (uint256 normalized, , uint256 principal) = _normalizeAndFee(isBuy ? listingContract.token0() : listingContract.baseToken(), actualAmount);
        IOMFListing.UpdateType[] memory updates = _createOrderUpdate(
            isBuy ? 1 : 2, orderId, principal, msg.sender, recipient, maxPrice, minPrice
        );
        listingContract.update(msg.sender, updates);
    }
}