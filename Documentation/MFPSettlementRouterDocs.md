# MFPSettlementRouter Contract Documentation

## Overview
The `MFPSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform by directly transferring tokens from the listing template to the order recipient, based on the current price and constrained by min/max price bounds. It inherits from `MFPSettlementPartial`, which extends `CCMainPartial`, integrating with `ICCListing` and `IERC20` interfaces for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. It eliminates Uniswap V2 dependency, using impact price calculations and partial settlement logic. It ensures gas optimization with `step` and `maxIterations`, robust error handling with try-catch, non-reverting behavior for individual order issues, and decimal precision via `normalize`/`denormalize`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.5 (updated 2025-09-29)

**Inheritance Tree:** `MFPSettlementRouter` → `MFPSettlementPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `MFPSettlementPartial.sol` (v0.1.5)

### Changes
- **v0.1.5**: Redid 0.1.4, adjusted `_executeOrderSwap` and `_prepareUpdateData` (29/9).
- **v0.1.4**: Updated `_prepareUpdateData` in `MFPSettlementPartial` to accumulate `amountSent` by adding prior `amountSent` from context, aligning with `CCUniPartial` v0.1.23 fix.
- **v0.1.3**: Renamed `OrderFailed` event to `OrderSkipped`. Updated `_executeOrderSwap` to revert on transfer failure, ensuring batch halts and prior `amountSent` is preserved.
- **v0.1.2**: Updated `_processOrderBatch` to handle dual return values (`context`, `isValid`) from `_validateOrder`, skipping invalid orders with `OrderSkipped`. Ensured reverts only on critical `ccUpdate` failures.
- **v0.1.2**: Updated `_validateOrder` to emit `OrderSkipped` instead of reverting, changed to `pure`. Added non-reverting logic in `_validateOrderParams`, `_checkPricing`, `_executeOrderSwap`, and `_prepareUpdateData`. Corrected `amountSent` with pre/post balance checks and status updates based on pending amount.
- **v0.1.1**: Updated `_validateOrder` and `_validateOrderParams` to process orders with `status >= 1 && < 3`. Modified `_prepareUpdateData` to accumulate `filled` and `amountSent`.
- **v0.1.0**: Initial implementation, replacing Uniswap V2 with direct transfers from `CCListingTemplate`. Added impact price and partial settlement logic.

## Mappings
- None defined directly. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`MFPSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementState** (`MFPSettlementRouter`): Contains `listingAddress` (address), `isBuyOrder` (bool), `step` (uint256), `maxIterations` (uint256).
- **OrderProcessContext** (`MFPSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `currentPrice` (uint256), `maxAmountIn` (uint256), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementContext** (`MFPSettlementPartial`): Contains `tokenA` (address), `tokenB` (address), `decimalsA` (uint8), `decimalsB` (uint8), `uniswapV2Pair` (address, unused).

## Events
- **OrderSkipped(uint256 indexed orderId, string reason)**: Emitted when an individual order fails validation, pricing checks, or transfer, ensuring non-reverting behavior for non-critical issues.

## External Functions
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder) → string memory reason**:
  - Iterates over pending orders from `step` up to `maxIterations`.
  - Initializes `SettlementContext` with `tokenA`, `tokenB`, `decimalsA`, `decimalsB` (`uniswapV2Pair` set to `address(0)`).
  - Calls `_initSettlement`, `_createHistoricalEntry`, `_processOrderBatch`.
  - Validates via `_validateOrder`, processes via `_processOrder`, applies updates via `_updateOrder`.
  - Returns empty string on success or error reason (e.g., "No orders settled: price out of range or transfer failure").
  - Reverts on critical failures: invalid listing (`onlyValidListing`), no pending orders or invalid step (`_initSettlement`), historical update failure (`_createHistoricalEntry`), transfer failure (`_executeOrderSwap`), or critical `ccUpdate` failure (`_updateOrder`).
  - **Internal Call Tree**:
    - `_initSettlement`: Fetches order IDs via `pendingBuyOrdersView` or `pendingSellOrdersView`, validates non-zero orders and step, reverts if invalid.
    - `_createHistoricalEntry`: Creates `HistoricalUpdate` using `volumeBalances`, `prices`, `historicalDataLengthView`, `getHistoricalDataView`, applies via `ccUpdate`, reverts on failure.
    - `_processOrderBatch`: Iterates orders, calls `_validateOrder`, `_processOrder`, `_updateOrder`. Skips invalid orders with `OrderSkipped`, reverts on critical `ccUpdate` failures.
    - `_validateOrder`: Fetches order data (`getBuyOrderAmounts` or `getSellOrderAmounts`, `getBuyOrderCore` or `getSellOrderCore`), checks `status >= 1 && < 3`, validates pricing via `_checkPricing`, emits `OrderSkipped` on failure.
    - `_processOrder`: Delegates to `_processBuyOrder` or `_processSellOrder`.
    - `_processBuyOrder`: Validates via `_validateOrderParams`, computes swap amount via `_computeSwapAmount`, applies updates via `_applyOrderUpdate`, emits `OrderSkipped` for invalid orders.
    - `_processSellOrder`: Similar to `_processBuyOrder` for sell orders.
    - `_applyOrderUpdate`: Executes transfer via `_executeOrderSwap`, prepares updates via `_prepareUpdateData`.
    - `_executeOrderSwap`: Performs direct transfer (`transactNative` or `transactToken`), tracks `amountSent` with pre/post balance checks, reverts on failure.
    - `_prepareUpdateData`: Updates `pending`, `filled`, `amountSent` (accumulates prior `amountSent`), sets `status` (3 if `pending <= 0`, else 2).
    - `_updateOrder`: Applies updates via `ccUpdate`, reverts on critical failure, returns success and reason.

