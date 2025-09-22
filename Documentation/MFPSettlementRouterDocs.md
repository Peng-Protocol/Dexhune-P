# MFPSettlementRouter Contract Documentation

## Overview
The `MFPSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform by directly transferring tokens from the listing template to the order recipient, based on the current price and constrained by min/max price bounds. It inherits from `MFPSettlementPartial`, which extends `CCMainPartial`, integrating with `ICCListing` and `IERC20` interfaces for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. Unlike `CCSettlementRouter`, it eliminates Uniswap V2 dependency, using impact price calculations and partial settlement logic. It ensures gas optimization with `step` and `maxIterations`, robust error handling with try-catch, and decimal precision via `normalize`/`denormalize`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.2 (updated 2025-09-22)

**Inheritance Tree:** `MFPSettlementRouter` → `MFPSettlementPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `MFPSettlementPartial.sol` (v0.1.1)

### Changes
- **v0.1.2**: Added Formulas section and detailed impact price/partial amount calculations with examples in documentation.
- **v0.1.1**: Updated `_validateOrder` and `_validateOrderParams` to process orders with `status >= 1 && < 3`. Modified `_prepareUpdateData` to accumulate `filled` and `amountSent`.
- **v0.1.0**: Initial implementation, replacing Uniswap V2 with direct transfers from `CCListingTemplate`. Added impact price and partial settlement logic.

## Mappings
- None defined directly. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`MFPSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementState** (`MFPSettlementRouter`): Contains `listingAddress` (address), `isBuyOrder` (bool), `step` (uint256), `maxIterations` (uint256).
- **OrderProcessContext** (`MFPSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `currentPrice` (uint256), `maxAmountIn` (uint256), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementContext** (`MFPSettlementPartial`): Contains `tokenA` (address), `tokenB` (address), `decimalsA` (uint8), `decimalsB` (uint8), `uniswapV2Pair` (address, unused).

## External Functions
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder) → string memory reason**:
  - Iterates over pending orders from `step` up to `maxIterations`.
  - Initializes `SettlementContext` with `tokenA`, `tokenB`, `decimalsA`, `decimalsB` (`uniswapV2Pair` set to `address(0)`).
  - Calls `_initSettlement`, `_createHistoricalEntry`, `_processOrderBatch`.
  - Validates via `_validateOrder`, processes via `_processOrder`, applies updates via `_updateOrder`.
  - Returns empty string or error reason (e.g., "No orders settled: price out of range or transfer failure").
  - **Internal Call Tree**:
    - `_initSettlement` → Fetches order IDs, validates non-zero orders and step.
    - `_createHistoricalEntry` → Creates `HistoricalUpdate` using `volumeBalances`, `prices`, `historicalDataLengthView`, `getHistoricalDataView`.
    - `_processOrderBatch` → Iterates orders, calls `_validateOrder`, `_processOrder`, `_updateOrder`.
    - `_validateOrder` → Fetches order data, checks `status >= 1 && < 3`, pricing via `_checkPricing`.
    - `_processOrder` → Calls `_processBuyOrder` or `_processSellOrder`.
    - `_processBuyOrder` → Validates via `_validateOrderParams`, computes swap amount via `_computeSwapAmount`, applies updates via `_applyOrderUpdate`.
    - `_processSellOrder` → Validates via `_validateOrderParams`, computes swap amount via `_computeSwapAmount`, applies updates via `_applyOrderUpdate`.
    - `_applyOrderUpdate` → Executes transfer via `_executeOrderSwap`, prepares updates via `_prepareUpdateData`.
    - `_executeOrderSwap` → Performs direct transfer (`transactNative` or `transactToken`), tracks `amountSent`.
    - `_prepareUpdateData` → Updates `filled` and `status`, accumulates `filled` and `amountSent`.
    - `_updateOrder` → Applies updates via `ccUpdate`.

## Internal Functions
### MFPSettlementRouter
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderContext memory**: Fetches order data, validates `status >= 1 && < 3` and pending amount, checks pricing.
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context, SettlementContext memory settlementContext) → OrderContext memory**: Delegates to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)**: Applies updates via `ccUpdate`.
- **_initSettlement(address listingAddress, bool isBuyOrder, uint256 step, ICCListing listingContract) → (SettlementState memory state, uint256[] memory orderIds)**: Fetches order IDs, validates step.
- **_createHistoricalEntry(ICCListing listingContract) → ICCListing.HistoricalUpdate[] memory**: Logs historical data.
- **_processOrderBatch(SettlementState memory state, uint256[] memory orderIds, ICCListing listingContract, SettlementContext memory settlementContext) → uint256 count**: Processes orders, returns count.

### MFPSettlementPartial
- **_checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) → bool**: Validates pricing, computes impact price, reverts on zero balance or price.
- **_computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) → uint256 preBalance**: Returns pre-transfer balance.
- **_validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderProcessContext memory**: Fetches and validates order details.
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Computes `swapAmount`, applies partial settlement if impact price exceeds bounds.
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, ICCListing listingContract) → OrderProcessContext memory**: Executes direct transfer, tracks `amountSent`.
- **_extractPendingAmount(OrderProcessContext memory context, bool isBuyOrder) → uint256**: Extracts pending amount.
- **_updateFilledAndStatus(OrderProcessContext memory context, bool isBuyOrder, uint256 pendingAmount) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Updates `filled`, `status`.
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Prepares update structs, accumulates `amountSent`.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory, ICCListing.SellOrderUpdate[] memory)**: Executes transfer, prepares updates.
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory**: Validates, computes, applies buy order updates.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory**: Validates, computes, applies sell order updates.
- **uint2str(uint256 _i) → string memory**: Converts uint to string.

