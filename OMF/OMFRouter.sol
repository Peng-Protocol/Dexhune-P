pragma solidity 0.8.2;

// SPDX-License-Identifier: BSD-3-Clause

// Version: 0.2.5
// Most Recent Changes:
// - From v0.2.4: Added try-catch in processPrimaryUpdates, prepareBuyLiquidSecondaryUpdates, and prepareSellLiquidSecondaryUpdates for graceful degradation.
// - Added OrderProcessingFailed event emission for failed orders.
// - Modified processPrimaryUpdates, prepareBuyLiquidSecondaryUpdates, and prepareSellLiquidSecondaryUpdates to use dynamic arrays for successful updates only.
// - Ensured no listing or liquidity updates (IOMFListing.update, IOMFLiquidity.deposit) occur for failed orders.
// - Preserved settleBuyLiquid and settleSellLiquid with transferToLiquidity helper for liquid settlement.
// - Maintained executeBuyLiquid and executeSellLiquid as internal with helpers to avoid stack-too-deep errors.
// - Preserved claimFees update to fetch volume from IOMFListing.volumeBalances().
// - Removed try-catch around safeTransferFrom in transferToLiquidity, relying on its built-in revert mechanism.

import "./utils/SettlementPartial.sol";

contract OMFRouter is SettlementPartial {
    using SafeERC20 for IERC20;

    event DepositorChanged(address indexed listingAddress, bool isX, uint256 slotIndex, address indexed oldDepositor, address indexed newDepositor);

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

    function claimFees(address listingAddress, bool isX, uint256 slotIndex) external {
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        (, , uint256 xVolume, uint256 yVolume) = IOMFListing(listingAddress).volumeBalances();
        uint256 volume = isX ? xVolume : yVolume;
        IOMFLiquidity(liquidityAddress).claimFees(msg.sender, isX, slotIndex, volume);
    }

    function changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor) external {
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        require(newDepositor != address(0), "Invalid new depositor");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        IOMFLiquidity(liquidityAddress).changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor);
        emit DepositorChanged(listingAddress, isX, slotIndex, msg.sender, newDepositor);
    }

    function settleBuyLiquid(address listingAddress) external {
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingBuyOrdersView();
        if (orderIds.length == 0) return;
        executeBuyLiquid(listingAddress, orderIds.length);
    }

    function settleSellLiquid(address listingAddress) external {
        (bool isValid, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        uint256[] memory orderIds = IOMFListing(listingAddress).pendingSellOrdersView();
        if (orderIds.length == 0) return;
        executeSellLiquid(listingAddress, orderIds.length);
    }

    function prepareExecutionState(address listingAddress) internal view returns (LiquidExecutionState memory) {
        (, , address token0, address baseToken) = IOMF(agent).validateListing(listingAddress);
        return LiquidExecutionState({
            token0: token0,
            baseToken: baseToken,
            token0Decimals: IERC20(token0).decimals(),
            baseTokenDecimals: IERC20(baseToken).decimals(),
            price: IOMFListing(listingAddress).getPrice()
        });
    }

    function fetchPendingOrders(address listingAddress, uint256 count, bool isBuy) internal view returns (uint256[] memory orderIds, uint256 adjustedCount) {
        orderIds = isBuy ? IOMFListing(listingAddress).pendingBuyOrdersView() : IOMFListing(listingAddress).pendingSellOrdersView();
        adjustedCount = count > orderIds.length ? orderIds.length : count;
    }

    function processPrimaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count,
        bool isBuy
    ) internal returns (PrimaryOrderUpdate[] memory) {
        PrimaryOrderUpdate[] memory tempUpdates = new PrimaryOrderUpdate[](count);
        uint256 validCount = 0;
        for (uint256 i = 0; i < count; i++) {
            try this.prepareLiquidPrimaryUpdates(listingAddress, state, orderIds, i + 1, isBuy) returns (PrimaryOrderUpdate[] memory singleUpdate) {
                if (singleUpdate.length > 0) {
                    tempUpdates[validCount] = singleUpdate[0];
                    validCount++;
                }
            } catch Error(string memory reason) {
                emit OrderProcessingFailed(listingAddress, orderIds[i], isBuy, reason);
            } catch {
                emit OrderProcessingFailed(listingAddress, orderIds[i], isBuy, "Unknown error");
            }
        }
        PrimaryOrderUpdate[] memory updates = new PrimaryOrderUpdate[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            updates[i] = tempUpdates[i];
        }
        if (updates.length > 0) {
            applyLiquidPrimaryUpdates(listingAddress, updates, isBuy);
        }
        return updates;
    }

    function transferToLiquidity(
        address listingAddress,
        address liquidityAddress,
        LiquidExecutionState memory state,
        PrimaryOrderUpdate[] memory primaryUpdates,
        bool isBuy
    ) internal {
        for (uint256 i = 0; i < primaryUpdates.length; i++) {
            uint256 amount = primaryUpdates[i].pendingValue;
            if (amount > 0) {
                address token = isBuy ? state.baseToken : state.token0;
                uint8 decimals = isBuy ? state.baseTokenDecimals : state.token0Decimals;
                IERC20(token).safeTransferFrom(listingAddress, liquidityAddress, denormalize(amount, decimals));
                try IOMFLiquidity(liquidityAddress).deposit(address(this), isBuy, amount) {
                    // Success
                } catch Error(string memory reason) {
                    emit OrderProcessingFailed(listingAddress, primaryUpdates[i].orderId, isBuy, string(abi.encodePacked("Liquidity deposit failed: ", reason)));
                } catch {
                    emit OrderProcessingFailed(listingAddress, primaryUpdates[i].orderId, isBuy, "Liquidity deposit failed: Unknown error");
                }
            }
        }
    }

    function processSecondaryUpdates(
        address listingAddress,
        address liquidityAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count,
        bool isBuy
    ) internal {
        SecondaryOrderUpdate[] memory secondaryUpdates = isBuy
            ? prepareBuyLiquidSecondaryUpdates(listingAddress, liquidityAddress, state, orderIds, count)
            : prepareSellLiquidSecondaryUpdates(listingAddress, liquidityAddress, state, orderIds, count);
        if (secondaryUpdates.length > 0) {
            applyLiquidSecondaryUpdates(listingAddress, secondaryUpdates, isBuy);
        }
    }

    function executeBuyLiquid(address listingAddress, uint256 count) internal {
        if (count == 0) return;
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        
        LiquidExecutionState memory state = prepareExecutionState(listingAddress);
        (uint256[] memory orderIds, uint256 adjustedCount) = fetchPendingOrders(listingAddress, count, true);
        if (adjustedCount == 0) return;
        
        PrimaryOrderUpdate[] memory primaryUpdates = processPrimaryUpdates(listingAddress, state, orderIds, adjustedCount, true);
        if (primaryUpdates.length > 0) {
            transferToLiquidity(listingAddress, liquidityAddress, state, primaryUpdates, true);
        }
        processSecondaryUpdates(listingAddress, liquidityAddress, state, orderIds, adjustedCount, true);
    }

    function executeSellLiquid(address listingAddress, uint256 count) internal {
        if (count == 0) return;
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        address liquidityAddress = getLiquidityAddressInternal(listingAddress);
        
        LiquidExecutionState memory state = prepareExecutionState(listingAddress);
        (uint256[] memory orderIds, uint256 adjustedCount) = fetchPendingOrders(listingAddress, count, false);
        if (adjustedCount == 0) return;
        
        PrimaryOrderUpdate[] memory primaryUpdates = processPrimaryUpdates(listingAddress, state, orderIds, adjustedCount, false);
        if (primaryUpdates.length > 0) {
            transferToLiquidity(listingAddress, liquidityAddress, state, primaryUpdates, false);
        }
        processSecondaryUpdates(listingAddress, liquidityAddress, state, orderIds, adjustedCount, false);
    }

    function prepareLiquidPrimaryUpdates(
        address listingAddress,
        LiquidExecutionState memory state,
        uint256[] memory orderIds,
        uint256 count,
        bool isBuy
    ) external view returns (PrimaryOrderUpdate[] memory) {
        require(count <= orderIds.length, "Invalid count");
        PrimaryOrderUpdate[] memory updates = new PrimaryOrderUpdate[](1);
        updates[0] = isBuy ? prepBuyLiquidCores(listingAddress, state, orderIds[count - 1]) : prepSellLiquidCores(listingAddress, state, orderIds[count - 1]);
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
        try IOMFListing(listingAddress).update(listingUpdates) {
            // Success
        } catch Error(string memory reason) {
            emit OrderProcessingFailed(listingAddress, 0, isBuy, string(abi.encodePacked("Batch update failed: ", reason)));
        } catch {
            emit OrderProcessingFailed(listingAddress, 0, isBuy, "Batch update failed: Unknown error");
        }
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
        try IOMFListing(listingAddress).update(listingUpdates) {
            // Success
        } catch Error(string memory reason) {
            emit OrderProcessingFailed(listingAddress, 0, isBuy, string(abi.encodePacked("Batch update failed: ", reason)));
        } catch {
            emit OrderProcessingFailed(listingAddress, 0, isBuy, "Batch update failed: Unknown error");
        }
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

    function processPrepBuyLiquidCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) external returns (uint256) {
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

    function processPrepSellLiquidCores(address listingAddress, LiquidExecutionState memory state, uint256 orderId) external returns (uint256) {
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
        SecondaryOrderUpdate[] memory tempUpdates = new SecondaryOrderUpdate[](count);
        uint256 validCount = 0;
        for (uint256 i = 0; i < count; i++) {
            try this.processPrepBuyLiquidCores(listingAddress, state, orderIds[i]) returns (uint256 filledValue) {
                tempUpdates[validCount] = buildLiquidSecondaryUpdate(orderIds[i], filledValue, true);
                validCount++;
            } catch Error(string memory reason) {
                emit OrderProcessingFailed(listingAddress, orderIds[i], true, reason);
            } catch {
                emit OrderProcessingFailed(listingAddress, orderIds[i], true, "Unknown error");
            }
        }
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            updates[i] = tempUpdates[i];
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
        SecondaryOrderUpdate[] memory tempUpdates = new SecondaryOrderUpdate[](count);
        uint256 validCount = 0;
        for (uint256 i = 0; i < count; i++) {
            try this.processPrepSellLiquidCores(listingAddress, state, orderIds[i]) returns (uint256 filledValue) {
                tempUpdates[validCount] = buildLiquidSecondaryUpdate(orderIds[i], filledValue, false);
                validCount++;
            } catch Error(string memory reason) {
                emit OrderProcessingFailed(listingAddress, orderIds[i], false, reason);
            } catch {
                emit OrderProcessingFailed(listingAddress, orderIds[i], false, "Unknown error");
            }
        }
        SecondaryOrderUpdate[] memory updates = new SecondaryOrderUpdate[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            updates[i] = tempUpdates[i];
        }
        return updates;
    }
}