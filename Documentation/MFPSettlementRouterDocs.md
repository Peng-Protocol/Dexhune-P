# MFPSettlementRouter Contract Documentation

## Overview
The `MFPSettlementRouter` contract, implemented in Solidity (`^0.8.2`), facilitates the settlement of buy and sell orders on a decentralized trading platform by directly transferring tokens from the listing template to the order recipient, based on the current price and constrained by min/max price bounds. It inherits from `MFPSettlementPartial`, which extends `CCMainPartial`, integrating with `ICCListing` and `IERC20` interfaces for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. Unlike `CCSettlementRouter`, it eliminates Uniswap V2 dependency, using impact price calculations (e.g., for a buy order with 10 tokenB pending and 100 tokenB balance, impact is 10%, increasing price from 1.25 to 1.375) and partial settlement logic (e.g., max 4 tokenB settled if impact price exceeds max price). It ensures gas optimization with `step` and `maxIterations`, robust error handling with try-catch, and decimal precision via `normalize`/`denormalize`.

**SPDX License:** BSL 1.1 - Peng Protocol 2025

**Version:** 0.1.1 (updated 2025-09-21)

**Inheritance Tree:** `MFPSettlementRouter` → `MFPSettlementPartial` → `CCMainPartial`

**Compatible Contracts:**
- `CCListingTemplate.sol` (v0.3.9)
- `CCMainPartial.sol` (v0.1.5)
- `MFPSettlementPartial.sol` (v0.1.1)

### Changes
- **v0.1.0**: Initial implementation, replacing Uniswap V2 with direct transfers from `CCListingTemplate`. Added impact price calculation (`impact = (pendingAmount * 1e18) / settlementBalance`, buy: `price * (1e18 + impact) / 1e18`, sell: `price * (1e18 - impact) / 1e18`) and partial settlement logic (`maxAmount = (settlementBalance * percentageDiff) / 100`, where `percentageDiff = (maxPrice / currentPrice * 100 - 100)` for buys). Compatible with `CCListingTemplate.sol` (v0.3.9), `CCMainPartial.sol` (v0.1.5).

## Mappings
- None defined directly in `MFPSettlementRouter` or `MFPSettlementPartial`. Relies on `ICCListing` view functions (`pendingBuyOrdersView`, `pendingSellOrdersView`) for order tracking.

## Structs
- **OrderContext** (`MFPSettlementRouter`): Contains `orderId` (uint256), `pending` (uint256), `status` (uint8), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementState** (`MFPSettlementRouter`): Contains `listingAddress` (address), `isBuyOrder` (bool), `step` (uint256), `maxIterations` (uint256).
- **OrderProcessContext** (`MFPSettlementPartial`): Contains `orderId` (uint256), `pendingAmount` (uint256), `filled` (uint256), `amountSent` (uint256), `makerAddress` (address), `recipientAddress` (address), `status` (uint8), `maxPrice` (uint256), `minPrice` (uint256), `currentPrice` (uint256), `maxAmountIn` (uint256), `swapAmount` (uint256), `buyUpdates` (ICCListing.BuyOrderUpdate[]), `sellUpdates` (ICCListing.SellOrderUpdate[]).
- **SettlementContext** (`MFPSettlementPartial`): Contains `tokenA` (address), `tokenB` (address), `decimalsA` (uint8), `decimalsB` (uint8), `uniswapV2Pair` (address, unused but retained for compatibility).

