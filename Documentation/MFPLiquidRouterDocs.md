# MFPLiquidRouter Contract Documentation

## Overview
The `MFPLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `MFPLiquidPartial` (v0.0.9). It integrates with `ICCListing`, `ICCLiquidity`, and `IERC20`. Removes Uniswap V2 functionality, using impact price calculation: `impactPercentage = normalizedAmountIn * 1e18`, adjusting price as `currentPrice * (1 ± impactPercentage) / 1e18` (plus for buys, minus for sells). Features a fee system (0.05% min at ≤1% liquidity usage, scaling to 0.10% at 2%, 0.50% at 10%, 50% max at 100%), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step`. Uses `ReentrancyGuard`. Fees are transferred with `pendingAmount` and recorded in `xFees`/`yFees`. Liquidity updates: buy orders increase `yLiquid` by `pendingAmount`, decrease `xLiquid` by `amountOut`; sell orders increase `xLiquid`, decrease `yLiquid`. Includes listing balance validation, emitting `ListingBalanceExcess` if exceeded.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.0.9 (updated 2025-10-13)

**Inheritance Tree:** `MFPLiquidRouter` → `MFPLiquidPartial` (v0.0.9) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `MFPLiquidPartial.sol` (v0.0.9), `CCLiquidityTemplate.sol` (v0.1.20)

## Mappings
- None defined in `MFPLiquidRouter`. Uses `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`, `makerPendingOrdersView`) for order tracking.

## Structs
- **HistoricalUpdateContext** (`MFPLiquidRouter`): Holds `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256).
- **OrderContext** (`MFPLiquidPartial`): Holds `listingContract` (ICCListing), `tokenIn`, `tokenOut` (address).
- **PrepOrderUpdateResult** (`MFPLiquidPartial`): Holds `tokenAddress`, `makerAddress`, `recipientAddress` (address), `tokenDecimals`, `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **BuyOrderUpdateContext** (`MFPLiquidPartial`): Holds `makerAddress`, `recipient` (address), `status` (uint8), `amountReceived`, `normalizedReceived`, `amountSent`, `preTransferWithdrawn` (uint256).
- **SellOrderUpdateContext** (`MFPLiquidPartial`): Mirrors `BuyOrderUpdateContext` for sell orders.
- **OrderBatchContext** (`MFPLiquidPartial`): Holds `listingAddress` (address), `maxIterations` (uint256), `isBuyOrder` (bool).
- **FeeContext** (`MFPLiquidPartial`): Holds `feeAmount`, `netAmount`, `liquidityAmount` (uint256), `decimals` (uint8).
- **OrderProcessingContext** (`MFPLiquidPartial`): Holds `maxPrice`, `minPrice`, `currentPrice`, `impactPrice` (uint256).
- **LiquidityUpdateContext** (`MFPLiquidPartial`): Holds `pendingAmount`, `amountOut` (uint256), `tokenDecimals` (uint8), `isBuyOrder` (bool).
- **TransferContext** (`MFPLiquidPartial`): Holds `maker`, `recipient` (address), `status`, `amountSent` (uint256).
- **FeeCalculationContext** (`MFPLiquidPartial`): Holds `normalizedAmountSent`, `normalizedLiquidity`, `feePercent`, `feeAmount` (uint256).
- **ListingBalanceContext** (`MFPLiquidPartial`): Holds `outputToken` (address), `normalizedListingBalance`, `internalLiquidity` (uint256).

## Formulas
Formulas in `MFPLiquidPartial.sol` (v0.0.9) govern settlement, pricing, and fees.

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
   - **Usage**: Restricts settlement if price impact exceeds bounds; emits `PriceOutOfBounds`.

3. **Fee Calculation**:
   - **Formula**:
     - `usagePercent = (normalizedAmountSent * 1e18) / normalizedLiquidity`.
     - `feePercent = (usagePercent * 5e15) / 1e16` (0.05% per 1% usage).
     - `feePercent = max(5e14, min(5e17, feePercent))` (0.05% min, 50% max).
     - `feeAmount = (amountIn * feePercent) / 1e18`, `netAmount = amountIn - feeAmount`.
   - **Used in**: `_computeFee` → `_fetchLiquidityData`, `_computeUsagePercent`, `_clampFeePercent`, `_calculateFeeAmount`.
   - **Description**: Scales fees linearly with liquidity usage (0.05% at ≤1%, 0.10% at 2%, 0.50% at 10%, 50% at 100%). Applied in `_executeOrderWithFees`.
   - **Usage**: Emits `FeeDeducted` with `feeAmount` and `netAmount`.

4. **Buy Order Output**:
   - **Formula**: `amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsA)`.
   - **Used in**: `_computeImpactPrice`, `_computeSwapAmount`, `_processSingleOrder`.
   - **Description**: Computes tokenA output for buy orders, aligning with `buyOutput ≈ buyPrincipal / currentPrice`.

