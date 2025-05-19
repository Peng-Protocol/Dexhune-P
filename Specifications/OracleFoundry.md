# OMF Contracts System Specification

This document specifies the functionalities of `OMFAgent.sol`, `OMFLiquidityTemplate.sol`, and `OMFListingTemplate.sol`, core components of a decentralized exchange (DEX) system for token listing, liquidity management, and order book operations. Designed for Solidity 0.8.2, the contracts emphasize security, gas efficiency, and decimal normalization (18 decimals). The specification details data structures, operations, and design considerations, focusing on technical accuracy and system behavior.

## OMFAgent.sol

`OMFAgent.sol` is an ownable contract managing token listings, liquidity aggregation, order tracking, and historical trend queries. It interacts with listing and liquidity contracts via a router, maintaining global state for pairs, users, and orders.

### 1. Configuration
- **Router Address**: Sets a non-zero router address (`routerAddress`) for mediating interactions.
- **Logic Contracts**: Configures non-zero addresses (`listingLogicAddress`, `liquidityLogicAddress`) for deploying listing and liquidity proxies.
- **Base Token**: Defines a non-zero reference token (`baseToken`, Token-1) for pairing with listed tokens (Token-0).

### 2. Token Listing
- **Pair Creation**: Deploys listing and liquidity contracts for Token-0/base token pairs via `listToken`:
  - **Validation**: Ensures Token-0 is non-zero, distinct from base token, unlisted, and caller holds ≥1% of Token-0 supply (normalized to 18 decimals).
  - **Deployment**: Generates deterministic salts (`keccak256(token0, baseToken, listingCount)`) for proxy deployment via logic contracts. Initializes proxies with router, tokens, listing ID, agent, and oracle data (address, decimals, view function selector).
  - **Storage**: Maps pair to listing address (`getListing[token0][baseToken]`), tracks listings (`allListings`) and tokens (`allListedTokens`). Calls `setAgent` on listing contract during initialization.
- **Listing Counter**: Increments `listingCount` per deployment, used in salts and IDs.

### 3. Liquidity Aggregation
- **Mappings**:
  - `globalLiquidity[token0][baseToken][user]`: User liquidity per pair.
  - `totalLiquidityPerPair[token0][baseToken]`: Total pair liquidity.
  - `userTotalLiquidity[user]`: User’s total liquidity.
  - `listingLiquidity[listingId][user]`: Liquidity per listing.
  - `historicalLiquidityPerPair[token0][baseToken][timestamp]`: Pair liquidity at timestamp.
  - `historicalLiquidityPerUser[token0][baseToken][user][timestamp]`: User liquidity at timestamp.
- **Updates**: Via `globalizeLiquidity`, callable by liquidity contracts:
  - Validates non-zero tokens, user, listing ID, and caller (liquidity contract).
  - For deposits: Increments liquidity mappings; for withdrawals: Decrements after sufficiency checks.
  - Normalizes amounts to 18 decimals.
  - Records historical data at `block.timestamp`.
  - Emits `GlobalLiquidityChanged` event.

### 4. Order Tracking
- **Mappings and Arrays**:
  - `globalOrders[token0][baseToken][orderId]`: Stores `GlobalOrder` (orderId, isBuy, maker, recipient, amount, status, timestamp).
  - `pairOrders[token0][baseToken]`: Array of orderIds for a pair, persistent across order statuses.
  - `userOrders[user]`: Array of orderIds for a user, persistent across order statuses.
  - `historicalOrderStatus[token0][baseToken][orderId][timestamp]`: Order status at timestamp.
  - `userTradingSummaries[user][token0][baseToken]`: User’s trading volume per pair.
- **Updates**: Via `globalizeOrders`, callable only by listing contracts (`msg.sender == getListing[token0][baseToken]`):
  - Validates non-zero tokens, maker, listing ID, and caller.
  - For new orders (`maker == address(0) && status != 0`): Initializes `GlobalOrder`, appends to `pairOrders` and `userOrders`.
  - For updates: Modifies `amount`, `status`, `timestamp`. Orders remain in `pairOrders` and `userOrders` even if canceled (status = 0) or filled (status = 3).
  - Records status in `historicalOrderStatus` and increments `userTradingSummaries` for non-zero amounts.
  - Emits `GlobalOrderChanged` event.
- **Status Codes**: 0 (canceled), 1 (pending), 2 (partially filled), 3 (filled).

