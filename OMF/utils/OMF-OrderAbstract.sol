// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.18 (Updated)
// Changes:
// - Added import for OMFSharedUtils.sol to use normalize and denormalize functions.
// - Updated _normalizeAndFee to use OMFSharedUtils.normalize (line 160).
// - Updated executeRefundAndUpdate to use OMFSharedUtils.denormalize (line 252).
// - From v0.0.17: Converted from library to abstract contract to support interface declarations.
// - From v0.0.17: Moved PrepData struct inside contract scope.
// - From v0.0.17: Made _transferToken, _normalizeAndFee, _createOrderUpdate public.
// - From v0.0.16: Replaced IOMFListing/IOMFLiquidity with OMFShared.IOMFListing/IOMFLiquidity.
// - From v0.0.16: Updated IOMFOrderLibrary to use OMFShared.UpdateType.
// - From v0.0.16: Removed SafeERC20 import, used OMFShared.SafeERC20.
// - From v0.0.16: Replaced inline assembly in clearOrders with Solidity array resizing.
// - From v0.0.14: Updated processExecuteBuyOrder/processExecuteSellOrder for tax-on-transfer tokens.
// - From v0.0.14: Removed denormalize function, now in OMFSharedUtils.
// - From v0.0.12: Fixed stack-too-deep in clearOrders/clearSingleOrder.
// - From v0.0.9: Aligned with OMFListingTemplate’s implicit listingId.

import "./OMF-Shared.sol";
import "./OMFSharedUtils.sol";

interface IOMF {
    function isValidListing(address listingAddress) external view returns (bool);
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
        OMFShared.UpdateType[] updates;
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
        address proxy,
        address user
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

abstract contract OMFOrderAbstract {
    using OMFShared.SafeERC20 for IERC20;

    struct PrepData {
        address token;
        uint256 normalized;
        uint256 fee;
        uint256 principal;
        uint256 orderId;
        OMFShared.UpdateType[] updates;
    }

    struct ExecutionState {
        OMFShared.IOMFListing listing;
        OMFShared.IOMFLiquidity liquidity;
        address liquidityAddress;
    }

    struct ClearOrderState {
        address makerAddress;
        address recipientAddress;
        uint256 pending;
        uint8 status;
        address refundTo;
        uint256 refundAmount;
        address token;
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    function _transferToken(address token, address target, uint256 amount) public returns (uint256) {
        uint256 preBalance = IERC20(token).balanceOf(target);
        IERC20(token).safeTransferFrom(msg.sender, target, amount);
        uint256 postBalance = IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(address token, uint256 amount) public view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = IERC20(token).decimals();
        normalized = OMFSharedUtils.normalize(amount, decimals);
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
    ) public pure returns (OMFShared.UpdateType[] memory) {
        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](1);
        updates[0] = OMFShared.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        return updates;
    }

    function validateAndPrepareRefund(
        OMFShared.IOMFListing listing,
        uint256 orderId,
        bool isBuy,
        address user
    ) internal view returns (ClearOrderState memory orderState, bool isValid) {
        orderState = ClearOrderState({
            makerAddress: address(0),
            recipientAddress: address(0),
            pending: 0,
            status: 0,
            refundTo: address(0),
            refundAmount: 0,
            token: address(0)
        });

        if (isBuy) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = listing.buyOrders(orderId);
            if (status == 1 || status == 2) {
                if (makerAddress != user) return (orderState, false);
                orderState.makerAddress = makerAddress;
                orderState.recipientAddress = recipientAddress;
                orderState.pending = pending;
                orderState.status = status;
                orderState.refundTo = recipientAddress != address(0) ? recipientAddress : makerAddress;
                orderState.refundAmount = pending;
                orderState.token = listing.token0();
                return (orderState, true);
            }
        } else {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = listing.sellOrders(orderId);
            if (status == 1 || status == 2) {
                if (makerAddress != user) return (orderState, false);
                orderState.makerAddress = makerAddress;
                orderState.recipientAddress = recipientAddress;
                orderState.pending = pending;
                orderState.status = status;
                orderState.refundTo = recipientAddress != address(0) ? recipientAddress : makerAddress;
                orderState.refundAmount = pending;
                orderState.token = listing.baseToken();
                return (orderState, true);
            }
        }
        return (orderState, false);
    }

    function executeRefundAndUpdate(
        OMFShared.IOMFListing listing,
        address proxy,
        ClearOrderState memory orderState,
        OMFShared.UpdateType[] memory updates,
        uint256 updateIndex,
        bool isBuy,
        uint256 orderId
    ) internal {
        if (orderState.refundAmount > 0) {
            uint8 decimals = IERC20(orderState.token).decimals();
            uint256 rawAmount = OMFSharedUtils.denormalize(orderState.refundAmount, decimals);
            listing.transact(proxy, orderState.token, rawAmount, orderState.refundTo);
        }
        updates[updateIndex] = OMFShared.UpdateType(
            isBuy ? 1 : 2,
            orderId,
            0,
            address(0),
            address(0),
            0,
            0
        );
        emit OrderCancelled(orderId);
    }

