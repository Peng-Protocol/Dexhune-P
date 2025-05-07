// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.1.3
// Most Recent Changes:
// - From v0.1.2: Added settleBuyOrders and settleSellOrders as external user-facing functions.
// - Preserved executeBuyOrders and executeSellOrders with their helper functions to avoid stack-too-deep errors.
// - Ensured no liquidity interaction in settleBuyOrders and settleSellOrders; pending amounts remain in listing contract's xBalance or yBalance.
// - Fixed undeclared identifier errors for listingAddress in prepBuyCores, prepSellCores, etc., by adding listingAddress parameter.
// - Updated prepareBuyBatchPrimaryUpdates, prepareSellBatchPrimaryUpdates, etc., to pass listingAddress.
// - Removed count parameter from settle functions in interface and implementation for user-facing simplicity.
// - Verified all helper functions (prepareBatchExecution, computeOrderAmounts, etc.) are accessible from MainPartial.

import "./MainPartial.sol";

contract SettlementPartial is MainPartial {
    using SafeERC20 for IERC20;

    function settleBuyOrders(address listingAddress) external {
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingBuyOrdersView();
        if (orderIds.length == 0) return;
        executeBuyOrders(listingAddress, orderIds.length);
    }

    function settleSellOrders(address listingAddress) external {
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingSellOrdersView();
        if (orderIds.length == 0) return;
        executeSellOrders(listingAddress, orderIds.length);
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
            updates[i] = prepBuyCores(listingAddress, state, orderIds[i]);
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
            updates[i] = prepSellCores(listingAddress, state, orderIds[i]);
        }
        return updates;
    }

    function applyBuyBatchPrimaryUpdates(address listingAddress, PrimaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: updates[i].updateType,
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
                updateType: updates[i].updateType,
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

    function prepareBuyBatchSecondaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal returns (SecondaryOrderUpdate[] memory) {
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 filledValue = processPrepBuyCores(listingAddress, state, orderIds[i]);
            updates[i] = buildSecondaryUpdate(orderIds[i], filledValue, true);
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
            uint256 filledValue = processPrepSellCores(listingAddress, state, orderIds[i]);
            updates[i] = buildSecondaryUpdate(orderIds[i], filledValue, false);
        }
        return updates;
    }

    function applyBuyBatchSecondaryUpdates(address listingAddress, SecondaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: updates[i].updateType,
                structId: updates[i].structId,
                index: updates[i].orderId,
                value: updates[i].filledValue,
                addr: address(0),
                recipient: address(0),
                maxPrice: 0,
                minPrice: 0
            });
        }
        IOMFListing(listingAddress).update(listingUpdates);
    }

    function applySellBatchSecondaryUpdates(address listingAddress, SecondaryOrderUpdate[] memory updates) internal {
        UpdateType[] memory listingUpdates = new UpdateType[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            listingUpdates[i] = UpdateType({
                updateType: updates[i].updateType,
                structId: updates[i].structId,
                index: updates[i].orderId,
                value: updates[i].filledValue,
                addr: address(0),
                recipient: address(0),
                maxPrice: 0,
                minPrice: 0
            });
        }
        IOMFListing(listingAddress).update(listingUpdates);
    }

    function prepBuyCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal view returns (PrimaryOrderUpdate memory) {
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

    function prepSellCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal view returns (PrimaryOrderUpdate memory) {
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

    function processPrepBuyCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (uint256) {
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

    function processPrepSellCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (uint256) {
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

    function buildSecondaryUpdate(uint256 orderId, uint256 filledValue, bool isBuy) internal pure returns (SecondaryOrderUpdate memory) {
        return SecondaryOrderUpdate({
            updateType: 3,
            structId: 0,
            orderId: orderId,
            filledValue: filledValue,
            historicalPrice: 0
        });
    }
}