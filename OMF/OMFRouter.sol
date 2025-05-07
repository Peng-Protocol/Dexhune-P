// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.2.1
// Most Recent Changes:
// - From v0.2.0: Fixed undeclared identifier errors for listingAddress in prepBuyLiquidCores, prepSellLiquidCores, processPrepBuyLiquidCores, and processPrepSellLiquidCores.
// - Added listingAddress parameter to prepBuyLiquidCores, prepSellLiquidCores, processPrepBuyLiquidCores, and processPrepSellLiquidCores.
// - Updated prepareLiquidPrimaryUpdates to pass listingAddress to prepBuyLiquidCores and prepSellLiquidCores.
// - Updated prepareBuyLiquidSecondaryUpdates and prepareSellLiquidSecondaryUpdates to pass listingAddress to processPrepBuyLiquidCores and processPrepSellLiquidCores.
// - Preserved prior changes: Replaced contents with prior LiquidPartial.sol (deposit, withdrawLiquidity, executeBuyLiquid, etc.).
// - Ensured agent and helper functions (transferToken, getLiquidityAddressInternal, etc.) are accessible from MainPartial via SettlementPartial.
// - Maintained compatibility with MainPartial structs (UpdateType, LiquidExecutionState).

import "./SettlementPartial.sol";

contract OMFRouter is SettlementPartial {
    using SafeERC20 for IERC20;

    function deposit(address listingAddress, bool isX, uint256 amount) external {
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        address token = isX ? token0 : baseToken;
        uint256 actualReceived = transferToken(token, liquidityAddress, amount);
        IOMFLiquidity(liquidityAddress).deposit(msg.sender, isX, actualReceived);
    }

    function withdrawLiquidity(address listingAddress, bool isX, uint256 amount, uint256 slotIndex) external {
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        PreparedWithdrawal memory withdrawal = isX
            ? IOMFLiquidity(liquidityAddress).xPrepOut(msg.sender, amount, slotIndex)
            : IOMFLiquidity(liquidityAddress).yPrepOut(msg.sender, amount, slotIndex);
        isX
            ? IOMFLiquidity(liquidityAddress).xExecuteOut(msg.sender, slotIndex, withdrawal)
            : IOMFLiquidity(liquidityAddress).yExecuteOut(msg.sender, slotIndex, withdrawal);
    }

    function claimFees(address listingAddress, bool isX, uint256 slotIndex, uint256 volume) external {
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        IOMFLiquidity(liquidityAddress).claimFees(msg.sender, isX, slotIndex, volume);
    }

    function executeBuyLiquid(address listingAddress, uint256 count) external {
        if (count == 0) return;
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        LiquidExecutionState memory state = prepareLiquidExecution(listingAddress);
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingBuyOrdersView();
        count = count > orderIds.length ? orderIds.length : count;
        PrimaryOrderUpdate[] memory primaryUpdates = prepareLiquidPrimaryUpdates(listingAddress, state, orderIds, count, true);
        applyLiquidPrimaryUpdates(listingAddress, primaryUpdates, true);
        SecondaryOrderUpdate[] memory secondaryUpdates = prepareBuyLiquidSecondaryUpdates(
            listingAddress,
            liquidityAddress,
            state,
            orderIds,
            count
        );
        applyLiquidSecondaryUpdates(listingAddress, secondaryUpdates, true);
    }

    function executeSellLiquid(address listingAddress, uint256 count) external {
        if (count == 0) return;
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        LiquidExecutionState memory state = prepareLiquidExecution(listingAddress);
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingSellOrdersView();
        count = count > orderIds.length ? orderIds.length : count;
        PrimaryOrderUpdate[] memory primaryUpdates = prepareLiquidPrimaryUpdates(listingAddress, state, orderIds, count, false);
        applyLiquidPrimaryUpdates(listingAddress, primaryUpdates, false);
        SecondaryOrderUpdate[] memory secondaryUpdates = prepareSellLiquidSecondaryUpdates(
            listingAddress,
            liquidityAddress,
            state,
            orderIds,
            count
        );
        applyLiquidSecondaryUpdates(listingAddress, secondaryUpdates, false);
    }

    function prepareLiquidExecution(address listingAddress) internal view returns (LiquidExecutionState memory) {
        (, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        return LiquidExecutionState({
            token0: token0,
            baseToken: baseToken,
            token0Decimals: IERC20(token0).decimals(),
            baseTokenDecimals: IERC20(baseToken).decimals(),
            price: IOMFListing(listingAddress).getPrice()
        });
    }

    function prepareLiquidPrimaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count,
        bool isBuy
    ) internal view returns (PrimaryOrderUpdate[] memory) {
        PrimaryOrderUpdate[] memory updates = new PrimaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            updates[i] = isBuy ? prepBuyLiquidCores(listingAddress, state, orderIds[i]) : prepSellLiquidCores(listingAddress, state, orderIds[i]);
        }
        return updates;
    }

    function applyLiquidPrimaryUpdates(address listingAddress, PrimaryOrderUpdate[] memory updates, bool isBuy) internal {
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

    function applyLiquidSecondaryUpdates(address listingAddress, SecondaryOrderUpdate[] memory updates, bool isBuy) internal {
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

    function prepBuyLiquidCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal view returns (PrimaryOrderUpdate memory) {
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

    function prepSellLiquidCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal view returns (PrimaryOrderUpdate memory) {
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

    function processPrepBuyLiquidCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (uint256) {
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

    function processPrepSellLiquidCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) internal returns (uint256) {
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

    function computeLiquidOrderAmounts(LiquidExecutionState memory state, uint256 pending, bool isBuy) internal pure returns (uint256 baseTokenAmount, uint256 token0Amount) {
        return computeOrderAmounts(state.price, pending, isBuy, state.token0Decimals, state.baseTokenDecimals);
    }

    function buildLiquidSecondaryUpdate(uint256 orderId, uint256 filledValue, bool isBuy) internal pure returns (SecondaryOrderUpdate memory) {
        return SecondaryOrderUpdate({
            updateType: 3,
            structId: 0,
            orderId: orderId,
            filledValue: filledValue,
            historicalPrice: 0
        });
    }

    function prepareBuyLiquidSecondaryUpdates(
        address listingAddress,
        address liquidityAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal returns (SecondaryOrderUpdate[] memory) {
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 filledValue = processPrepBuyLiquidCores(listingAddress, state, orderIds[i]);
            updates[i] = buildLiquidSecondaryUpdate(orderIds[i], filledValue, true);
        }
        return updates;
    }

    function prepareSellLiquidSecondaryUpdates(
        address listingAddress,
        address liquidityAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count
    ) internal returns (SecondaryOrderUpdate[] memory) {
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 filledValue = processPrepSellLiquidCores(listingAddress, state, orderIds[i]);
            updates[i] = buildLiquidSecondaryUpdate(orderIds[i], filledValue, false);
        }
        return updates;
    }
}