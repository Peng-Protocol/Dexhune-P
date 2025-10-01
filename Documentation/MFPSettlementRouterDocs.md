# MFPSettlementRouter Contract Documentation

## Overview
The `MFPSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform by directly transferring tokens from the listing template to the order recipient, based on the current price and constrained by min/max price bounds. It inherits from `MFPSettlementPartial`, which extends `CCMainPartial`, integrating with `ICCListing` and `IERC20` interfaces for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. It eliminates Uniswap V2 dependency, using impact price calculations and partial settlement logic. It ensures gas optimization with `step` and `maxIterations`, robust error handling with try-catch, non-reverting behavior for individual order issues, and decimal precision via `normalize`/`denormalize`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.5 (updated 2025-10-01)

**Inheritance Tree:** `MFPSettlementRouter` → `MFPSettlementPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `MFPSettlementPartial.sol` (v0.1.7)

### Changes
- **v0.1.5**: Commented out unused parameters (`amount` in `_computeAmountSent`, `listingAddress` in `_validateOrderParams` and `_executeOrderSwap`, `settlementContext` in `_computeSwapAmount`) to silence warnings.
- Updated `_computeSwapAmount` to cap `swapAmount` to `pendingAmount` after impact adjustment to prevent over-transfer. Added detailed error messages for edge cases (zero balance, invalid price, insufficient pending amount). Ensured no overlapping calls by streamlining `_applyOrderUpdate` flow. Removed redundant `_updateFilledAndStatus` function.
- **v0.1.4**: Modified `_validateOrder` to set `context.status = 0` when pricing fails. Updated `_processOrderBatch` to skip orders with `context.status == 0`, preventing silent failures (30/9).
- **v0.1.3**: Renamed `OrderFailed` event to `OrderSkipped`. Updated `_executeOrderSwap` to revert on transfer failure, ensuring batch halts and prior `amountSent` is preserved.
- **v0.1.2**: Updated `_processOrderBatch` to handle dual return values (`context`, `isValid`) from `_validateOrder`, skipping invalid orders with `OrderSkipped`. Ensured reverts only on critical `ccUpdate` failures.
- **v0.1.2**: Updated `_validateOrder` to emit `OrderSkipped` instead of reverting, changed to `pure`. Added non-reverting logic in `_validateOrderParams`, `_checkPricing`, `_executeOrderSwap`, and `_prepareUpdateData`. Corrected `amountSent` with pre/post balance checks and status updates based on pending amount.
- **v0.1.1**: Updated `_validateOrder` and `_validateOrderParams` to process orders with `status >= 1 && < 3`. Modified `_prepareUpdateData` to accumulate `filled` and `amountSent`.
- **v0.1.0**: Initial implementation, replacing Uniswap V2 with direct transfers from `CCListingTemplate`. Added impact price and partial settlement logic.

## Mappings
- None defined directly. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`MFPSettlementRouter`): Contains `orderId` (uint256, unique order identifier), `pending` (uint256, normalized pending amount), `status` (uint8, order state: 0=cancelled, 1=pending, 2=partially filled, 3=filled), `buyUpdates` (ICCListing.BuyOrderUpdate[], buy order updates), `sellUpdates` (ICCListing.SellOrderUpdate[], sell order updates).
- **SettlementState** (`MFPSettlementRouter`): Contains `listingAddress` (address, listing contract address), `isBuyOrder` (bool, true for buy orders, false for sell), `step` (uint256, starting index for batch processing), `maxIterations` (uint256, maximum orders to process).
- **OrderProcessContext** (`MFPSettlementPartial`): Contains `orderId` (uint256, order identifier), `pendingAmount` (uint256, normalized pending amount), `filled` (uint256, normalized filled amount), `amountSent` (uint256, normalized transferred amount), `makerAddress` (address, order creator), `recipientAddress` (address, token recipient), `status` (uint8, order state), `maxPrice` (uint256, maximum acceptable price for buys), `minPrice` (uint256, minimum acceptable price for sells), `currentPrice` (uint256, listing’s current price), `maxAmountIn` (uint256, maximum input amount), `swapAmount` (uint256, amount to transfer), `buyUpdates` (ICCListing.BuyOrderUpdate[], buy order updates), `sellUpdates` (ICCListing.SellOrderUpdate[], sell order updates).
- **SettlementContext** (`MFPSettlementPartial`): Contains `tokenA` (address, first token in pair), `tokenB` (address, second token in pair), `decimalsA` (uint8, decimals of tokenA), `decimalsB` (uint8, decimals of tokenB), `uniswapV2Pair` (address, unused, kept for compatibility).

