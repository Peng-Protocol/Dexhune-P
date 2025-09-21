# MFPLiquidRouter Contract Documentation

## Overview
The `MFPLiquidRouter` contract (Solidity ^0.8.2) settles buy/sell orders using `ICCLiquidity`, inheriting `MFPLiquidPartial`. It integrates with `ICCListing`, `ICCLiquidity`, and `IERC20`. Removes Uniswap V2 functionality, replacing it with a new impact price calculation: `impactPercentage = settlementAmount / xBalance`, adjusting price as `currentPrice * (1 ± impactPercentage)` (plus for buys, minus for sells). Features a fee system (max 1% based on liquidity usage), user-specific settlement via `makerPendingOrdersView`, and gas-efficient iteration with `step`. Uses `ReentrancyGuard` for security. Fees are transferred with `pendingAmount` and recorded in `xFees`/`yFees`. Liquidity updates: for buy orders, `pendingAmount` increases `yLiquid`, `amountOut` decreases `xLiquid`; for sell orders, `pendingAmount` increases `xLiquid`, `amountOut` decreases `yLiquid`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.0 (updated 2025-09-21)

**Inheritance Tree:** `MFPLiquidRouter` → `MFPLiquidPartial` (v0.0.46) → `CCMainPartial` (v0.1.5)

**Compatibility:** `CCListingTemplate.sol` (v0.3.9), `ICCLiquidity.sol` (v0.0.5), `CCMainPartial.sol` (v0.1.5), `MFPLiquidPartial.sol` (v0.0.46), `CCLiquidityTemplate.sol` (v0.1.18)

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

## Formulas
Formulas in `MFPLiquidPartial.sol` (v0.0.46) govern settlement and price impact calculations.

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
   - **Used in**: `_computeImpactPrice`, `_prepBuy/SellOrderUpdate`, `_processSingleOrder`, `_prepareLiquidityUpdates`, `_computeFee`, `_executeOrderWithFees`.
   - **Description**: Ensures 18-decimal precision for calculations, reverting to native decimals for transfers.

6. **Fee Calculation**:
   - **Formula**: `feePercent = (normalizedPending / normalizedLiquidity) * 1e18`, capped at 1%; `feeAmount = (pendingAmount * feePercent) / 1e20`; `netAmount = pendingAmount - feeAmount`.
   - **Used in**: `_computeFee`, `_executeOrderWithFees`, `_prepareLiquidityUpdates`.
   - **Description**: Calculates fee based on liquidity usage (`xLiquid` for sell, `yLiquid` for buy).

7. **Liquidity Updates**:
   - **Formula**:
     - Buy: `yLiquid += normalize(pendingAmount)`, `xLiquid -= normalize(amountOut)`, `yFees += normalize(feeAmount)`.
     - Sell: `xLiquid += normalize(pendingAmount)`, `yLiquid -= normalize(amountOut)`, `xFees += normalize(feeAmount)`.
   - **Used in**: `_prepareLiquidityUpdates`, `ICCLiquidity.ccUpdate`.

## External Functions

### settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**:
  - `listingAddress` (address): `ICCListing` contract address for order book.
  - `maxIterations` (uint256): Maximum orders to process in a batch.
  - `step` (uint256): Starting index for order processing (gas optimization).