    function prepBuyOrder(
        address listingAddress,
        IOMFOrderAbstract.BuyOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (IOMFOrderAbstract.OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.token0();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = listing.nextOrderId();
        prepData.updates = _createOrderUpdate(
            1, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return IOMFOrderAbstract.OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function prepSellOrder(
        address listingAddress,
        IOMFOrderAbstract.SellOrderDetails memory details,
        address listingAgent,
        address proxy
    ) external returns (IOMFOrderAbstract.OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.baseToken();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = listing.nextOrderId();
        prepData.updates = _createOrderUpdate(
            2, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return IOMFOrderAbstract.OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function executeBuyOrder(
        address listingAddress,
        IOMFOrderAbstract.OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        address liquidityAddr = listing.liquidityAddress();
        ExecutionState memory state = ExecutionState(listing, OMFShared.IOMFLiquidity(liquidityAddr), liquidityAddr);
        processExecuteBuyOrder(prep, state, proxy);
    }

    function processExecuteBuyOrder(
        IOMFOrderAbstract.OrderPrep memory prep,
        ExecutionState memory state,
        address proxy
    ) internal {
        uint256 receivedPrincipal = _transferToken(prep.token, address(state.listing), prep.principal);
        require(receivedPrincipal > 0, "No principal received");

        uint256 receivedFee = _transferToken(prep.token, state.liquidityAddress, prep.fee);

        // Update principal in updates to reflect post-tax amount
        prep.updates[0].value = receivedPrincipal;

        state.listing.update(proxy, prep.updates);
        state.liquidity.addFees(proxy, true, receivedFee);

        OMFShared.UpdateType[] memory historicalUpdate = new OMFShared.UpdateType[](1);
        (
            uint256 xBalance,
            uint256 yBalance,
            uint256 xVolume,
            uint256 yVolume
        ) = state.listing.listingVolumeBalancesView();
        historicalUpdate[0] = OMFShared.UpdateType(
            3, 0, state.listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        state.listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, true, msg.sender);
    }

    function executeSellOrder(
        address listingAddress,
        IOMFOrderAbstract.OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        address liquidityAddr = listing.liquidityAddress();
        ExecutionState memory state = ExecutionState(listing, OMFShared.IOMFLiquidity(liquidityAddr), liquidityAddr);
        processExecuteSellOrder(prep, state, proxy);
    }

    function processExecuteSellOrder(
        IOMFOrderAbstract.OrderPrep memory prep,
        ExecutionState memory state,
        address proxy
    ) internal {
        uint256 receivedPrincipal = _transferToken(prep.token, address(state.listing), prep.principal);
        require(receivedPrincipal > 0, "No principal received");

        uint256 receivedFee = _transferToken(prep.token, state.liquidityAddress, prep.fee);

        // Update principal in updates to reflect post-tax amount
        prep.updates[0].value = receivedPrincipal;

        state.listing.update(proxy, prep.updates);
        state.liquidity.addFees(proxy, false, receivedFee);

        OMFShared.UpdateType[] memory historicalUpdate = new OMFShared.UpdateType[](1);
        (
            uint256 xBalance,
            uint256 yBalance,
            uint256 xVolume,
            uint256 yVolume
        ) = state.listing.listingVolumeBalancesView();
        historicalUpdate[0] = OMFShared.UpdateType(
            3, 0, state.listing.listingPriceView(), address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        state.listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, false, msg.sender);
    }

    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external {
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);

        (ClearOrderState memory orderState, bool isValid) = validateAndPrepareRefund(listing, orderId, isBuy, msg.sender);
        require(isValid, "Order not active or not maker");

        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](1);
        executeRefundAndUpdate(listing, proxy, orderState, updates, 0, isBuy, orderId);

        listing.update(proxy, updates);
    }

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address user
    ) external {
        require(IOMF(listingAgent).isValidListing(listingAddress), "Invalid listing");
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        (bool success, bytes memory returnData) = listingAddress.staticcall(
            abi.encodeWithSignature("makerPendingOrdersView(address)", user)
        );
        require(success, "Failed to fetch user orders");
        uint256[] memory userOrders = abi.decode(returnData, (uint256[]));

        if (userOrders.length == 0) return;

        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](userOrders.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < userOrders.length; i++) {
            bool isValid;
            ClearOrderState memory orderState;

            // Try buy order
            (orderState, isValid) = validateAndPrepareRefund(listing, userOrders[i], true, user);
            if (isValid) {
                executeRefundAndUpdate(listing, proxy, orderState, updates, updateCount, true, userOrders[i]);
                updateCount++;
                continue;
            }

            // Try sell order
            (orderState, isValid) = validateAndPrepareRefund(listing, userOrders[i], false, user);
            if (isValid) {
                executeRefundAndUpdate(listing, proxy, orderState, updates, updateCount, false, userOrders[i]);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            if (updateCount < updates.length) {
                OMFShared.UpdateType[] memory resized = new OMFShared.UpdateType[](updateCount);
                for (uint256 i = 0; i < updateCount; i++) {
                    resized[i] = updates[i];
                }
                updates = resized;
            }
            listing.update(proxy, updates);
        }
    }

    function adjustOrder(
        address listing,
        bool isBuy,
        uint256 actualAmount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        OMFShared.IOMFListing listingContract = OMFShared.IOMFListing(listing);
        (uint256 normalized, , uint256 principal) = _normalizeAndFee(isBuy ? listingContract.token0() : listingContract.baseToken(), actualAmount);
        OMFShared.UpdateType[] memory updates = _createOrderUpdate(
            isBuy ? 1 : 2, orderId, principal, msg.sender, recipient, maxPrice, minPrice
        );
        listingContract.update(msg.sender, updates);
    }
}