## Events
- **OrderSkipped(uint256 indexed orderId, string reason)**: Emitted when an individual order fails validation, pricing checks, or transfer, ensuring non-reverting behavior for non-critical issues. `orderId` identifies the order, `reason` provides detailed failure explanation (e.g., "Invalid status", "Zero swap amount").

## External Functions
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder) → string memory reason**:
  - **Parameters**:
    - `listingAddress`: Address of the listing contract (`ICCListing`).
    - `step`: Starting index for batch processing to control gas usage.
    - `maxIterations`: Maximum number of orders to process in the batch.
    - `isBuyOrder`: True for buy orders, false for sell orders.
  - **Description**: Iterates over pending orders from `step` up to `maxIterations`. Initializes `SettlementContext` with `tokenA`, `tokenB`, `decimalsA`, `decimalsB` (`uniswapV2Pair` set to `address(0)`). Calls `_initSettlement`, `_createHistoricalEntry`, `_processOrderBatch`. Validates via `_validateOrder`, processes via `_processOrder`, applies updates via `_updateOrder`. Returns empty string on success or error reason (e.g., "No orders settled: price out of range or transfer failure").
  - **Reverts**: On invalid listing (`onlyValidListing`), no pending orders or invalid step (`_initSettlement`), historical update failure (`_createHistoricalEntry`), transfer failure (`_executeOrderSwap`), or critical `ccUpdate` failure (`_updateOrder`).
  - **Internal Call Tree**:
    - `_initSettlement`: Fetches order IDs via `pendingBuyOrdersView` or `pendingSellOrdersView`, validates non-zero orders and step, reverts if invalid.
    - `_createHistoricalEntry`: Creates `HistoricalUpdate` using `volumeBalances`, `prices`, `historicalDataLengthView`, `getHistoricalDataView`, applies via `ccUpdate`, reverts on failure.
    - `_processOrderBatch`: Iterates orders, calls `_validateOrder`, `_processOrder`, `_updateOrder`. Skips invalid orders or `status == 0` with `OrderSkipped`, reverts on critical `ccUpdate` failures.
    - `_validateOrder`: Fetches order data (`getBuyOrderAmounts` or `getSellOrderAmounts`, `getBuyOrderCore` or `getSellOrderCore`), checks `status >= 1 && < 3`, validates pricing via `_checkPricing`, sets `status = 0` on pricing failure, emits `OrderSkipped` on failure.
    - `_processOrder`: Delegates to `_processBuyOrder` or `_processSellOrder`.
    - `_processBuyOrder`: Validates via `_validateOrderParams`, computes swap amount via `_computeSwapAmount`, applies updates via `_applyOrderUpdate`, emits `OrderSkipped` for invalid orders.
    - `_processSellOrder`: Similar to `_processBuyOrder` for sell orders.
    - `_applyOrderUpdate`: Executes transfer via `_executeOrderSwap`, prepares updates via `_prepareUpdateData`.
    - `_executeOrderSwap`: Performs direct transfer (`transactNative` or `transactToken`), tracks `amountSent` with pre/post balance checks, reverts on failure.
    - `_prepareUpdateData`: Updates `pending`, `filled`, `amountSent` (accumulates prior `amountSent`), sets `status` (3 if `pending <= 0`, else 2).
    - `_updateOrder`: Applies updates via `ccUpdate`, reverts on critical failure, returns success and reason.