## Internal Functions
### MFPSettlementRouter
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → (OrderContext memory, bool isValid)**: Fetches order data, validates `status >= 1 && < 3` and pending amount, checks pricing, emits `OrderSkipped` on failure, returns `false` to skip.
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context, SettlementContext memory settlementContext) → OrderContext memory**: Delegates to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)**: Applies updates via `ccUpdate`, reverts on critical failure, returns `false` for empty updates or non-critical failures.
- **_initSettlement(address listingAddress, bool isBuyOrder, uint256 step, ICCListing listingContract) → (SettlementState memory state, uint256[] memory orderIds)**: Fetches order IDs, validates step, reverts if no orders or invalid step.
- **_createHistoricalEntry(ICCListing listingContract) → ICCListing.HistoricalUpdate[] memory**: Logs historical data via `ccUpdate`, reverts on failure.
- **_processOrderBatch(SettlementState memory state, uint256[] memory orderIds, ICCListing listingContract, SettlementContext memory settlementContext) → uint256 count**: Processes orders, skips invalid ones with `OrderSkipped`, reverts on critical `ccUpdate` failures.

### MFPSettlementPartial
- **_checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) → bool**: Validates pricing, computes impact price, emits `OrderSkipped` on zero balance/price or price out of bounds, returns `false` to skip.
- **_computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) → uint256 preBalance**: Returns pre-transfer balance for `amountSent` calculation.
- **_validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → (OrderProcessContext memory, bool isValid)**: Fetches and validates order details, emits `OrderSkipped` on invalid parameters (zero pending, invalid status, or price), returns `false` to skip.
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Computes `swapAmount`, applies partial settlement if impact price exceeds bounds, reverts on zero `settlementBalance` or `swapAmount`.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, ICCListing listingContract) → OrderProcessContext memory**: Executes direct transfer, tracks `amountSent` with pre/post balance checks, reverts on transfer failure.
- **_extractPendingAmount(OrderProcessContext memory context, bool isBuyOrder) → uint256**: Extracts pending amount from updates or context.
- **_updateFilledAndStatus(OrderProcessContext memory context, bool isBuyOrder, uint256 pendingAmount) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Updates `filled`, `status` (unused in favor of `_prepareUpdateData`).
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Prepares update structs, sets `status` (3 if `pending <= 0`, else 2), accumulates `filled` and `amountSent`.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Executes transfer, prepares updates.
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory**: Validates, computes, applies buy order updates, emits `OrderSkipped` for invalid orders, returns empty updates to skip.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory**: Validates, computes, applies sell order updates, emits `OrderSkipped` for invalid orders, returns empty updates to skip.
- **uint2str(uint256 _i) → string memory**: Converts uint to string for error messages.

## Formulas
- **Impact Price Calculation**:
  - **Formula**: `impact = (pendingAmount * 1e18) / settlementBalance`
    - Buy: `impactPrice = (currentPrice * (1e18 + impact)) / 1e18`
    - Sell: `impactPrice = (currentPrice * (1e18 - impact)) / 1e18`
  - **Example**: Buy order, `pendingAmount = 10 tokenB`, `settlementBalance = 100 tokenB`, `currentPrice = 1.25 (tokenA/tokenB)`.
    - `impact = (10 * 1e18) / 100 = 0.1e18`
    - `impactPrice = (1.25 * (1e18 + 0.1e18)) / 1e18 = 1.375`
  - **Details**: Emits `OrderSkipped` if `settlementBalance = 0` or `currentPrice = 0`, or if `impactPrice > maxPrice` (buy) or `< minPrice` (sell).

- **Partial Settlement (Swap Amount)**:
  - **Formula**: If `impactPrice > maxPrice` (buy) or `< minPrice` (sell):
    - `percentageDiff = (buy ? (maxPrice * 100e18) / currentPrice - 100e18 : (currentPrice * 100e18) / minPrice - 100e18) / 1e18`
    - `swapAmount = min((settlementBalance * percentageDiff) / 100, pendingAmount)`
  - **Example**: Buy order, `pendingAmount = 10 tokenB`, `settlementBalance = 100 tokenB`, `currentPrice = 1.25`, `maxPrice = 1.3`.
    - `impactPrice = 1.375` (exceeds `maxPrice = 1.3`).
    - `percentageDiff = ((1.3 * 100e18) / 1.25 - 100e18) / 1e18 = 4`
    - `swapAmount = min((100 * 4) / 100, 10) = 4 tokenB`
    - Updates: `newPending = 10 - 4 = 6`, `filled += 4`, `amountSent += postBalance - preBalance`, `status = 2` (partial).
  - **Details**: Reverts if `swapAmount = 0`.