- **Behavior**: Settles buy orders for `msg.sender`. Checks pending orders via `makerPendingOrdersView(msg.sender)` and `yBalance` via `volumeBalances(0)`. Creates historical data entry via `_createHistoricalUpdate` if orders exist. Processes orders via `_processOrderBatch`, which handles `ccUpdate` with `BuyOrderUpdate` structs. Emits events for failures. Validates `xLiquid` and `yLiquid` before settlement, skipping orders with insufficient liquidity or invalid pricing. Does not initiate partial fills but can complete existing ones (status 2).
- **Internal Call Flow**:
  - Validates listing with `onlyValidListing`.
  - Checks `pendingOrders` length and `step` via `makerPendingOrdersView`.
  - Checks `yBalance` via `volumeBalances(0)`.
  - Calls `_createHistoricalUpdate`:
    - Fetches `volumeBalances(0)`, `prices(0)`, `historicalDataLengthView`, `getHistoricalDataView`.
    - Creates `HistoricalUpdate` with current `xVolume`, `yVolume`.
    - Calls `ccUpdate` with `HistoricalUpdate[]`.
  - Calls `_processOrderBatch(listingAddress, maxIterations, true, step)`:
    - Calls `_collectOrderIdentifiers` to fetch order IDs.
    - Iterates orders, calls `_processSingleOrder`:
      - Fetches `getBuyOrderAmounts/Core/Pricing`.
      - Calls `_validateOrderPricing` (uses `_computeCurrentPrice`, `_computeImpactPrice`).
      - Validates liquidity via `liquidityAmounts`.
      - Calls `_computeFee`, `_executeOrderWithFees`:
        - Emits `FeeDeducted`.
        - Calls `_computeSwapAmount`, `_prepareLiquidityUpdates` (updates `yLiquid`, `xLiquid`, `yFees` via `ccUpdate`).
        - Creates `HistoricalUpdate` with current `xVolume`, `yVolume`.
        - Calls `executeSingleBuyLiquid`:
          - Calls `_prepBuyOrderUpdate`, `_createBuyOrderUpdates`.
          - Executes `ccUpdate` with `BuyOrderUpdate[]`.
- **Emits**: `NoPendingOrders` (empty orders or invalid step), `InsufficientBalance` (zero `yBalance` or insufficient `xLiquid`/`yLiquid`), `UpdateFailed` (batch processing failure), `PriceOutOfBounds` (invalid pricing).
- **Graceful Degradation**: Returns without reverting if no orders, `step` exceeds orders, or insufficient balance. Skips orders with insufficient liquidity or invalid pricing.
- **Note**: `amountSent` (tokenA) accumulates total tokens sent across settlements.

### settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step)
- **Parameters**: Same as `settleBuyLiquid`.
- **Behavior**: Settles sell orders for `msg.sender`. Checks pending orders via `makerPendingOrdersView(msg.sender)` and `xBalance` via `volumeBalances(0)`. Creates historical data entry via `_createHistoricalUpdate` if orders exist. Processes orders via `_processOrderBatch`, which handles `ccUpdate` with `SellOrderUpdate` structs. Emits events for failures. Validates `xLiquid` and `yLiquid` before settlement, skipping orders with insufficient liquidity or invalid pricing. Does not initiate partial fills but can complete existing ones (status 2).
- **Internal Call Flow**: Similar to `settleBuyLiquid`, but:
  - Uses `xBalance` from `volumeBalances(0)`.
  - Calls `_processOrderBatch(listingAddress, maxIterations, false, step)`:
    - Uses `getSellOrderAmounts/Core/Pricing`.
    - Updates `xLiquid`, `yLiquid`, `xFees` in `_prepareLiquidityUpdates`.
    - Calls `executeSingleSellLiquid`:
      - Calls `_prepSellOrderUpdate`, `_createSellOrderUpdates`.
      - Executes `ccUpdate` with `SellOrderUpdate[]`.
- **Emits**: `NoPendingOrders`, `InsufficientBalance` (zero `xBalance` or insufficient `xLiquid`/`yLiquid`), `UpdateFailed`, `PriceOutOfBounds`.
- **Graceful Degradation**: Same as `settleBuyLiquid`.
- **Note**: `amountSent` (tokenB) accumulates total tokens sent across settlements.