5. **Sell Order Output**:
   - **Formula**: `amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsB)`.
   - **Used in**: `_computeImpactPrice`, `_computeSwapAmount`, `_processSingleOrder`.
   - **Description**: Computes tokenB output for sell orders, aligning with `sellOutput ≈ sellPrincipal * currentPrice`.

6. **Normalization/Denormalization**:
   - **Normalize**: `normalize(amount, decimals) = decimals < 18 ? amount * 10^(18-decimals) : amount / 10^(decimals-18)`.
   - **Denormalize**: `denormalize(amount, decimals) = decimals < 18 ? amount / 10^(18-decimals) : amount * 10^(decimals-18)`.
   - **Used in**: `_computeImpactPrice`, `_fetchOrderData`, `_updateLiquidity`, `_computeResult`, `_processSingleOrder`, `_prepareLiquidityUpdates`, `_computeFee`, `_executeOrderWithFees`.
   - **Description**: Ensures 18-decimal precision for calculations.

## External Functions
### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress`: Address of `ICCListing` contract.
  - `maxIterations`: Maximum orders to process in batch (gas control).
  - `step`: Starting index in `makerPendingOrdersView` (gas-efficient slicing).
- **Behavior**: Settles buy orders for `msg.sender`. Validates listing, checks pending orders via `makerPendingOrdersView`. If none or `step >= length`, emits `NoPendingOrders`. Calls `_createHistoricalUpdate` if orders exist, then `_processOrderBatch`. Emits `UpdateFailed` if batch fails.
- **External Call Tree**:
  - `ICCListing.makerPendingOrdersView(msg.sender)`: Fetches order IDs.
  - `ICCListing.ccUpdate`: Updates historical data via `_createHistoricalUpdate`.
  - `ICCListing.getBuyOrderAmounts`: Fetches `pendingAmount` in `_processOrderBatch` → `_processSingleOrder`.
  - `ICCLiquidity.liquidityAmounts`: Validates `xLiquid`, `yLiquid` in `_processSingleOrder`.
  - `ICCListing.getBuyOrderPricing`: Validates pricing in `_validateOrderPricing`.
  - `ICCListing.prices(0)`: Fetches price in `_computeCurrentPrice`, `_computeImpactPrice`.
  - `IERC20.balanceOf`, `ICCListing.liquidityAddressView`: Validates listing balance in `_processSingleOrder`.
  - `ICCLiquidity.ccUpdate`, `ICCListing.transactToken/Native`: Updates liquidity and transfers tokens in `_executeOrderWithFees` → `_prepareLiquidityUpdates`.
- **Emits**: `NoPendingOrders`, `UpdateFailed`, `PriceOutOfBounds`, `InsufficientBalance`, `ListingBalanceExcess`, `FeeDeducted`, `TokenTransferFailed`.
- **Graceful Degradation**: Skips invalid orders (pricing, liquidity, balance); returns `false` on non-critical errors.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles sell orders for `msg.sender`. Mirrors buy logic, using `getSellOrderAmounts`, `SellOrderUpdate[]`.
- **External Call Tree**: Similar to `settleBuyLiquid`, using sell-specific `ICCListing` functions.
- **Emits**: Same as `settleBuyLiquid`, sell-specific.
- **Graceful Degradation**: Identical.