- **AmountSent Calculation**:
  - **Formula**: `amountSent = postBalance - preBalance` (computed in `_executeOrderSwap` via `_computeAmountSent`).
  - **Example**: Buy order, `swapAmount = 4 tokenB`, `decimalsB = 6`, `amountToSend = 4 * 10^6`. Pre-transfer balance = `1000`, post-transfer = `1004 * 10^6`, `amountSent = 1004 * 10^6 - 1000 = 4 * 10^6` (denormalized).
  - **Details**: Handles tax-on-transfer tokens by capturing actual received amount, reverts on transfer failure.

## Key Interactions
- **ICCListing**:
  - **Data Retrieval**: `getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`, `getBuyOrderPricing`, `getSellOrderPricing`, `prices`, `volumeBalances`, `historicalDataLengthView`, `getHistoricalDataView`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`.
  - **State Updates**: `ccUpdate` for `BuyOrderUpdate`, `SellOrderUpdate`, `HistoricalUpdate`.
  - **Fund Transfers**: `transactToken`, `transactNative` for direct transfers, reverts on failure.
- **ICCAgent**: Validates listings via `isValidListing` in `onlyValidListing` modifier.
- **IERC20**: Queries balances for `amountSent` calculation in `_computeAmountSent`.

## Limitations and Assumptions
- **No Uniswap V2**: Uses direct transfers, assumes sufficient `CCListingTemplate` balance.
- **No Order Creation/Cancellation**: Handled by `CCOrderRouter`.
- **No Payouts/Liquidity Settlement**: Handled by `CCLiquidityRouter`.
- **Impact Price**: Linear scaling (`impact = (pendingAmount * 1e18) / settlementBalance`).
  - **Example**: Sell order, `pendingAmount = 20 tokenA`, `settlementBalance = 200 tokenA`, `currentPrice = 1.25`.
    - `impact = (20 * 1e18) / 200 = 0.1e18`
    - `impactPrice = (1.25 * (1e18 - 0.1e18)) / 1e18 = 1.125`
- **Partial Settlement**: Limits `swapAmount` if impact price exceeds bounds.
  - **Example**: Sell order, `pendingAmount = 20 tokenA`, `settlementBalance = 200 tokenA`, `currentPrice = 1.25`, `minPrice = 1.2`.
    - `impactPrice = 1.125` (below `minPrice = 1.2`).
    - `percentageDiff = ((1.25 * 100e18) / 1.2 - 100e18) / 1e18 ≈ 4.1666`
    - `swapAmount = min((200 * 4.1666) / 100, 20) ≈ 8.3332 tokenA`
- **Decimal Handling**: Uses `normalize`/`denormalize` for 18-decimal precision.
- **Zero-Amount Handling**: Emits `OrderSkipped` for invalid orders, returns empty updates.
- **Pending/Filled/AmountSent**: Tracks `swapAmount` (tokenB for buys, tokenA for sells), accumulates `filled` and `amountSent`.
- **Historical Data**: Logs `HistoricalUpdate` at `settleOrders` start if orders exist, reverts on failure.
- **Critical Failures**: Reverts on `ccUpdate` failures in `_updateOrder`, transfer failures in `_executeOrderSwap`, or zero `swapAmount`/`settlementBalance` in `_computeSwapAmount`.

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, dynamic arrays.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing` with try-catch.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `ccUpdate`; emits `OrderSkipped` for non-critical issues (invalid order, pricing, or zero amounts).
- **Status Handling**: Validates `status >= 1 && < 3`, sets to 3 (filled) if `pending <= 0`, else 2 (partial).
- **ccUpdate Calls**: In `_updateOrder` (order updates), `_createHistoricalEntry` (historical data).
- **Price Calculation**: Uses `prices(0)` ((balanceB * 1e18) / balanceA).
- **AmountSent**: Tracks actual tokens received (tokenA for buys, tokenB for sells) via pre/post balance checks.
- **Handling Tax-on-transfer tokens**:
  - **Pending/Filled**: Set based on pre-transfer `swapAmount`, ensuring users bear tax costs.
  - **AmountSent**: Set based on pre/post balance checks, capturing actual amount received after taxes.
- **Order Skipping**: If any check fails (`_validateOrder`, `_validateOrderParams`, `_checkPricing`), the order is skipped with `OrderSkipped`, and subsequent checks are not executed for that order. The batch continues processing remaining orders until `maxIterations` is reached or a critical failure occurs.