### 5. Queries
- **User Liquidity Across Pairs**: Returns `token0s`, `baseTokens`, `amounts` for user’s non-zero liquidity. Caps at 100 pairs for gas efficiency.
- **Top Liquidity Providers**: Returns `users`, `amounts` for a listing ID, sorted descending, capped at 50.
- **User Liquidity Share**: Computes user’s share (`userAmount * 1e18 / total`) for a pair, with total liquidity.
- **Pairs by Liquidity**: Lists pairs with liquidity ≥ `minLiquidity`, configurable by `focusOnToken0`. Caps at 100 pairs.
- **Pair Liquidity Trend**: Queries `historicalLiquidityPerPair` over `[startTime, endTime]`:
  - If `focusOnToken0`, uses `token0/baseToken` pair.
  - If `!focusOnToken0`, iterates `allListedTokens` with `token0` as base token.
  - Returns non-zero `timestamps`, `amounts`. Gas-intensive for large ranges.
- **User Liquidity Trend**: Queries `historicalLiquidityPerUser`:
  - Iterates `allListedTokens`, uses `baseToken` as pair token based on `focusOnToken0`.
  - Returns non-zero `tokens`, `timestamps`, `amounts`. Gas-intensive for many tokens/ranges.
- **Order Activity by Pair**: Queries `globalOrders` over `[startTime, endTime]` for a pair, returning `orderIds` and `OrderData` (orderId, isBuy, maker, recipient, amount, status, timestamp).
- **User Trading Profile**: Returns `token0s`, `baseTokens`, `volumes` for user’s trading activity, capped at 100 pairs.
- **Top Traders by Volume**: Returns `traders`, `volumes` for a listing ID, sorted descending, capped at 50.
- **Pairs by Order Volume**: Lists pairs with order volume ≥ `minVolume`, configurable by `focusOnToken0`. Caps at 100 pairs.

### 6. Events
- `ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingId)`: Emitted on pair creation.
- `GlobalLiquidityChanged(listingId, token0, baseToken, user, amount, isDeposit)`: Emitted on liquidity updates.
- `GlobalOrderChanged(listingId, token0, baseToken, orderId, isBuy, maker, amount, status)`: Emitted on order updates.

### 7. Design Notes
- **Historical Data**: Sparse mappings store only changed states, reducing gas but requiring full range iteration for trends.
- **Order Persistence**: Orders remain in `pairOrders` and `userOrders` regardless of status, enabling historical queries.
- **Gas Warning**: Uncapped trend queries and order volume calculations risk high gas costs for large time ranges or token counts.
- **Decimal Handling**: Normalizes to 18 decimals in `checkCallerBalance` and `globalizeLiquidity`; `globalizeOrders` assumes normalized amounts.
- **Access Control**: `globalizeOrders` restricted to listing contracts, ensuring data integrity.

## OMFLiquidityTemplate.sol

`OMFLiquidityTemplate.sol` manages liquidity pools for a specific Token-0/base token pair, instantiated per listing. It handles deposits, withdrawals, fees, and slots, with non-reentrant guards.

### 1. Initialization
- **Parameters**: Sets via one-time functions:
  - `router`: Non-zero router address.
  - `listingId`: Unique listing identifier.
  - `listingAddress`: Non-zero listing contract address.
  - `token0`, `baseToken`: Non-zero, distinct token addresses.
  - `agent`: Non-zero `OMFAgent.sol` address for synchronization.

### 2. Liquidity Operations
- **Deposits**: Via `deposit`, router-only:
  - Transfers tokens (`token0` or `baseToken`), normalizes to 18 decimals.
  - Creates slot (`xLiquiditySlots` or `yLiquiditySlots`) with depositor, allocation, volume, timestamp.
  - Updates `activeXLiquiditySlots` or `activeYLiquiditySlots`.
  - Syncs with `OMFAgent.sol` via `globalizeLiquidity` (not `globalizeUpdate`, which is specific to orders in `OMFListingTemplate.sol`).
- **Withdrawals**:
  - **Preparation** (`xPrepOut`, `yPrepOut`): Calculates withdrawable amounts from slot allocation and liquidity (`xLiquid`, `yLiquid`). Converts deficits using listing’s price (scaled to 1e18), respecting available liquidity.
  - **Execution** (`xExecuteOut`, `yExecuteOut`): Updates slot allocation, transfers tokens (denormalized), syncs with `OMFAgent.sol` via `globalizeLiquidity`. Non-reentrant.
- **State**: `LiquidityDetails` struct tracks `xLiquid`, `yLiquid`, `xFees`, `yFees`.

### 3. Fee Operations
- **Addition**: Via `addFees`, router-only:
  - Transfers tokens, normalizes fees, updates `xFees` or `yFees`.