## Internal Functions
### MFPSettlementRouter
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → (OrderContext memory, bool isValid)**:
  - **Parameters**: `listingAddress` (listing contract), `orderId` (order identifier), `isBuyOrder` (buy/sell flag), `listingContract` (ICCListing interface).
  - **Description**: Fetches order data, validates `status >= 1 && < 3` and pending amount, checks pricing, sets `status = 0` on pricing failure, emits `OrderSkipped` on failure, returns `false` to skip.
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context, SettlementContext memory settlementContext) → OrderContext memory**:
  - **Parameters**: `listingAddress`, `isBuyOrder`, `listingContract`, `context` (order data), `settlementContext` (token and decimal data).
  - **Description**: Delegates to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)**:
  - **Parameters**: `listingContract`, `context`, `isBuyOrder`.
  - **Description**: Applies updates via `ccUpdate`, reverts on critical failure, returns `false` for empty updates or non-critical failures.
- **_initSettlement(address listingAddress, bool isBuyOrder, uint256 step, ICCListing listingContract) → (SettlementState memory state, uint256[] memory orderIds)**:
  - **Parameters**: `listingAddress`, `isBuyOrder`, `step`, `listingContract`.
  - **Description**: Fetches order IDs, validates step, reverts if no orders or invalid step.
- **_createHistoricalEntry(ICCListing listingContract) → ICCListing.HistoricalUpdate[] memory**:
  - **Parameters**: `listingContract`.
  - **Description**: Logs historical data via `ccUpdate`, reverts on failure.
- **_processOrderBatch(SettlementState memory state, uint256[] memory orderIds, ICCListing listingContract, SettlementContext memory settlementContext) → uint256 count**:
  - **Parameters**: `state` (settlement state), `orderIds` (pending order IDs), `listingContract`, `settlementContext`.
  - **Description**: Processes orders, skips invalid ones or `status == 0` with `OrderSkipped`, reverts on critical `ccUpdate` failures.

### MFPSettlementPartial
- **_checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) → bool**:
  - **Parameters**: `listingAddress`, `orderIdentifier` (order ID), `isBuyOrder`, `pendingAmount` (normalized pending amount).
  - **Description**: Validates pricing, computes impact price, emits `OrderSkipped` on zero balance/price or price out of bounds, returns `false` to skip.
- **_computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) → uint256 preBalance**:
  - **Parameters**: `tokenAddress` (token to transfer), `recipientAddress` (recipient), `amount` (unused, commented out).
  - **Description**: Returns pre-transfer balance for `amountSent` calculation.
- **_validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → (OrderProcessContext memory, bool isValid)**:
  - **Parameters**: `listingAddress` (unused, commented out), `orderId`, `isBuyOrder`, `listingContract`.
  - **Description**: Fetches and validates order details, emits `OrderSkipped` on invalid parameters (zero pending, invalid status, or price), returns `false` to skip.
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**:
  - **Parameters**: `listingAddress`, `isBuyOrder`, `context` (order data), `settlementContext` (unused, commented out).
  - **Description**: Computes `swapAmount`, applies partial settlement if impact price exceeds bounds, emits `OrderSkipped` on zero `settlementBalance` or `swapAmount`, caps `swapAmount` to `pendingAmount`.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, ICCListing listingContract) → OrderProcessContext memory**:
  - **Parameters**: `listingAddress` (unused, commented out), `isBuyOrder`, `context`, `listingContract`.
  - **Description**: Executes direct transfer, tracks `amountSent` with pre/post balance checks, reverts on transfer failure, emits `OrderSkipped` on zero transfer amount.
- **_extractPendingAmount(OrderProcessContext memory context, bool isBuyOrder) → uint256**:
  - **Parameters**: `context`, `isBuyOrder`.
  - **Description**: Extracts pending amount from updates or context.
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**:
  - **Parameters**: `context`, `isBuyOrder`.
  - **Description**: Prepares update structs, sets `status` (3 if `pending <= 0`, else 2), accumulates `filled` and `amountSent`.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**:
  - **Parameters**: `listingAddress`, `listingContract`, `context`, `isBuyOrder`.
  - **Description**: Executes transfer, prepares updates, emits `OrderSkipped` if no swap executed.
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory**:
  - **Parameters**: `listingAddress`, `orderIdentifier`, `listingContract`, `settlementContext`.
  - **Description**: Validates, computes, applies buy order updates, emits `OrderSkipped` for invalid orders or zero swap amount, returns empty updates to skip.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory**:
  - **Parameters**: `listingAddress`, `orderIdentifier`, `listingContract`, `settlementContext`.
  - **Description**: Validates, computes, applies sell order updates, emits `OrderSkipped` for invalid orders or zero swap amount, returns empty updates to skip.
