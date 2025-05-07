// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.1.3
// Most Recent Changes:
// - From v0.1.2: Fixed undeclared identifier errors for listingAddress in prepBuyOrderCores, prepSellOrderCores, processPrepBuyOrderCores, processPrepSellOrderCores, buildBuySecondaryUpdate, and buildSellSecondaryUpdate.
// - Added listingAddress parameter to prepBuyOrderCores, prepSellOrderCores, processPrepBuyOrderCores, processPrepSellOrderCores, buildBuySecondaryUpdate, and buildSellSecondaryUpdate.
// - Updated prepareBuyBatchPrimaryUpdates, prepareSellBatchPrimaryUpdates, prepareBuyBatchSecondaryUpdates, and prepareSellBatchSecondaryUpdates to pass listingAddress to their helpers.
// - Preserved stack depth fixes: prepareBatchSecondaryUpdates split into prepareBuyBatchSecondaryUpdates and prepareSellBatchSecondaryUpdates with helpers.
// - Ensured agent and helper functions (computeOrderAmounts, performTransactionAndAdjust, etc.) are accessible from MainPartial via OrderPartial.
// - Used explicit casting for interface calls (e.g., IOMFListing).

import "./OrderPartial.sol";

contract SettlementPartial is OrderPartial {
    using SafeERC20 for IERC20;

    function settleBuyOrders(address listingAddress, uint256 count) internal {
        if (count == 0) return;
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingBuyOrdersView();
        count = count > orderIds.length ? orderIds.length : count;
        executeBuyOrders(listingAddress, count);
    }

    function settleSellOrders(address listingAddress, uint256 count) internal {
        if (count == 0) return;
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingSellOrdersView();
        count = count > orderIds.length ? orderIds.length : count;
        executeSellOrders(listingAddress, count);
    }

    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) internal {
        (address maker, , uint8 status) = isBuy
            ? IOMFListing(listingAddress).buyOrderCoreView(orderId)
            : IOMFListing(listingAddress).sellOrderCoreView(orderId);
        require(status != 0, "Order already cleared");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType({
            updateType: isBuy ? 1 : 2,
            structId: 0,
            index: orderId,
            value: 0,
            addr: maker,
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        IOMFListing(listingAddress).update(updates);
        emit OrderCancelled(orderId, isBuy);
    }

    function clearOrders(address listingAddress, uint256[] memory orderIds, bool isBuy) internal {
        for (uint256 i = 0; i < orderIds.length; i++) {
            clearSingleOrder(listingAddress, orderIds[i], isBuy);
        }
    }

    function clearOrdersInternal(address listingAddress, address maker, bool isBuy) internal {
        uint256[] memory orderIds = IOMFListing(listingAddress).makerPendingOrdersView(maker);
        for (uint256 i = 0; i < orderIds.length; i++) {
            (address orderMaker, , uint8 status) = isBuy
                ? IOMFListing(listingAddress).buyOrderCoreView(orderIds[i])
                : IOMFListing(listingAddress).sellOrderCoreView(orderIds[i]);
            if (orderMaker == maker && status != 0) {
                clearSingleOrder(listingAddress, orderIds[i], isBuy);
            }
        }
    }

    function validateAndPrepareRefund(address listingAddress, uint256 orderId, bool isBuy) internal view returns (uint256 amount, address token, address recipient) {
        (address maker, address orderRecipient, uint8 status) = isBuy
            ? IOMFListing(listingAddress).buyOrderCoreView(orderId)
            : IOMFListing(listingAddress).sellOrderCoreView(orderId);
        (uint256 pending, ) = isBuy
            ? IOMFListing(listingAddress).buyOrderAmountsView(orderId)
            : IOMFListing(listingAddress).sellOrderAmountsView(orderId);
        require(status == 1 || status == 2, "Invalid order status");
        (, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        return (
            pending,
            isBuy ? baseToken : token0,
            orderRecipient == address(0) ? maker : orderRecipient
        );
    }

    function executeRefundAndUpdate(address listingAddress, uint256 orderId, bool isBuy) internal {
        (uint256 amount, address token, address recipient) = validateAndPrepareRefund(
            listingAddress,
            orderId,
            isBuy
        );
        uint8 decimals = IERC20(token).decimals();
        uint256 denormalizedAmount = denormalize(amount, decimals);
        IOMFListing(listingAddress).transact(token, denormalizedAmount, recipient);
        clearSingleOrder(listingAddress, orderId, isBuy);
    }

    function prepBuyOrderCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal view returns (PrimaryOrderUpdate memory) {
        (address maker, address recipient, uint8 status) = IOMFListing(listingAddress).buyOrderCoreView(orderId);
        (uint256 pending, uint256 filled) = IOMFListing(listingAddress).buyOrderAmountsView(orderId);
        require(status == 1 || status == 2, "Invalid order status");
        (uint256 baseTokenAmount, uint256 token0Amount) = computeOrderAmounts(
            state.price,
            pending,
            true,
            state.token0Decimals,
            state.baseTokenDecimals
        );
        return PrimaryOrderUpdate({
            updateType: 1,
            structId: 2,
            orderId: orderId,
            pendingValue: baseTokenAmount,
            recipient: recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    function prepSellOrderCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal view returns (PrimaryOrderUpdate memory) {
        (address maker, address recipient, uint8 status) = IOMFListing(listingAddress).sellOrderCoreView(orderId);
        (uint256 pending, uint256 filled) = IOMFListing(listingAddress).sellOrderAmountsView(orderId);
        require(status == 1 || status == 2, "Invalid order status");
        (uint256 baseTokenAmount, uint256 token0Amount) = computeOrderAmounts(
            state.price,
            pending,
            false,
            state.token0Decimals,
            state.baseTokenDecimals
        );
        return PrimaryOrderUpdate({
            updateType: 2,
            structId: 2,
            orderId: orderId,
            pendingValue: token0Amount,
            recipient: recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    function processPrepBuyOrderCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (uint256) {
        (address maker, address recipient, uint8 status) = IOMFListing(listingAddress).buyOrderCoreView(orderId);
        (uint256 pending, uint256 filled) = IOMFListing(listingAddress).buyOrderAmountsView(orderId);
        require(status == 1 || status == 2, "Invalid order status");
        (, uint256 token0Amount) = computeOrderAmounts(
            state.price,
            pending,
            true,
            state.token0Decimals,
            state.baseTokenDecimals
        );
        return performTransactionAndAdjust(listingAddress, state.token0, token0Amount, recipient, state.token0Decimals);
    }

    function processPrepSellOrderCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (uint256) {
        (address maker, address recipient, uint8 status) = IOMFListing(listingAddress).sellOrderCoreView(orderId);
        (uint256 pending, uint256 filled) = IOMFListing(listingAddress).sellOrderAmountsView(orderId);
        require(status == 1 || status == 2, "Invalid order status");
        (uint256 baseTokenAmount, ) = computeOrderAmounts(
            state.price,
            pending,
            false,
            state.token0Decimals,
            state.baseTokenDecimals
        );
        return performTransactionAndAdjust(listingAddress, state.baseToken, baseTokenAmount, recipient, state.baseTokenDecimals);
    }

    function executeBuyOrders(address listingAddress, uint256 count) internal {
        if (count == 0) return;
        LiquidExecutionState memory state = prepareBatchExecution(listingAddress);
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingBuyOrdersView();
        count = count > orderIds.length ? orderIds.length : count;
        PrimaryOrderUpdate[] memory primaryUpdates = prepareBuyBatchPrimaryUpdates(listingAddress, state, orderIds, count);
        applyBuyBatchPrimaryUpdates(listingAddress, primaryUpdates);
        SecondaryOrderUpdate[] memory secondaryUpdates = prepareBuyBatchSecondaryUpdates(
            listingAddress,
            state,
            orderIds,
            count
        );
        applyBuyBatchSecondaryUpdates(listingAddress, secondaryUpdates);
    }

    function executeSellOrders(address listingAddress, uint256 count) internal {
        if (count == 0) return;
        LiquidExecutionState memory state = prepareBatchExecution(listingAddress);
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingSellOrdersView();
        count = count > orderIds.length ? orderIds.length : count;
        PrimaryOrderUpdate[] memory primaryUpdates = prepareSellBatchPrimaryUpdates(listingAddress, state, orderIds, count);
        applySellBatchPrimaryUpdates(listingAddress, primaryUpdates);
        SecondaryOrderUpdate[] memory secondaryUpdates = prepareSellBatchSecondaryUpdates(
            listingAddress,
            state,
            orderIds,
            count
        );
        applySellBatchSecondaryUpdates(listingAddress, secondaryUpdates);
    }

    function prepareBatchExecution(address listingAddress) internal view returns (LiquidExecutionState memory) {
        (, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        return LiquidExecutionState({
            token0: token0,
            baseToken: baseToken,
            token0Decimals: IERC20(token0).decimals(),
            baseTokenDecimals: IERC20(baseToken).decimals(),
            price: IOMFListing(listingAddress).getPrice()
        });
    }

    function prepareBuyBatchPrimaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal view returns (PrimaryOrderUpdate[] memory) {
        PrimaryOrderUpdate[] memory updates = new PrimaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            updates[i] = prepBuyOrderCores(listingAddress, state, orderIds[i]);
        }
        return updates;
    }

    function prepareSellBatchPrimaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal view returns (PrimaryOrderUpdate[] memory) {
        PrimaryOrderUpdate[] memory updates = new PrimaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            updates[i] = prepSellOrderCores(listingAddress, state, orderIds[i]);
        }
        return updates;
    }

    function applyBuyBatchPrimaryUpdates(address listingAddress, PrimaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: 1,
                structId: updates[i].structId,
                index: updates[i].orderId,
                value: updates[i].pendingValue,
                addr: msg.sender,
                recipient: updates[i].recipient,
                maxPrice: updates[i].maxPrice,
                minPrice: updates[i].minPrice
            });
        }
        IOMFListing(listingAddress).update(listingUpdates);
    }

    function applySellBatchPrimaryUpdates(address listingAddress, PrimaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: 2,
                structId: updates[i].structId,
                index: updates[i].orderId,
                value: updates[i].pendingValue,
                addr: msg.sender,
                recipient: updates[i].recipient,
                maxPrice: updates[i].maxPrice,
                minPrice: updates[i].minPrice
            });
        }
        IOMFListing(listingAddress).update(listingUpdates);
    }

    function buildBuySecondaryUpdate(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (SecondaryOrderUpdate memory) {
        uint256 filledValue = processPrepBuyOrderCores(listingAddress, state, orderId);
        return SecondaryOrderUpdate({
            updateType: 3,
            structId: 0,
            orderId: orderId,
            filledValue: filledValue,
            historicalPrice: 0
        });
    }

    function buildSellSecondaryUpdate(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (SecondaryOrderUpdate memory) {
        uint256 filledValue = processPrepSellOrderCores(listingAddress, state, orderId);
        return SecondaryOrderUpdate({
            updateType: 3,
            structId: 0,
            orderId: orderId,
            filledValue: filledValue,
            historicalPrice: 0
        });
    }

    function prepareBuyBatchSecondaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal returns (SecondaryOrderUpdate[] memory) {
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            updates[i] = buildBuySecondaryUpdate(listingAddress, state, orderIds[i]);
        }
        return updates;
    }

    function prepareSellBatchSecondaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal returns (SecondaryOrderUpdate[] memory) {
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            updates[i] = buildSellSecondaryUpdate(listingAddress, state, orderIds[i]);
        }
        return updates;
    }

    function applyBuyBatchSecondaryUpdates(address listingAddress, SecondaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: 3,
                structId: 0,
                index: updates[i].orderId,
                value: updates[i].filledValue,
                addr: address(0),
                recipient: address(0),
                maxPrice: 0,
                minPrice: 0
            });
        }
        IOMFListing(listingAddress).update(listingUpdates);
        for (uint256 i = 0; i < updates.length; i++) {
            delete tempOrderUpdates[updates[i].orderId];
        }
    }

    function applySellBatchSecondaryUpdates(address listingAddress, SecondaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: 3,
                structId: 0,
                index: updates[i].orderId,
                value: updates[i].filledValue,
                addr: address(0),
                recipient: address(0),
                maxPrice: 0,
                minPrice: 0
            });
        }
        IOMFListing(listingAddress).update(listingUpdates);
        for (uint256 i = 0; i < updates.length; i++) {
            delete tempOrderUpdates[updates[i].orderId];
        }
    }
}