## Internal Functions (MFPLiquidPartial, v0.0.9)
- **_computeCurrentPrice**: Fetches `prices(0)` with try-catch. Called by `settleBuy/SellLiquid` → `_processOrderBatch` → `_processSingleOrder` → `_validateOrderPricing`, `_computeImpactPrice`.
- **_computeImpactPrice**: Calculates impact price and `amountOut`. Called by `_processSingleOrder` → `_validateOrderPricing`, `_computeSwapAmount`.
- **_getTokenAndDecimals**: Retrieves token address and decimals. Called by `_processSingleOrder` → `_fetchOrderData`, `_computeFee`.
- **_checkPricing**: Validates `impactPrice` against `maxPrice`/`minPrice`. Called by `_processSingleOrder` → `_validateOrderPricing`.
- **_validateOrderPricing**: Returns `OrderProcessingContext`, emits `PriceOutOfBounds`. Called by `_processSingleOrder`.
- **_fetchLiquidityData**: Fetches `xLiquid`, `yLiquid`, decimals for fees. Called by `_computeFee`.
- **_computeUsagePercent**: Calculates fee percentage (0.05% at ≤1%, 50% at 100%). Called by `_computeFee`.
- **_clampFeePercent**: Enforces 0.05%-50% bounds. Called by `_computeFee`.
- **_calculateFeeAmount**: Computes `feeAmount`, `netAmount`. Called by `_computeFee`.
- **_computeFee**: Coordinates fee calculation. Called by `_processSingleOrder`.
- **_computeSwapAmount**: Computes `amountOut` for updates. Called by `_executeOrderWithFees`.
- **_toSingleUpdateArray**: Converts update to array. Called by `_prepareLiquidityUpdates`.
- **_prepareLiquidityUpdates**: Transfers input, updates `xLiquid`, `yLiquid`, `xFees`/`yFees`. Called by `_executeOrderWithFees`.
- **_fetchOrderData**: Fetches order/token data. Called by `_prepBuy/SellOrderUpdate`.
- **_transferPrincipal**: Transfers principal to liquidity contract. Called by `_prepBuy/SellOrderUpdate`.
- **_updateLiquidity**: Updates `xLiquid`/`yLiquid`. Called by `_prepBuy/SellOrderUpdate`.
- **_transferSettlement**: Transfers settlement token with balance checks. Called by `_prepBuy/SellOrderUpdate`.
- **_computeResult**: Sets status (3 if `newPending == 0`, else 2). Called by `_prepBuy/SellOrderUpdate`.
- **_prepBuyOrderUpdate**: Coordinates buy order settlement. Called by `_executeOrderWithFees` → `executeSingleBuyLiquid`.
- **_prepSellOrderUpdate**: Coordinates sell order settlement. Called by `_executeOrderWithFees` → `executeSingleSellLiquid`.
- **_executeOrderWithFees**: Emits `FeeDeducted`, updates liquidity, executes order, updates historical data. Called by `_processSingleOrder`.
- **_processSingleOrder**: Validates pricing, liquidity, listing balance; processes order, skips on errors. Called by `_processOrderBatch`.
- **_processOrderBatch**: Iterates orders, skips settled ones, returns success. Called by `settleBuy/SellLiquid`.
- **_createBuyOrderUpdates**: Builds `BuyOrderUpdate` structs. Called by `executeSingleBuyLiquid`.
- **_createSellOrderUpdates**: Builds `SellOrderUpdate` structs. Called by `executeSingleSellLiquid`.
- **_finalizeUpdates**: Resizes update arrays. Called by `executeSingleBuy/SellLiquid`.
- **_uint2str**: Converts uint to string. Called by error emissions.

## Internal Functions (MFPLiquidRouter)
- **_createHistoricalUpdate**: Creates `HistoricalUpdate` with `prices(0)`, `xVolume`, `yVolume`, `block.timestamp`. Called by `settleBuy/SellLiquid` if orders exist. Calls `ICCListing.ccUpdate`.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuy/SellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch.
- **Safe Transfers**: `IERC20` with pre/post balance checks in `_transferSettlement`. Ensures exact principal transfer via `transactToken/Native`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state (`agent`, `uniswapV2Router`) accessed via view functions.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `TokenTransferFailed`, `ListingBalanceExcess`).
  - Skips settled orders (`pendingAmount == 0`) in `_processOrderBatch`.
  - Validates `step <= identifiers.length`.
  - Validates liquidity and listing balance in `_processSingleOrder`.
  - Struct-based `ccUpdate` calls with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate`.
  - Reverts on critical failures (execution, transfers, updates) in `_executeOrderWithFees`, `_prepareLiquidityUpdates`, `_transferPrincipal`, `_updateLiquidity`, `_transferSettlement`.
  - Uses `transactToken/Native` for safe transfers.
  - Captures `xVolume`, `yVolume` without incrementing in `_executeOrderWithFees`.

## Key Insights
- Relies on `ICCLiquidity` for settlements, not direct swaps.
- Completes partial fills (status 2) set by `CCListingTemplate`.
- Zero amounts, failed transfers, invalid prices, or excessive listing balance return `false`.
- `depositor` set to `address(this)` in `ccUpdate`, `maker` in `transactToken`.
- `step` must be ≤ pending orders length.
- `amountSent` accumulates across settlements.
- Historical data created at batch start and per-order, using current `xVolume`, `yVolume`.
- Fee scaling incentivizes liquidity provision.
- Restricts liquid settlement if Uniswap v2 LP Balance for the output token is grearter than the liquidity template balance.

### Critical vs Non-Critical Issues
- **Critical Errors**:
  - **Invalid Listing/Configuration**: `onlyValidListing` must pass; `agent` required.
  - **Failed Updates/Transfers**: `_prepareLiquidityUpdates`, `_transferPrincipal`, `_transferSettlement` revert on failure.
- **Non-Critical Errors**:
  - **Invalid Pricing**: Emits `PriceOutOfBounds`, skips order.
  - **Insufficient Liquidity**: Emits `InsufficientBalance`, skips order.
  - **Excessive Listing Balance**: Emits `ListingBalanceExcess`, skips order.
