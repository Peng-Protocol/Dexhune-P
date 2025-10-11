# MFPLiquidRouter Contract Documentation

## Overview
The `MFPLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `MFPLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, and `IERC20`. Removes Uniswap V2 functionality, using impact price calculation: `impactPercentage = normalizedAmountIn * 1e18`, adjusting price as `currentPrice * (1 ± impactPercentage) / 1e18` (plus for buys, minus for sells). Features a fee system (0.01% min, 10% max based on `amountSent` usage), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step`. Uses `ReentrancyGuard` for security. Fees are transferred with `pendingAmount` and recorded in `xFees`/`yFees`. Liquidity updates: for buy orders, `pendingAmount` increases `yLiquid`, `amountOut` decreases `xLiquid`; for sell orders, `pendingAmount` increases `xLiquid`, `amountOut` decreases `yLiquid`. Includes listing balance validation, emitting `ListingBalanceExcess` if exceeded.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.8 (updated 2025-10-11)

**Inheritance Tree:** `MFPLiquidRouter` → `MFPLiquidPartial` (v0.0.8) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `MFPLiquidPartial.sol` (v0.0.8), `CCLiquidityTemplate.sol` (v0.1.20)

## Mappings
- None defined in `MFPLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`) for order tracking.

## Structs
- **HistoricalUpdateContext** (`MFPLiquidRouter`): Holds `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256).
- **OrderContext** (`MFPLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn`, `tokenOut` (address).
- **PrepOrderUpdateResult** (`MFPLiquidPartial`): Holds `tokenAddress`, `makerAddress`, `recipientAddress` (address), `tokenDecimals`, `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **BuyOrderUpdateContext** (`MFPLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **SellOrderUpdateContext** (`MFPLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **OrderBatchContext** (`MFPLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **FeeContext** (`MFPLiquidPartial`): Holds `feeAmount`, `netAmount`, `liquidityAmount` (uint256), `decimals` (uint8).
- **OrderProcessingContext** (`MFPLiquidPartial`): Holds `maxPrice`, `minPrice`, `currentPrice`, `impactPrice` (uint256).
- **LiquidityUpdateContext** (`MFPLiquidPartial`): Holds `pendingAmount`, `amountOut` (uint256), `tokenDecimals` (uint8), `isBuyOrder` (bool).
- **TransferContext** (`MFPLiquidPartial`): Holds `maker`, `recipient` (address), `status`, `amountSent` (uint256).
- **FeeCalculationContext** (`MFPLiquidPartial`): Holds `normalizedAmountSent`, `normalizedLiquidity`, `feePercent`, `feeAmount` (uint256).
- **ListingBalanceContext** (`MFPLiquidPartial`): Holds `outputToken` (address), `normalizedListingBalance`, `internalLiquidity` (uint256).

## Formulas
Formulas in `MFPLiquidPartial.sol` (v0.0.8) govern settlement and price impact calculations.

1. **Current Price**:
   - **Formula**: `price = listingContract.prices(0)`.
   - **Used in**: `_computeCurrentPrice`, `_validateOrderPricing`, `_processSingleOrder`, `_computeImpactPrice`.
   - **Description**: Fetches price from `ICCListing.prices(0)` with try-catch, ensuring settlement price is within `minPrice` and `maxPrice`. Reverts with detailed reason if fetch fails.
   - **Usage**: Ensures settlement price aligns with `CCListingTemplate` in `_processSingleOrder`.

2. **Impact Price**:
   - **Formula**:
     - `impactPercentage = normalizedAmountIn * 1e18`.
     - Buy: `impactPrice = (currentPrice * (1e18 + impactPercentage)) / 1e18`.
     - Sell: `impactPrice = (currentPrice * (1e18 - impactPercentage)) / 1e18`.
     - `amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsOut)`.
   - **Used in**: `_computeImpactPrice`, `_processSingleOrder`, `_validateOrderPricing`, `_computeSwapAmount`.
   - **Description**: Calculates price impact based on `normalizedAmountIn`, adjusting `currentPrice` upward for buys, downward for sells. Ensures `minPrice <= impactPrice <= maxPrice`.
   - **Usage**: Restricts settlement if price impact exceeds bounds; emits `PriceOutOfBounds` for graceful degradation.

3. **Buy Order Output**:
   - **Formula**: `amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsA)`.
   - **Used in**: `_computeImpactPrice`, `_computeSwapAmount`, `_processSingleOrder`.
   - **Description**: Computes tokenA output for buy orders, aligning with `buyOutput ≈ buyPrincipal / currentPrice`.

4. **Sell Order Output**:
   - **Formula**: `amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsB)`.
   - **Used in**: `_computeImpactPrice`, `_computeSwapAmount`, `_processSingleOrder`.
   - **Description**: Computes tokenB output for sell orders, aligning with `sellOutput ≈ sellPrincipal * currentPrice`.

5. **Normalization/Denormalization**:
   - **Normalize**: `normalize(amount, decimals) = decimals < 18 ? amount * 10^(18-decimals) : amount / 10^(decimals-18)`.
   - **Denormalize**: `denormalize(amount, decimals) = decimals < 18 ? amount / 10^(18-decimals) : amount * 10^(decimals-18)`.
   - **Used in**: `_computeImpactPrice`, `_fetchOrderData`, `_updateLiquidity`, `_computeResult`, `_processSingleOrder`, `_prepareLiquidityUpdates`, `_computeFee`, `_executeOrderWithFees`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

6. **Fee Calculation**:
   - **Formula**:
     - `usagePercent = (normalizedAmountSent * 1e18) / normalizedLiquidity`.
     - `feePercent = clamp(usagePercent, 0.01%, 10%)`.
     - `feeAmount = (amount * feePercent) / 1e18`.
     - `netAmount = amount - feeAmount`.
   - **Used in**: `_computeFee`, `_fetchLiquidityData`, `_computeUsagePercent`, `_clampFeePercent`, `_calculateFeeAmount`, `_executeOrderWithFees`.
   - **Description**: Scales fees between 0.01% and 10% based on usage, applied to `amountSent`.

7. **Listing Balance Check**:
   - **Formula**:
     - `normalizedListingBalance = normalize(tokenBalance, decimalsA/decimalsB)`.
     - Check: `normalizedListingBalance > internalLiquidity ? emit ListingBalanceExcess : proceed`.
   - **Used in**: `_processSingleOrder`.
   - **Description**: Validates listing contract’s token balance against internal liquidity (`xLiquid`/`yLiquid`), emitting `ListingBalanceExcess` if exceeded.

## External Functions (MFPLiquidRouter)
- **settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)**:
  - **Call Tree**: Calls `_createHistoricalUpdate` (creates `HistoricalUpdate` via `ccUpdate`), `_processOrderBatch` (iterates orders, calls `_processSingleOrder`), which calls `_validateOrderPricing`, `_computeImpactPrice`, `_computeFee`, `_executeOrderWithFees`, `_prepareLiquidityUpdates`, `_fetchOrderData`, `_transferPrincipal`, `_updateLiquidity`, `_transferSettlement`, `_computeResult`, `_prepBuyOrderUpdate`, `_createBuyOrderUpdates`, `executeSingleBuyLiquid`.
  - **Description**: Settles buy orders for `msg.sender` using `makerPendingOrdersView`. Validates listing, checks pending orders, creates historical update if orders exist, processes batch with `maxIterations` and `step`. Emits `NoPendingOrders` or `UpdateFailed` on failure.
  - **Emits**: `NoPendingOrders`, `UpdateFailed`.
  - **Graceful Degradation**: Returns on empty/invalid orders or step overflow, emits events for non-critical failures.

- **settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)**:
  - **Call Tree**: Similar to `settleBuyLiquid`, but for sell orders, calling `_prepSellOrderUpdate`, `_createSellOrderUpdates`, `executeSingleSellLiquid`.
  - **Description**: Settles sell orders for `msg.sender`. Same validation and update logic as `settleBuyLiquid`.
  - **Emits**: `NoPendingOrders`, `UpdateFailed`.
  - **Graceful Degradation**: Same as `settleBuyLiquid`.