## External Functions
- **settleOrders(address listingAddress, uint256 step, uint256 maxIterations, bool isBuyOrder) → string memory reason** (`MFPSettlementRouter`):
  - Iterates over pending orders from `step` up to `maxIterations` using `pendingBuyOrdersView` or `pendingSellOrdersView`.
  - Initializes `SettlementContext` with `tokenA`, `tokenB`, `decimalsA`, `decimalsB` (sets `uniswapV2Pair` to `address(0)`).
  - Calls `_initSettlement` to fetch order IDs, `_createHistoricalEntry` to log historical data, and `_processOrderBatch` to process orders.
  - Validates orders via `_validateOrder`, processes via `_processOrder`, and applies updates via `_updateOrder`.
  - Returns empty string on success or error reason (e.g., "No orders settled: price out of range or transfer failure").
  - **Internal Call Tree**:
    - `_initSettlement` → Fetches order IDs, validates non-zero orders and step.
    - `_createHistoricalEntry` → Creates `HistoricalUpdate` using `volumeBalances`, `prices`, `historicalDataLengthView`, `getHistoricalDataView`.
    - `_processOrderBatch` → Iterates orders, calls `_validateOrder`, `_processOrder`, `_updateOrder`.
    - `_validateOrder` → Fetches order data (`getBuyOrderAmounts`/`getSellOrderAmounts`, `getBuyOrderCore`/`getSellOrderCore`), checks pricing via `_checkPricing`.
    - `_processOrder` → Calls `_processBuyOrder` or `_processSellOrder`.
    - `_processBuyOrder` → Validates via `_validateOrderParams`, computes swap amount via `_computeSwapAmount`, applies updates via `_applyOrderUpdate`.
    - `_processSellOrder` → Validates via `_validateOrderParams`, computes swap amount via `_computeSwapAmount`, applies updates via `_applyOrderUpdate`.
    - `_applyOrderUpdate` → Executes transfer via `_executeOrderSwap`, prepares updates via `_prepareUpdateData`.
    - `_executeOrderSwap` → Performs direct transfer (`transactNative` or `transactToken`) to recipient, tracks `amountSent` with pre/post balance checks.
    - `_prepareUpdateData` → Updates `filled` and `status` via `_updateFilledAndStatus`.
    - `_updateOrder` → Applies updates via `ccUpdate`.