## Formulas
- **Impact Price Calculation**:
  - **Formula**: `impact = (pendingAmount * 1e18) / settlementBalance`
    - Buy: `impactPrice = (currentPrice * (1e18 + impact)) / 1e18`
    - Sell: `impactPrice = (currentPrice * (1e18 - impact)) / 1e18`
  - **Example**: Buy order, `pendingAmount = 10 tokenB`, `settlementBalance = 100 tokenB`, `currentPrice = 1.25 (tokenA/tokenB)`.
    - `impact = (10 * 1e18) / 100 = 0.1e18`
    - `impactPrice = (1.25 * (1e18 + 0.1e18)) / 1e18 = 1.25 * 1.1 = 1.375`
  - **Details**: Validates against `maxPrice` (buy) or `minPrice` (sell). Reverts if `settlementBalance = 0` or `currentPrice = 0`.

- **Partial Settlement (Swap Amount)**:
  - **Formula**: If `impactPrice > maxPrice` (buy) or `< minPrice` (sell):
    - `percentageDiff = (buy ? (maxPrice * 100e18) / currentPrice - 100e18 : (currentPrice * 100e18) / minPrice - 100e18) / 1e18`
    - `swapAmount = min((settlementBalance * percentageDiff) / 100, pendingAmount)`
  - **Example**: Buy order, `pendingAmount = 10 tokenB`, `settlementBalance = 100 tokenB`, `currentPrice = 1.25`, `maxPrice = 1.3`.
    - `impactPrice = 1.375` (from above, exceeds `maxPrice = 1.3`).
    - `percentageDiff = ((1.3 * 100e18) / 1.25 - 100e18) / 1e18 = (104e18 - 100e18) / 1e18 = 4`
    - `swapAmount = min((100 * 4) / 100, 10) = min(4, 10) = 4 tokenB`
    - Updates: `newPending = 10 - 4 = 6`, `filled += 4`, `status = 2` (partial).
  - **Details**: Ensures `swapAmount <= pendingAmount`, reverts if `swapAmount = 0`.

## Key Interactions
- **ICCListing**:
  - **Data Retrieval**: `getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`, `getBuyOrderPricing`, `getSellOrderPricing`, `prices`, `volumeBalances`, `historicalDataLengthView`, `getHistoricalDataView`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`.
  - **State Updates**: `ccUpdate` for `BuyOrderUpdate`, `SellOrderUpdate`, `HistoricalUpdate`.
  - **Fund Transfers**: `transactToken`, `transactNative` to transfer tokens.
- **ICCAgent**: Validates listings via `isValidListing`.

## Limitations and Assumptions
- **No Uniswap V2**: Uses direct transfers, assumes sufficient `CCListingTemplate` balance.
- **No Order Creation/Cancellation**: Handled elsewhere (e.g., `CCOrderRouter`).
- **No Payouts/Liquidity Settlement**: Handled by `CCLiquidityRouter`.
- **Impact Price**: Linear scaling (`impact = (pendingAmount * 1e18) / settlementBalance`).
  - **Example**: Sell order, `pendingAmount = 20 tokenA`, `settlementBalance = 200 tokenA`, `currentPrice = 1.25`.
    - `impact = (20 * 1e18) / 200 = 0.1e18`
    - `impactPrice = (1.25 * (1e18 - 0.1e18)) / 1e18 = 1.25 * 0.9 = 1.125`
- **Partial Settlement**: Limits `swapAmount` if impact price exceeds bounds.
  - **Example**: Sell order, `pendingAmount = 20 tokenA`, `settlementBalance = 200 tokenA`, `currentPrice = 1.25`, `minPrice = 1.2`.
    - `impactPrice = 1.125` (below `minPrice = 1.2`).
    - `percentageDiff = ((1.25 * 100e18) / 1.2 - 100e18) / 1e18 ≈ 4.1666`
    - `swapAmount = min((200 * 4.1666) / 100, 20) ≈ min(8.3332, 20) = 8.3332 tokenA`
- **Decimal Handling**: Uses `normalize`/`denormalize` for 18-decimal precision.
- **Zero-Amount Handling**: Reverts on zero `swapAmount` or balance, returns empty updates for failed transfers.
- **Pending/Filled/AmountSent**: Tracks `swapAmount` (tokenB for buys, tokenA for sells), accumulates `filled` and `amountSent`.
- **Historical Data**: Logs `HistoricalUpdate` at `settleOrders` start if orders exist.

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, dynamic arrays.
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, `ccUpdate`.
- **Status Handling**: Validates `status >= 1 && < 3`, sets to 3 (filled) or 2 (partial).
- **ccUpdate Calls**: In `_updateOrder` (order updates), `_createHistoricalEntry` (historical data).
- **Price Calculation**: Uses `prices(0)` ((balanceB * 1e18) / balanceA).
- **AmountSent**: Tracks tokens received (tokenA for buys, tokenB for sells), incremented per partial fill.