## Internal Functions (MFPLiquidPartial, v0.0.8)
- **_computeCurrentPrice**: Fetches `prices(0)` with try-catch.
- **_computeImpactPrice**: Calculates impact price and `amountOut`.
- **_getTokenAndDecimals**: Retrieves token address and decimals.
- **_checkPricing**: Validates `impactPrice` against `maxPrice`/`minPrice`.
- **_validateOrderPricing**: Emits `PriceOutOfBounds` for invalid pricing, returns `OrderProcessingContext`.
- **_fetchLiquidityData**: Fetches liquidity amounts and decimals for fee calculation.
- **_computeUsagePercent**: Calculates usage percentage for fees.
- **_clampFeePercent**: Clamps fee between 0.01% and 10%.
- **_calculateFeeAmount**: Computes `feeAmount`, `netAmount`.
- **_computeFee**: Coordinates fee calculation using helper functions.
- **_computeSwapAmount**: Computes `amountOut` for liquidity updates.
- **_toSingleUpdateArray**: Converts single update to array for `ICCLiquidity.ccUpdate`.
- **_prepareLiquidityUpdates**: Updates `xLiquid`, `yLiquid`, `xFees`/`yFees` via `ICCLiquidity.ccUpdate`, transfers tokens, reverts on critical failures.
- **_fetchOrderData**: Fetches order and token data.
- **_transferPrincipal**: Transfers principal to liquidity contract.
- **_updateLiquidity**: Updates `xLiquid`/`yLiquid` for principal.
- **_transferSettlement**: Transfers settlement token, uses pre/post balance checks.
- **_computeResult**: Sets status (3 if `newPending == 0`, else 2), builds `PrepOrderUpdateResult`.
- **_prepBuyOrderUpdate**: Coordinates buy order settlement.
- **_prepSellOrderUpdate**: Coordinates sell order settlement.
- **_executeOrderWithFees**: Emits `FeeDeducted`, updates liquidity, executes order, updates historical data.
- **_processSingleOrder**: Validates pricing, liquidity, and listing balance; processes single order, skips on errors.
- **_processOrderBatch**: Iterates orders, skips settled orders, returns success.
- **_createBuyOrderUpdates**: Builds `BuyOrderUpdate` structs, sets status.
- **_createSellOrderUpdates**: Builds `SellOrderUpdate` structs, sets status.
- **_finalizeUpdates**: Resizes update arrays.
- **_uint2str**: Converts uint to string.