- **uint2str(uint256 _i) → string memory**:
  - **Parameters**: `_i` (uint to convert).
  - **Description**: Converts uint to string for error messages.

## Formulas
- **Impact Price Calculation**:
  - **Formula**: `impact = (pendingAmount * 1e18) / settlementBalance`
    - Buy: `impactPrice = (currentPrice * (1e18 + impact)) / 1e18`
    - Sell: `impactPrice = (currentPrice * (1e18 - impact)) / 1e18`
  - **Example**: Buy order, `pendingAmount = 10 tokenB`, `settlementBalance = 100 tokenB`, `currentPrice = 1.25 (tokenA/tokenB)`.
    - `impact = (10 * 1e18) / 100 = 0.1e18`
    - `impactPrice = (1.25 * (1e18 + 0.1e18)) / 1e18 = 1.375`
  - **Details**: Emits `OrderSkipped` if `settlementBalance = 0`, `currentPrice = 0`, or if `impactPrice > maxPrice` (buy) or `< minPrice` (sell).

- **Partial Settlement (Swap Amount)**:
  - **Formula**: If `impactPrice > maxPrice` (buy) or `< minPrice` (sell):
    - `percentageDiff = (buy ? (maxPrice * 100e18) / currentPrice - 100e18 : (currentPrice * 100e18) / minPrice - 100e18) / 1e18`
    - `swapAmount = min((settlementBalance * percentageDiff) / 100, pendingAmount)`
  - **Example**: Buy order, `pendingAmount = 10 tokenB`, `settlementBalance = 100 tokenB`, `currentPrice = 1.25`, `maxPrice = 1.3`.
    - `impactPrice = 1.375` (exceeds `maxPrice = 1.3`).
    - `percentageDiff = ((1.3 * 100e18) / 1.25 - 100e18) / 1e18 = 4`
    - `swapAmount = min((100 * 4) / 100, 10) = 4 tokenB`
    - Updates: `newPending = 10 - 4 = 6`, `filled += 4`, `amountSent += postBalance - preBalance`, `status = 2` (partial).
  - **Details**: Emits `OrderSkipped` if `swapAmount = 0`. Caps `swapAmount` to `pendingAmount` to prevent over-transfer.

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
- **Critical Failures**: Reverts on `ccUpdate` failures in `_updateOrder`, transfer failures in `_executeOrderSwap`, or zero `settlementBalance` in `_computeSwapAmount`.

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, dynamic arrays.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing` with try-catch.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `ccUpdate`; emits `OrderSkipped` for non-critical issues (invalid order, pricing, zero amounts).
- **Status Handling**: Validates `status >= 1 && < 3`, sets to 3 (filled) if `pending <= 0`, else 2 (partial).
- **ccUpdate Calls**: In `_updateOrder` (order updates), `_createHistoricalEntry` (historical data).
- **Price Calculation**: Uses `prices(0)` ((balanceB * 1e18) / balanceA).
- **AmountSent**: Tracks actual tokens received (tokenA for buys, tokenB for sells) via pre/post balance checks.
- **Handling Tax-on-transfer tokens**:
  - **Pending/Filled**: Set based on pre-transfer `swapAmount`, ensuring users bear tax costs.
  - **AmountSent**: Set based on pre/post balance checks, capturing actual amount received after taxes.
- **Order Skipping**: If any check fails (`_validateOrder`, `_validateOrderParams`, `_checkPricing`, `_executeOrderSwap`, `_computeSwapAmount`), the order is skipped with `OrderSkipped`, and subsequent checks are not executed for that order. The batch continues processing remaining orders until `maxIterations` is reached or a critical failure occurs.