- **Claiming**: Via `claimFees`, router-only:
  - Computes share: `(volume - dVolume) * 0.05% * (allocation * 1e18 / liquid)`.
  - Caps at available fees, transfers denormalized amount, updates slot’s `dVolume`.

### 4. Slot Management
- **Updates**: Via `update`, handles balance, fee, and slot changes. Tracks depositors, allocations, volumes.
- **Depositor Change**: Via `changeSlotDepositor`, transfers slot ownership, updates `userIndex`.
- **Removal**: Removes zero-allocation slots, cleans `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`.

### 5. Utilities
- **Normalization**: Converts amounts to/from 18 decimals based on token decimals.
- **Views**: Expose `liquidityAmounts`, `feeAmounts`, `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView`, `userIndexView`, `getXSlotView`, `getYSlotView`.
- **Transactions**: Via `transact`, transfers tokens after liquidity checks, non-reentrant.

### 6. Design Notes
- **Sparse Slots**: Slots track only active contributions, reducing storage costs.
- **Price Conversion**: Withdrawal deficits use listing’s price, ensuring balanced exits.
- **Decimal Precision**: Normalization prevents precision loss across token decimals.
- **Clarification**: `globalizeUpdate` in this context refers to liquidity syncing via `globalizeLiquidity`, distinct from order syncing in `OMFListingTemplate.sol`.

## OMFListingTemplate.sol

`OMFListingTemplate.sol` manages a specific Token-0/base token pair’s order book, balances, and price data, instantiated per listing. It handles buy/sell orders, balance updates, and synchronization with `OMFAgent.sol`.

### 1. Initialization
- **Parameters**: Sets via one-time functions:
  - `router`: Non-zero router address (`routerAddress`).
  - `listingId`: Unique listing identifier (`listingId`).
  - `liquidityAddress`: Non-zero liquidity contract address (`liquidityAddress`).
  - `token0`, `baseToken`: Non-zero, distinct token addresses (`token0`, `baseToken`).
  - `oracle`: Non-zero oracle address with decimals (`oracle`, `oracleDecimals`).
  - `agent`: Non-zero `OMFAgent.sol` address (`agent`), callable by anyone but typically set by `OMFAgent.sol` during pair initialization.

### 2. Order Management
- **Updates**: Via `update`, router-only, processes `UpdateType` arrays:
  - **Balance Updates**: Sets `xBalance`, `yBalance` or increments `xVolume`, `yVolume` in `volumeBalance`.
  - **Buy Orders**: Creates or updates orders in `buyOrderCores`, `buyOrderPricings`, `buyOrderAmounts`:
    - New orders: Assigns `orderId` via `orderIdHeight`, sets maker, recipient, status (1), adds to `pendingBuyOrders` and `makerPendingOrders`.
    - Cancellations: Sets status to 0, removes from `pendingBuyOrders` and `makerPendingOrders`.
    - Fills: Reduces `pending`, increases `filled`, adjusts `xBalance` or `yBalance`, updates status (2 or 3), removes from pending arrays if fully filled.
  - **Sell Orders**: Similar to buy orders, using `sellOrderCores`, `sellOrderPricings`, `sellOrderAmounts`, `pendingSellOrders`.
  - **Historical Data**: Stores price, balances, volumes, timestamp in `historicalData`.
  - **Price Calculation**: Updates `price` as `(xBalance * 1e18) / yBalance` if both non-zero.
  - Emits `OrderUpdated(orderId, isBuy, status)` and `BalancesUpdated(xBalance, yBalance)`.
- **Synchronization**: Calls `globalizeUpdate` at the end of `update` to sync pending orders with `OMFAgent.sol`.

### 3. Order Synchronization
- **globalizeUpdate**: External, callable by anyone:
  - Iterates `pendingBuyOrders` and `pendingSellOrders`, syncing orders with status 1 (pending) or 2 (partially filled).
  - Fetches `makerAddress`, `recipientAddress`, `pending` amount, and `status` from respective mappings.
  - Calls `OMFAgent.globalizeOrders` with normalized amounts, wrapped in `try/catch` for graceful degradation.
  - Skips if `agent` is unset.
- **Purpose**: Ensures `OMFAgent.sol` tracks the latest order states for global queries.