## Internal Functions (MFPLiquidRouter)
- **_createHistoricalUpdate**: Fetches `prices(0)`, historical data (`xVolume`, `yVolume`); creates `HistoricalUpdate` with `block.timestamp` via `ccUpdate`. Sets `xBalance`, `yBalance` to 0 as unused.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch.
- **Safe Transfers**: `IERC20` with pre/post balance checks in `_transferSettlement`. Checks exact principal amount transferred from `CCListingTemplate` to `CCLiquidityTemplate` before updating `x/yLiquid`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via view functions.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`, `ListingBalanceExcess`).
  - Skips settled orders via `pendingAmount == 0` in `_processOrderBatch`.
  - Validates `step <= identifiers.length`.
  - Validates liquidity and listing balance in `_processSingleOrder` (v0.0.8).
  - Struct-based `ccUpdate` calls with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate`.
  - Optimized struct fields in `MFPLiquidPartial.sol` (v0.0.8).
  - Reverts on critical failures (execution, liquidity updates, transfers) in `_executeOrderWithFees`, `_prepareLiquidityUpdates`, `_transferPrincipal`, `_updateLiquidity`, `_transferSettlement`.
  - Skips orders with insufficient `xLiquid`/`yLiquid`, invalid pricing, or excessive listing balance in `_processSingleOrder` (v0.0.8).
  - Uses `transactToken` for ERC20, `transactNative` for ETH in `_prepareLiquidityUpdates`, `_transferPrincipal`, `_transferSettlement`.
  - Captures current `xVolume`, `yVolume` without incrementing in `_executeOrderWithFees`.

## Key Insights
- Relies on `ICCLiquidity` for settlements, not direct token swaps.
- Does not initiate partial fills but completes existing ones (status 2) set by other contracts (e.g., `CCListingTemplate`).
- Zero amounts, failed transfers, invalid prices, or excessive listing balance return `false` in `_processOrderBatch`.
- `depositor` set to `address(this)` in `ICCLiquidity.ccUpdate` calls, `maker` in `transactToken` for settlement.
- `step` must be <= length of pending orders.
- `amountSent` accumulates total tokens sent across settlements.
- Historical data created at start of settlement if orders exist, updated with current `xVolume`, `yVolume` in `_executeOrderWithFees`.

### Critical vs Non-Critical Issues
- **Critical Errors**:
  - **Invalid Listing or Configuration**: `onlyValidListing` call to `ICCAgent` must pass. `agent` must be set.
  - **Failed Liquidity or Fee Updates**: `_prepareLiquidityUpdates` reverts on `ccUpdate` failure.
  - **Failed Token Transfers**: `_prepareLiquidityUpdates`, `_transferPrincipal`, `_transferSettlement` revert on `transactToken`/`transactNative` failure.
- **Non-Critical Errors**:
  - **Invalid Pricing**: `_processSingleOrder` emits `PriceOutOfBounds`, returns `false`.
  - **Insufficient Liquidity**: `_processSingleOrder` emits `InsufficientBalance`, returns `false`.
  - **Excessive Listing Balance**: `_processSingleOrder` emits `ListingBalanceExcess`, returns `false`.
