# MFPLiquidRouter Contract Documentation

## Overview
The `MFPLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `MFPLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, and `IERC20`. Removes Uniswap V2 functionality, using impact price calculation: `impactPercentage = settlementAmount / xBalance`, adjusting price as `currentPrice * (1 ± impactPercentage)` (plus for buys, minus for sells). Features a fee system (0.01% min, 10% max based on `amountSent` usage), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step`. Uses `ReentrancyGuard` for security. Fees are transferred with `pendingAmount` and recorded in `xFees`/`yFees`. Liquidity updates: for buy orders, `pendingAmount` increases `yLiquid`, `amountOut` decreases `xLiquid`; for sell orders, `pendingAmount` increases `xLiquid`, `amountOut` decreases `yLiquid`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.5 (updated 2025-09-27)

**Inheritance Tree:** `MFPLiquidRouter` → `MFPLiquidPartial` (v0.1.4) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `MFPLiquidPartial.sol` (v0.1.4), `CCLiquidityTemplate.sol` (v0.1.20)

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

## Formulas
Formulas in `MFPLiquidPartial.sol` (v0.1.4) govern settlement and price impact calculations.

1. **Current Price**:
   - **Formula**: `price = listingContract.prices(0)`.
   - **Used in**: `_computeCurrentPrice`, `_validateOrderPricing`, `_processSingleOrder`, `_computeImpactPrice`.
   - **Description**: Fetches price from `ICCListing.prices(0)` with try-catch, ensuring settlement price is within `minPrice` and `maxPrice`. Reverts with detailed reason if fetch fails.
   - **Usage**: Ensures settlement price aligns with `CCListingTemplate` in `_processSingleOrder`.

2. **Impact Price**:
   - **Formula**:
     - `impactPercentage = (normalizedAmountIn * 1e18) / xBalance`.
     - Buy: `impactPrice = (currentPrice * (1e18 + impactPercentage)) / 1e18`.
     - Sell: `impactPrice = (currentPrice * (1e18 - impactPercentage)) / 1e18`.
     - `amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsOut)`.
   - **Used in**: `_computeImpactPrice`, `_processSingleOrder`, `_validateOrderPricing`, `_computeSwapAmount`.
   - **Description**: Calculates price impact based on `settlementAmount/xBalance` ratio, adjusting `currentPrice` upward for buys, downward for sells. Ensures `minPrice <= impactPrice <= maxPrice`.
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

6.  **Fee Calculation**:
    * **Formula**:
        * `usagePercent = (normalize(amountOut, decimalsOut) * 1e18) / normalize(outputLiquidity, decimalsOut)`.
        * `feePercent = usagePercent / 10`.
        * `feePercent = max(1e14, min(1e17, feePercent))` (clamped between 0.01% and 10%).
        * `feeAmount = (pendingAmount * feePercent) / 1e18`; `netAmount = pendingAmount - feeAmount`.
    * **Used in**: `_computeFee` (called by `_processSingleOrder` → `_executeOrderWithFees`).
    * **Description**: A dynamic fee is calculated based on the usage of the **output** liquidity pool (i.e., `xLiquid` for buys, `yLiquid` for sells). The fee percentage is **one-tenth** of the liquidity usage percentage, clamped between a **0.01% minimum** and a **10% maximum**. This incentivizes liquidity providers by scaling fees with slippage. For example, if an order requires `amountSent` of 100 from an available `outputLiquidity` of 120, the usage is 83.33%, resulting in an 8.333% fee.
    * **Usage**: The `feeAmount` is deducted from the user's input (`pendingAmount`) before the swap calculation. The fee is then added to the corresponding fee pool (`yFees` for buys, `xFees` for sells).

7. **Liquidity Updates**:
   - **Formula**:
     - Buy: 
       - Principal: `yLiquid += normalize(pendingAmount)` via `_transferPrincipal` and `_updateLiquidity` (transfers tokenB to liquidity contract, updates `yLiquid` via `ICCLiquidity.ccUpdate`).
       - Settlement: `xLiquid -= normalize(amountOut)` via `_transferSettlement` (transfers tokenA from liquidity contract).
       - Fees: `yFees += normalize(feeAmount)` via `_prepareLiquidityUpdates` (calculates `feeAmount` in `_computeFee`, updates `yFees` via `ICCLiquidity.ccUpdate`).
     - Sell: 
       - Principal: `xLiquid += normalize(pendingAmount)` via `_transferPrincipal` and `_updateLiquidity` (transfers tokenA to liquidity contract, updates `xLiquid` via `ICCLiquidity.ccUpdate`).
       - Settlement: `yLiquid -= normalize(amountOut)` via `_transferSettlement` (transfers tokenB from liquidity contract).
       - Fees: `xFees += normalize(feeAmount)` via `_prepareLiquidityUpdates` (calculates `feeAmount` in `_computeFee`, updates `xFees` via `ICCLiquidity.ccUpdate`).
   - **Used in**: `_prepareLiquidityUpdates`, `_updateLiquidity`, `_transferPrincipal`, `_transferSettlement`, `ICCLiquidity.ccUpdate`.
   - **Description**: Principal transfers (`pendingAmount`) are executed via `ICCListing.transactToken` to the liquidity contract, updating `xLiquid` or `yLiquid`. Settlement transfers (`amountOut`) reduce the opposite liquidity pool (`xLiquid` for buys, `yLiquid` for sells) via `ICCLiquidity.transactToken`. Fees are calculated in `_computeFee`, normalized, and recorded in `xFees` or `yFees` via `ICCLiquidity.ccUpdate`, separate from principal and settlement updates.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address.
  - `maxIterations` (uint256): Maximum orders to process.
  - `step` (uint256): Starting index for gas optimization.
- **Behavior**: Settles buy orders for `msg.sender`. Validates `listingAddress` via `onlyValidListing`, checks `makerPendingOrdersView`, and verifies `yBalance` via `volumeBalances(0)`. Creates `HistoricalUpdate` if orders exist. Processes orders via `_processOrderBatch`, skipping invalid orders (pricing, liquidity). Reverts on critical failures (transfers, `ccUpdate`).
- **Internal Call Flow**:
  - Validates via `onlyValidListing` (uses `ICCAgent.isValidListing`).
  - Checks `pendingOrders` and `step` via `makerPendingOrdersView`.
  - Checks `yBalance` via `volumeBalances(0)`.
  - Calls `_createHistoricalUpdate`:
    - Fetches `volumeBalances(0)`, `prices(0)`, `historicalDataLengthView`, `getHistoricalDataView`.
    - Calls `ccUpdate` with `HistoricalUpdate[]`.
  - Calls `_processOrderBatch(listingAddress, maxIterations, true, step)`:
    - Calls `_collectOrderIdentifiers`.
    - Iterates orders, calls `_processSingleOrder`:
      - Fetches `getBuyOrderAmounts/Core/Pricing`.
      - Calls `_validateOrderPricing` (uses `_computeCurrentPrice`, `_computeImpactPrice`).
      - Validates liquidity via `liquidityAmounts`.
      - Calls `_computeFee` (uses `_fetchLiquidityData`, `_computeUsagePercent`, `_clampFeePercent`, `_calculateFeeAmount`).
      - Calls `_executeOrderWithFees`:
        - Emits `FeeDeducted`.
        - Calls `_computeSwapAmount`, `_prepareLiquidityUpdates` (uses `_fetchOrderData`, `_transferPrincipal`, `_updateLiquidity`, `_transferSettlement`, `_computeResult`).
        - Updates `yLiquid`, `xLiquid`, `yFees` via `ICCLiquidity.ccUpdate`.
        - Calls `executeSingleBuyLiquid` (uses `_prepBuyOrderUpdate`, `_createBuyOrderUpdates`, `ccUpdate`).
- **Emits**: `NoPendingOrders`, `InsufficientBalance`, `UpdateFailed`, `PriceOutOfBounds`, `FeeDeducted`.
- **Graceful Degradation**: Skips orders with invalid pricing, insufficient liquidity, or zero `pendingAmount`.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles sell orders for `msg.sender`. Similar to `settleBuyLiquid`, but checks `xBalance` and updates `xLiquid`, `yLiquid`, `xFees`. Processes via `_processOrderBatch` with `isBuyOrder = false`.
- **Internal Call Flow**: Similar to `settleBuyLiquid`, but uses `getSellOrderAmounts/Core/Pricing`, `_prepSellOrderUpdate`, `_createSellOrderUpdates`, `executeSingleSellLiquid`.
- **Emits**: Same as `settleBuyLiquid`.
- **Graceful Degradation**: Same as `settleBuyLiquid`.

## Internal Functions (MFPLiquidPartial, v0.1.5)
- **_computeCurrentPrice**: Fetches `prices(0)` with try-catch.
- **_computeImpactPrice**: Calculates impact price and `amountOut`.
- **_getTokenAndDecimals**: Retrieves token address and decimals.
- **_validateOrderPricing**: Emits `PriceOutOfBounds` for invalid pricing, returns `false`.
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
- **_executeOrderWithFees**: Emits `FeeDeducted`, updates liquidity, executes order.
- **_processSingleOrder**: Validates and processes single order, skips on errors.
- **_processOrderBatch**: Iterates orders, skips settled orders, returns success.
- **_createBuyOrderUpdates**: Builds `BuyOrderUpdate` structs, sets status.
- **_createSellOrderUpdates**: Builds `SellOrderUpdate` structs, sets status.
- **_finalizeUpdates**: Resizes update arrays.
- **_uint2str**: Converts uint to string.


## Internal Functions (MFPLiquidRouter)
- **_createHistoricalUpdate**: Fetches `volumeBalances(0)`, `prices(0)`, historical data (`xVolume`, `yVolume`); creates `HistoricalUpdate` with `block.timestamp` via `ccUpdate`.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch.
- **Safe Transfers**: `IERC20` with pre/post balance checks in `_transferSettlement`.
Checks exact principal amount transferred from `CCLlistingTemplate` to `CCLiquidityTemplate` before updating `x/yLiquid`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via view functions.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`).
  - Skips settled orders via `pendingAmount == 0` in `_processOrderBatch`.
  - Validates `step <= identifiers.length`.
  - Validates liquidity in `_processSingleOrder` (v0.1.4).
  - Struct-based `ccUpdate` calls with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` (v0.1.4).
  - Optimized struct fields in `MFPLiquidPartial.sol` (v0.1.4).
  - Reverts on critical failures (execution, liquidity updates, transfers) in `_executeOrderWithFees`, `_prepareLiquidityUpdates`, `_transferPrincipal`, `_updateLiquidity`, `_transferSettlement` (v0.1.4).
  - Skips orders with insufficient `xLiquid`/`yLiquid` or invalid pricing in `_processSingleOrder` (v0.1.4).
  - Uses `transactToken` for ERC20, `transactNative` for ETH in `_prepareLiquidityUpdates`, `_transferPrincipal`, `_transferSettlement` (v0.1.4).
  - Captures current `xVolume`, `yVolume` without incrementing in `_executeOrderWithFees` (v0.1.4).

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct token swaps.
- Does not initiate partial fills but completes existing ones (status 2) set by other contracts (e.g., `CCListingTemplate`).
- Zero amounts, failed transfers, or invalid prices return `false` in `_processOrderBatch`.
- `depositor` set to `address(this)` in `ICCLiquidity.ccUpdate` calls, `maker` in `transactToken` for settlement.
- `step` must be <= length of pending orders.
- `amountSent` accumulates total tokens sent across settlements.
- Historical data created at start of settlement if orders exist, updated with current `xVolume`, `yVolume` in `_executeOrderWithFees`.