### 4. Data Structures
- **Structs**:
  - `VolumeBalance`: Tracks `xBalance`, `yBalance`, `xVolume`, `yVolume`.
  - `BuyOrderCore`: Stores `makerAddress`, `recipientAddress`, `status` (0 = canceled, 1 = pending, 2 = partially filled, 3 = filled).
  - `BuyOrderPricing`: Stores `maxPrice`, `minPrice`.
  - `BuyOrderAmounts`: Stores `pending`, `filled` amounts (normalized).
  - `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`: Analogous for sell orders.
  - `HistoricalData`: Stores `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
  - `UpdateType`: Defines update type (0 = balance, 1 = buy order, 2 = sell order, 3 = historical), struct ID, index, values, and addresses.
- **Mappings**:
  - `buyOrderCores[orderId]`, `buyOrderPricings[orderId]`, `buyOrderAmounts[orderId]`: Buy order details.
  - `sellOrderCores[orderId]`, `sellOrderPricings[orderId]`, `sellOrderAmounts[orderId]`: Sell order details.
  - `isBuyOrderComplete[orderId]`, `isSellOrderComplete[orderId]`: Tracks order completeness.
  - `makerPendingOrders[maker]`: Array of orderIds for a maker.
- **Arrays**:
  - `pendingBuyOrders`: Active buy orderIds (status 1 or 2).
  - `pendingSellOrders`: Active sell orderIds (status 1 or 2).
  - `historicalData`: Array of `HistoricalData` entries.

### 5. Utilities
- **Normalization**: `normalize` converts amounts to 18 decimals; `denormalize` reverses for transfers.
- **Transactions**: `transact`, router-only, transfers `token0` or `baseToken` after balance checks, updates `volumeBalance` and `price`, non-reentrant.
- **Order Removal**: `removePendingOrder` removes orderIds from `pendingBuyOrders`, `pendingSellOrders`, or `makerPendingOrders` using pop-and-swap.
- **Price Fetching**: `getPrice` queries oracle’s `latestPrice`, scales to 18 decimals based on `oracleDecimals`.

### 6. Views
- `listingVolumeBalancesView`: Returns `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- `listingPriceView`: Returns current `price`.
- `pendingBuyOrdersView`, `pendingSellOrdersView`: Return active orderId arrays.
- `makerPendingOrdersView(maker)`: Returns maker’s pending orderIds.
- `getHistoricalDataView(index)`, `historicalDataLengthView`: Access historical data.
- `buyOrderCoreView(orderId)`, `buyOrderPricingView(orderId)`, `buyOrderAmountsView(orderId)`: Return buy order details.
- `sellOrderCoreView(orderId)`, `sellOrderPricingView(orderId)`, `sellOrderAmountsView(orderId)`: Return sell order details.
- `isOrderCompleteView(orderId, isBuy)`: Returns completion status.

### 7. Events
- `OrderUpdated(orderId, isBuy, status)`: Emitted on order creation, update, or cancellation.
- `BalancesUpdated(xBalance, yBalance)`: Emitted on balance changes.

### 8. Design Notes
- **Sparse Storage**: `pendingBuyOrders`, `pendingSellOrders` track only active orders, reducing gas.
- **Decimal Precision**: All amounts normalized to 18 decimals, with `normalize`/`denormalize` for token transfers.
- **Gas Warning**: `globalizeUpdate` may be gas-intensive for many pending orders; consider batching for large order books.
- **Access Control**: `setAgent` is public but one-time, typically called by `OMFAgent.sol`. `globalizeUpdate` is public for flexibility.
- **Graceful Degradation**: `globalizeUpdate` uses `try/catch` and skips if `agent` is unset.

## System Considerations
- **Security**: Ownable (`OMFAgent`), router-only (`OMFLiquidityTemplate`, `OMFListingTemplate` for critical functions), non-reentrant guards.
- **Gas**: Sparse mappings optimize storage; uncapped trend queries and `globalizeUpdate` risk high costs for large datasets.
- **Error Handling**: Reverts on invalid inputs; returns empty arrays for no data; `try/catch` in `globalizeUpdate`.
- **Scalability**: Supports multiple pairs and orders, but trend queries and order syncing may limit large-scale usage without optimization.
- **Order Persistence**: Orders remain in `OMFAgent.sol`’s `pairOrders` and `userOrders`, enabling historical analysis but increasing storage.
- **Decimal Normalization**: All contracts normalize to 18 decimals, ensuring precision across token decimals.

## Conclusion
`OMFAgent.sol` orchestrates listings, liquidity aggregation, and order tracking, while `OMFLiquidityTemplate.sol` manages per-pair pools and `OMFListingTemplate.sol` handles order books and balances. The system ensures secure, precise operations with normalized decimals and sparse storage, though trend queries and order synchronization require gas optimization for large-scale usage.