## Internal Functions
### MFPSettlementRouter
- **_validateOrder(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderContext memory context**: Fetches order data, validates status and pending amount, checks pricing via `_checkPricing`.
- **_processOrder(address listingAddress, bool isBuyOrder, ICCListing listingContract, OrderContext memory context, SettlementContext memory settlementContext) → OrderContext memory**: Delegates to `_processBuyOrder` or `_processSellOrder`.
- **_updateOrder(ICCListing listingContract, OrderContext memory context, bool isBuyOrder) → (bool success, string memory reason)**: Applies `ccUpdate` with `buyUpdates` or `sellUpdates`, returns success or error reason.
- **_initSettlement(address listingAddress, bool isBuyOrder, uint256 step, ICCListing listingContract) → (SettlementState memory state, uint256[] memory orderIds)**: Initializes state, fetches order IDs.
- **_createHistoricalEntry(ICCListing listingContract) → ICCListing.HistoricalUpdate[] memory historicalUpdates**: Logs historical data (`price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`) via `ccUpdate`.
- **_processOrderBatch(SettlementState memory state, uint256[] memory orderIds, ICCListing listingContract, SettlementContext memory settlementContext) → uint256 count**: Processes orders, returns count of successful settlements.

### MFPSettlementPartial
- **_checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) → bool**: Validates order pricing, computes impact price (`impact = (pendingAmount * 1e18) / settlementBalance`, buy: increase price, sell: decrease price), reverts on zero balance or price.
- **_computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) → uint256 preBalance**: Returns pre-transfer balance for tracking `amountSent`.
- **_validateOrderParams(address listingAddress, uint256 orderId, bool isBuyOrder, ICCListing listingContract) → OrderProcessContext memory context**: Fetches and validates order details (core, pricing, amounts).
- **_computeSwapAmount(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, SettlementContext memory settlementContext) → OrderProcessContext memory**: Computes `swapAmount`, applies partial settlement if impact price exceeds bounds (e.g., `(settlementBalance * ((maxPrice / currentPrice * 100 - 100))) / 100` for buys).
- **_executeOrderSwap(address listingAddress, bool isBuyOrder, OrderProcessContext memory context, ICCListing listingContract) → OrderProcessContext memory**: Executes direct transfer (`transactNative` or `transactToken`), tracks `amountSent` with pre/post balance checks.
- **_extractPendingAmount(OrderProcessContext memory context, bool isBuyOrder) → uint256 pending**: Extracts pending amount from updates or context.
- **_updateFilledAndStatus(OrderProcessContext memory context, bool isBuyOrder, uint256 pendingAmount) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Updates `filled` and `status` (3 if fully settled, 2 if partial).
- **_prepareUpdateData(OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Prepares update structs for `ccUpdate`.
- **_applyOrderUpdate(address listingAddress, ICCListing listingContract, OrderProcessContext memory context, bool isBuyOrder) → (ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates)**: Executes transfer, prepares updates.
- **_processBuyOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.BuyOrderUpdate[] memory buyUpdates**: Validates, computes swap amount, applies updates for buy orders.
- **_processSellOrder(address listingAddress, uint256 orderIdentifier, ICCListing listingContract, SettlementContext memory settlementContext) → ICCListing.SellOrderUpdate[] memory sellUpdates**: Validates, computes swap amount, applies updates for sell orders.
- **uint2str(uint256 _i) → string memory str**: Converts uint to string for error messages.

## Key Interactions
- **ICCListing**:
  - **Data Retrieval**: `getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`, `getBuyOrderPricing`, `getSellOrderPricing`, `prices`, `volumeBalances`, `historicalDataLengthView`, `getHistoricalDataView`, `pendingBuyOrdersView`, `pendingSellOrdersView`, `tokenA`, `tokenB`, `decimalsA`, `decimalsB`.
  - **State Updates**: `ccUpdate` for `BuyOrderUpdate`, `SellOrderUpdate`, `HistoricalUpdate`.
  - **Fund Transfers**: `transactToken`, `transactNative` to transfer tokens to recipient.
- **ICCAgent**: Validates listings via `isValidListing` in `onlyValidListing` modifier.

## Limitations and Assumptions
- **No Uniswap V2**: Relies on direct transfers from listing template, assuming sufficient balance in `CCListingTemplate`.
- **No Order Creation/Cancellation**: Handled by other contracts (e.g., `CCOrderRouter`).
- **No Payouts or Liquidity Settlement**: Handled by `CCLiquidityRouter` or similar.
- **Impact Price**: Assumes linear price scaling (`impact = (pendingAmount * 1e18) / settlementBalance`, buy: increase, sell: decrease).
- **Partial Settlement**: Limits `swapAmount` if impact price exceeds `maxPrice` (buy) or falls below `minPrice` (sell), using `(settlementBalance * percentageDiff) / 100`.
- **Decimal Handling**: Uses `normalize`/`denormalize` for 18-decimal precision, assumes `IERC20.decimals` or 18 for ETH.
- **Zero-Amount Handling**: Reverts on zero `swapAmount` or settlement balance, returns empty updates for failed transfers.
- **Pending/Filled**: Uses `swapAmount` (tokenB for buys, tokenA for sells) for `pending` and `filled`, accumulating `filled`.
- **AmountSent**: Tracks actual tokens received by recipient (tokenA for buys, tokenB for sells) with pre/post balance checks.
- **Historical Data**: Creates `HistoricalUpdate` at the start of `settleOrders` if pending orders exist, logging `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`.

## Additional Details
- **Reentrancy Protection**: `nonReentrant` on `settleOrders`.
- **Gas Optimization**: Uses `step`, `maxIterations`, and dynamic arrays. Refactored with `SettlementState` (v0.1.0).
- **Listing Validation**: `onlyValidListing` checks `ICCAgent.isValidListing`.
- **Error Handling**: Try-catch in `transactNative`, `transactToken`, and `ccUpdate` with decoded reasons.
- **Status Handling**: Sets status to 3 (fully settled) if `swapAmount >= pendingAmount`, otherwise 2 (partially settled).
- **ccUpdate Call Locations**:
  - `_updateOrder` applies `buyUpdates` or `sellUpdates` for orders.
  - `_createHistoricalEntry` applies `historicalUpdates` at the start of `settleOrders`.
- **Price Calculation**: Uses `listingContract.prices(0)` ((balanceB * 1e18) / balanceA).
- **Partial Fills**: Occur when impact price exceeds bounds, limiting `swapAmount` to respect `maxPrice` (buy) or `minPrice` (sell).
- **AmountSent**: Tracks tokens received (e.g., tokenA for buys) via pre/post balance checks, incremented per partial fill.