## Internal Functions (MFPLiquidPartial, v0.0.46)
- **_computeCurrentPrice**: Fetches price from `ICCListing.prices(0)` with try-catch.
- **_computeImpactPrice**: Calculates price impact as `currentPrice * (1 ± settlementAmount/xBalance)` and `amountOut` based on `currentPrice`.
- **_getTokenAndDecimals**: Retrieves token address and decimals.
- **_validateOrderPricing**: Validates prices, emits `PriceOutOfBounds`.
- **_computeFee**: Calculates `feeAmount`, `netAmount` based on liquidity usage.
- **_computeSwapAmount**: Computes `amountOut` for liquidity updates.
- **_toSingleUpdateArray**: Converts single update to array for `ICCLiquidity.ccUpdate`.
- **_prepareLiquidityUpdates**: Transfers `pendingAmount` (via `transactToken` for ERC20, `transactNative` for ETH), updates `xLiquid`, `yLiquid`, `xFees`/`yFees` via `ICCLiquidity.ccUpdate`, reverts on critical failures.
- **_prepBuyOrderUpdate**: Handles buy order transfers, sets `amountSent` (tokenA) with pre/post balance checks.
- **_prepSellOrderUpdate**: Handles sell order transfers, sets `amountSent` (tokenB) with pre/post balance checks.
- **_executeOrderWithFees**: Emits `FeeDeducted`, creates `HistoricalUpdate` with current `xVolume`, `yVolume`, executes order via `executeSingleBuy/SellLiquid`, reverts on critical failures.
- **_processSingleOrder**: Validates prices and liquidity, computes fees, executes order, skips on insufficient liquidity or invalid pricing.
- **_processOrderBatch**: Iterates orders, skips settled orders (pendingAmount == 0), returns success status.
- **_createBuyOrderUpdates**: Builds `BuyOrderUpdate` structs for `ccUpdate`, sets status (0: cancelled, 2: partially filled, 3: filled). If `pendingAmount == 0` when fetched in `_processOrderBatch`, the order is skipped. During settlement, if `pendingAmount == 0` (e.g., fully processed or malformed) and no tokens are transferred, `newStatus` is set to 0 (cancelled). Status 3 (filled) is set when `preTransferWithdrawn >= pendingAmount`. Status 2 (partially filled) is set when `preTransferWithdrawn < pendingAmount`.
- **_createSellOrderUpdates**: Builds `SellOrderUpdate` structs for `ccUpdate`, sets status similarly to `_createBuyOrderUpdates`.
- **_finalizeUpdates**: Resizes `BuyOrderUpdate[]` or `SellOrderUpdate[]` based on `isBuyOrder`.
- **_uint2str**: Converts uint to string for error messages.

## Internal Functions (MFPLiquidRouter)
- **_createHistoricalUpdate**: Fetches `volumeBalances(0)`, `prices(0)`, historical data (`xVolume`, `yVolume`); creates `HistoricalUpdate` with `block.timestamp` via `ccUpdate`.

## Security Measures
- **Reentrancy Protection**: `nonReentrant` on `settleBuyLiquid`, `settleSellLiquid`.
- **Listing Validation**: `onlyValidListing` uses `ICCAgent.isValidListing` with try-catch.
- **Safe Transfers**: `IERC20` with pre/post balance checks in `_prepBuy/SellOrderUpdate`.
- **Safety**:
  - Explicit casting for interfaces.
  - No inline assembly.
  - Hidden state variables (`agent`, `uniswapV2Router`) accessed via view functions.
  - Avoids reserved keywords, `virtual`/`override`.
  - Graceful degradation with events (`NoPendingOrders`, `InsufficientBalance`, `PriceOutOfBounds`, `UpdateFailed`, `ApprovalFailed`, `TokenTransferFailed`, `SwapFailed`).
  - Skips settled orders via `pendingAmount == 0` in `_processOrderBatch`.
  - Validates `step <= identifiers.length`.
  - Validates liquidity in `_processSingleOrder` (v0.0.46).
  - Struct-based `ccUpdate` calls with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` (v0.0.26).
  - Optimized struct fields in `MFPLiquidPartial.sol` (v0.0.46).
  - Reverts on critical failures (execution, liquidity updates, transfers) in `_executeOrderWithFees`, `_prepareLiquidityUpdates` (v0.0.46).
  - Skips orders with insufficient `xLiquid`/`yLiquid` or invalid pricing in `_processSingleOrder` (v0.0.46).
  - Uses `transactToken` for ERC20, `transactNative` for ETH in `_prepareLiquidityUpdates` (v0.0.46).
  - Captures current `xVolume`, `yVolume` without incrementing in `_executeOrderWithFees` (v0.0.46).

## Limitations and Assumptions
- Relies on `ICCLiquidity` for settlements, not direct token swaps.
- Does not initiate partial fills but completes existing ones (status 2) set by other contracts (e.g., `CCListingTemplate`).
- Zero amounts, failed transfers, or invalid prices return `false` in `_processOrderBatch`.
- `depositor` set to `address(this)` in `ICCLiquidity` calls.
- `step` must be <= length of pending orders.
- `amountSent` accumulates total tokens sent across settlements.
- Historical data created at start of settlement if orders exist, updated with current `xVolume`, `yVolume` in `_executeOrderWithFees`.
