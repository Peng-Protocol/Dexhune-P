# OMF Contracts System Specification

This document specifies the decentralized exchange (DEX) system comprising `OMFAgent.sol`, `OMFLiquidityTemplate.sol`, `OMFListingTemplate.sol`, `OMFListingLogic.sol`, `OMFLiquidityLogic.sol`, and `OMFRouter.sol` (incorporating `MainPartial.sol`, `OrderPartial.sol`, and `SettlementPartial.sol` as a single contract via imports). Built for Solidity 0.8.2 with BSD-3-Clause license, the contracts manage token listings - liquidity pools - order books - and settlements, price is acquired from an oracle address and function supplied in each listing, all assets are listed as ASSET/USD. The system ensures security, gas efficiency, and decimal normalization (18 decimals). `TokenRegistry.sol` is referenced for balance tracking but is not part of the OMF system. This specification details data structures, operations, and design considerations, incorporating the provided contracts.

## OMFAgent.sol

`OMFAgent.sol` is an ownable contract orchestrating token listings, liquidity aggregation, and order tracking. It deploys listing and liquidity contracts via logic contracts and maintains global state.

### 1. Configuration
- **State Variables**:
  - `routerAddress`: Router for mediating interactions.
  - `listingLogicAddress`, `liquidityLogicAddress`: Logic contracts for proxy deployment.
  - `baseToken`: Reference token (Token-1) for pairs.
  - `registryAddress`: `TokenRegistry.sol` address, set via `setRegistry` (onlyOwner).
  - `listingCount`: Tracks deployed listings.
- **Setters** (onlyOwner):
  - `setRouter`, `setListingLogic`, `setLiquidityLogic`, `setBaseToken`, `setRegistry`.

### 2. Token Listing
- **listToken(tokenA, oracleAddress, oracleDecimals, oracleViewFunction)**:
  - Validates: Non-zero `tokenA`, distinct from `baseToken`, unlisted, caller holds ≥1% of `tokenA` supply (checked via ERC20 `balanceOf`, normalized to 18 decimals).
  - Deploys: Listing and liquidity proxies via `OMFListingLogic` and `OMFLiquidityLogic` using deterministic salts (`keccak256(tokenA, baseToken, listingCount)`).
  - Initializes: Listing with router, tokens, `listingId`, agent, registry, oracle data, liquidity address; liquidity with router, tokens, `listingId`, agent, listing address.
  - Stores: Maps pair to listing (`getListing[tokenA][baseToken]`), tracks listings (`allListings`), tokens (`allListedTokens`).
  - Increments `listingCount`.
- **Events**:
  - `ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingId)`.

### 3. Liquidity Aggregation
- **Mappings**:
  - `globalLiquidity[token0][baseToken][user]`: User liquidity per pair.
  - `totalLiquidityPerPair[token0][baseToken]`: Total pair liquidity.
  - `userTotalLiquidity[user]`: User’s total liquidity.
  - `listingLiquidity[listingId][user]`: Liquidity per listing.
  - `historicalLiquidityPerPair[token0][baseToken][timestamp]`: Pair liquidity at timestamp.
  - `historicalLiquidityPerUser[token0][baseToken][user][timestamp]`: User liquidity at timestamp.
- **globalizeLiquidity(listingId, token0, baseToken, user, amount, isDeposit)**:
  - Validates: Non-zero tokens, user, valid `listingId`, caller is liquidity contract.
  - Updates: Increments (deposits) or decrements (withdrawals) liquidity mappings after sufficiency checks. Records historical data at `block.timestamp`.
  - Emits: `GlobalLiquidityChanged`.

### 4. Order Tracking
- **Struct**:
  - `GlobalOrder`: Stores `orderId`, `isBuy`, `maker`, `recipient`, `amount`, `status` (0 = canceled, 1 = pending, 2 = partially filled, 3 = filled), `timestamp`.
- **Mappings**:
  - `globalOrders[token0][baseToken][orderId]`: Order details.
  - `pairOrders[token0][baseToken]`: Array of orderIds per pair.
  - `userOrders[user]`: Array of orderIds per user.
  - `historicalOrderStatus[token0][baseToken][orderId][timestamp]`: Order status at timestamp.
  - `userTradingSummaries[user][token0][baseToken]`: User’s trading volume.
- **globalizeOrders(listingId, token0, baseToken, orderId, isBuy, maker, recipient, amount, status)**:
  - Validates: Non-zero tokens, maker, valid `listingId`, caller is listing contract.
  - Creates: New order if `maker` is unset and `status` non-zero.
  - Updates: Existing order’s `amount`, `status`, `timestamp`.
  - Stores: Order in `pairOrders`, `userOrders`, and `historicalOrderStatus`. Increments `userTradingSummaries`.
  - Emits: `GlobalOrderChanged`.

### 5. View Functions
- **getUserLiquidityAcrossPairs(user, maxIterations)**: Returns user’s non-zero liquidity pairs.
- **getTopLiquidityProviders(listingId, maxIterations)**: Returns top providers for a listing, sorted descending.
- **getUserLiquidityShare(user, token0, baseToken)**: Returns user’s share (`userAmount * 1e18 / total`) and total liquidity.
- **getAllPairsByLiquidity(minLiquidity, focusOnToken0, maxIterations)**: Lists pairs with liquidity ≥ `minLiquidity`.
- **getPairLiquidityTrend(token0, focusOnToken0, startTime, endTime)**: Returns non-zero liquidity timestamps and amounts.
- **getUserLiquidityTrend(user, focusOnToken0, startTime, endTime)**: Returns user’s non-zero liquidity tokens, timestamps, amounts.
- **getOrderActivityByPair(token0, baseToken, startTime, endTime)**: Returns orderIds and details within time range.
- **getUserTradingProfile(user)**: Returns user’s trading volumes per pair.
- **getTopTradersByVolume(listingId, maxIterations)**: Returns top traders by volume, sorted descending.
- **getAllPairsByOrderVolume(minVolume, focusOnToken0, maxIterations)**: Lists pairs with volume ≥ `minVolume`.
- **allListingsLength**(): Returns number of listings.
- **validateListing(listingAddress)**: Returns validity, agent, `token0`, `baseToken`.

### 6. Design Notes
- **Decimal Handling**: Normalizes to 18 decimals in `checkCallerBalance`.
- **Gas Efficiency**: Sparse mappings; `maxIterations` limits loops. Trend queries risk high gas.
- **Access Control**: `globalizeOrders` restricted to listing contracts; `globalizeLiquidity` to liquidity contracts.
- **Registry Usage**: Sets `registryAddress` in new listings for balance tracking; does not directly use registry for balances.

## OMFListingLogic.sol

`OMFListingLogic.sol` deploys `OMFListingTemplate` contracts using deterministic salts.

### 1. Core Functions
- **deploy(listingSalt)**:
  - Deploys: `OMFListingTemplate` with `listingSalt`.
  - Returns: Deployed contract address.

### 2. Design Notes
- **Purpose**: Separates listing deployment from `OMFAgent`, resolving `SafeERC20` import conflicts.
- **Gas Efficiency**: Minimal logic, uses CREATE2 for deterministic deployment.
- **Access Control**: Public, no restrictions.

## OMFLiquidityLogic.sol

`OMFLiquidityLogic.sol` deploys `OMFLiquidityTemplate` contracts using deterministic salts.

### 1. Core Functions
- **deploy(liquiditySalt)**:
  - Deploys: `OMFLiquidityTemplate` with `liquiditySalt`.
  - Returns: Deployed contract address.

### 2. Design Notes
- **Purpose**: Isolates liquidity deployment, resolving `SafeERC20` import conflicts.
- **Gas Efficiency**: Minimal logic, uses CREATE2.
- **Access Control**: Public, no restrictions.

## OMFLiquidityTemplate.sol

`OMFLiquidityTemplate.sol` manages liquidity pools for a Token-0/base token pair, handling deposits, withdrawals, and fees. Deployed per listing.

### 1. Initialization
- **State Variables**:
  - `router`, `listingAddress`, `listingId`, `agent`, `token0`, `baseToken`.
- **Setters** (one-time):
  - `setRouter`, `setListingId`, `setListingAddress`, `setTokens`, `setAgent`.

### 2. Data Structures
- **Structs**:
  - `LiquidityDetails`: Tracks `xLiquid`, `yLiquid`, `xFees`, `yFees`.
  - `Slot`: Stores `depositor`, `allocation` (normalized), `dVolume` (volume at deposit), `timestamp`.
  - `UpdateType`: Defines update type (0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot), `index`, `value`, `addr`, `recipient`.
  - `PreparedWithdrawal`: Stores `amount0` (token0), `amount1` (baseToken).
- **Mappings**:
  - `xLiquiditySlots[index]`, `yLiquiditySlots[index]`: Slot details.
  - `userIndex[user]`: Slot indices per user.
- **Arrays**:
  - `activeXLiquiditySlots`, `activeYLiquiditySlots`: Active slot indices.
- **Events**:
  - `LiquidityAdded(isX, amount)`, `FeesAdded(isX, amount)`, `FeesClaimed(isX, amount, depositor)`.
  - `LiquidityUpdated(xLiquid, yLiquid)`, `SlotDepositorChanged(isX, slotIndex, oldDepositor, newDepositor)`.
  - `GlobalLiquidityUpdated(isX, amount, isDeposit, caller)`, `RegistryUpdateFailed(reason)`.

### 3. Core Functions
- **deposit(caller, isX, amount)** (onlyRouter, nonReentrant):
  - Transfers tokens (`token0` or `baseToken`), normalizes to 18 decimals.
  - Creates slot, updates `activeXLiquiditySlots` or `activeYLiquiditySlots`, `userIndex`.
  - Calls `update`, `globalizeUpdate`, `updateRegistry`.
- **xPrepOut(caller, amount, index)** (onlyRouter):
  - Validates: Caller is depositor, sufficient allocation.
  - Calculates: `withdrawAmount0` (capped at `xLiquid`), `withdrawAmount1` (deficit converted via listing’s price, capped at `yLiquid`).
  - Returns: `PreparedWithdrawal`.
- **yPrepOut(caller, amount, index)** (onlyRouter):
  - Similar to `xPrepOut`, for baseToken.
- **xExecuteOut(caller, index, withdrawal)** (onlyRouter, nonReentrant):
  - Updates slot allocation, transfers tokens (denormalized), calls `transact`, `globalizeUpdate`, `updateRegistry`.
- **yExecuteOut(caller, index, withdrawal)** (onlyRouter, nonReentrant):
  - Similar to `xExecuteOut`, for baseToken and token0.
- **addFees(caller, isX, fee)** (onlyRouter, nonReentrant):
  - Transfers tokens, updates fees via `update`.
- **claimFees(caller, isX, slotIndex, volume)**:
  - Calculates share: `(volume - dVolume) * 0.05% * (allocation * 1e18 / liquid)`, capped at available fees.
  - Transfers fees (denormalized), updates `dVolume`.
- **update(caller, updates)** (onlyRouter):
  - Processes `UpdateType` array: updates balances, fees, slots.
  - Manages slot creation/removal, `userIndex`, `activeXLiquiditySlots`, `activeYLiquiditySlots`.
- **changeSlotDepositor(caller, isX, slotIndex, newDepositor)** (onlyRouter):
  - Transfers slot ownership, updates `userIndex`.
- **transact(caller, token, amount, recipient)** (onlyRouter, nonReentrant):
  - Transfers tokens after liquidity checks, updates `xLiquid` or `yLiquid`.
- **updateRegistry(caller, isX)** (internal):
  - Fetches `registryAddress` from listing, calls `TokenRegistry.initializeBalances`.

### 4. View Functions
- **liquidityAmounts()**: Returns `xLiquid`, `yLiquid`.
- **feeAmounts()**: Returns `xFees`, `yFees`.
- **activeXLiquiditySlotsView()**, **activeYLiquiditySlotsView()**: Return active slot indices.
- **userIndexView(user)**: Returns user’s slot indices.
- **getXSlotView(index)**, **getYSlotView(index)**: Return slot details.
- **token0()**, **baseToken()**: Return token addresses.

### 5. Design Notes
- **Decimal Handling**: Normalizes to 18 decimals using ERC20 `decimals`.
- **Gas Efficiency**: Sparse slots, dynamic arrays. No `maxIterations` for loops.
- **Access Control**: `onlyRouter` for critical functions.
- **Registry Usage**: Fetches `registryAddress` from listing for balance updates.
- **Error Handling**: `try/catch` in `updateRegistry`, reverts on invalid inputs.

## OMFListingTemplate.sol

`OMFListingTemplate.sol` manages a Token-0/base token pair’s order book, balances, and price data, deployed per listing.

### 1. Initialization
- **State Variables**:
  - `routerAddress`, `token0`, `baseToken`, `listingId`, `oracle`, `oracleDecimals`, `agent`, `registryAddress`, `liquidityAddress`, `orderIdHeight`, `lastDay`.
- **Setters** (one-time):
  - `setRouter`, `setListingId`, `setLiquidityAddress`, `setTokens`, `setOracle`, `setAgent`, `setRegistry`.

### 2. Data Structures
- **Structs**:
  - `VolumeBalance`: Tracks `xBalance`, `yBalance`, `xVolume`, `yVolume`.
  - `BuyOrderCore`: Stores `makerAddress`, `recipientAddress`, `status`.
  - `BuyOrderPricing`: Stores `maxPrice`, `minPrice`.
  - `BuyOrderAmounts`: Stores `pending`, `filled` (normalized).
  - `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`: Analogous for sell orders.
  - `HistoricalData`: Stores `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
  - `ListingUpdateType`: Defines update type, `structId`, `index`, `value`, addresses, prices.
- **Mappings**:
  - `buyOrderCores[orderId]`, `buyOrderPricings[orderId]`, `buyOrderAmounts[orderId]`: Buy order details.
  - `sellOrderCores[orderId]`, `sellOrderPricings[orderId]`, `sellOrderAmounts[orderId]`: Sell order details.
  - `isBuyOrderComplete[orderId]`, `isSellOrderComplete[orderId]`: Order completeness.
  - `makerPendingOrders[maker]`: OrderIds per maker.
- **Arrays**:
  - `pendingBuyOrders`, `pendingSellOrders`: Active orderIds (status 1 or 2).
  - `historicalData`: Historical data entries.
- **Events**:
  - `OrderUpdated(orderId, isBuy, status)`, `BalancesUpdated(xBalance, yBalance)`, `RegistryUpdateFailed(reason)`.

### 3. Core Functions
- **update(updates)** (onlyRouter):
  - Processes `ListingUpdateType` array: updates balances, orders, historical data.
  - Updates `price`, `lastDay`. Calls `globalizeUpdate`.
- **transact(token, amount, recipient)** (onlyRouter):
  - Transfers tokens, updates balances/volumes, `price`, `lastDay`. Calls `updateRegistry`.
- **globalizeUpdate()**:
  - Syncs orders with `OMFAgent.globalizeOrders` using `try/catch`.
- **updateRegistry()**:
  - Calls `TokenRegistry.initializeBalances` for order makers with `try/catch`.
- **queryYield(isX, maxIterations)**:
  - Computes APY using volume changes from `historicalData`, liquidity from `OMFLiquidityTemplate`.

### 4. View Functions
- **volumeBalances()**: Returns `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **getPrice()**: Returns oracle price (18 decimals).
- **pendingBuyOrdersView()**, **pendingSellOrdersView()**: Return active orderIds.
- **makerPendingOrdersView(maker)**: Returns maker’s orderIds.
- **buyOrderCoreView(orderId)**, **buyOrderPricingView(orderId)**, **buyOrderAmountsView(orderId)**: Buy order details.
- **sellOrderCoreView(orderId)**, **sellOrderPricingView(orderId)**, **sellOrderAmountsView(orderId)**: Sell order details.
- **isOrderCompleteView(orderId, isBuy)**: Returns completion status.
- **liquidityAddress()**, **token0()**, **baseToken()**: Return addresses.

### 5. Design Notes
- **Decimal Handling**: Normalizes to 18 decimals.
- **Gas Efficiency**: `maxIterations` in `queryYield`. `globalizeUpdate` risks high gas.
- **Access Control**: `onlyRouter` for critical functions.
- **Registry Usage**: Updates maker balances.

## OMFRouter.sol

`OMFRouter.sol`, incorporating `MainPartial.sol`, `OrderPartial.sol`, and `SettlementPartial.sol` via imports, forms a single contract handling user interactions for liquidity management, order creation, and settlements.

### 1. Core Functions
- **deposit(listingAddress, isX, amount)**:
  - Validates listing, transfers tokens to liquidity contract, calls `deposit`.
- **withdrawLiquidity(listingAddress, isX, amount, slotIndex)**:
  - Validates listing, prepares and executes withdrawal via `xPrepOut`/`yPrepOut` and `xExecuteOut`/`yExecuteOut`.
- **claimFees(listingAddress, isX, slotIndex)**:
  - Validates listing, fetches volume from `volumeBalances`, calls `claimFees`.
- **changeDepositor(listingAddress, isX, slotIndex, newDepositor)**:
  - Validates listing and `newDepositor`, calls `changeSlotDepositor`.
  - Emits: `DepositorChanged`.
- **settleBuyOrders(listingAddress)**:
  - Validates listing, executes buy orders via `executeBuyOrders`.
- **settleSellOrders(listingAddress)**:
  - Validates listing, executes sell orders via `executeSellOrders`.
- **settleBuyLiquid(listingAddress)**:
  - Validates listing, executes buy orders with liquidity via `executeBuyLiquid`.
- **settleSellLiquid(listingAddress)**:
  - Validates listing, executes sell orders with liquidity via `executeSellLiquid`.
- **createBuyOrder(listingAddress, amount, maxPrice, minPrice, recipient)**:
  - Validates listing, prepares and applies order updates, emits `OrderCreated`.
- **createSellOrder(listingAddress, amount, maxPrice, minPrice, recipient)**:
  - Similar to `createBuyOrder` for sell orders.

### 2. Internal Functions
- **executeBuyOrders(listingAddress, count)**:
  - Prepares state, processes primary and secondary updates.
- **executeSellOrders(listingAddress, count)**:
  - Similar to `executeBuyOrders` for sell orders.
- **executeBuyLiquid(listingAddress, count)**:
  - Prepares state, fetches orders, processes primary updates, transfers to liquidity, processes secondary updates.
- **executeSellLiquid(listingAddress, count)**:
  - Similar to `executeBuyLiquid` for sell orders.
- **prepareExecutionState(listingAddress)**: Returns `LiquidExecutionState`.
- **fetchPendingOrders(listingAddress, count, isBuy)**: Returns orderIds, adjusted count.
- **processPrimaryUpdates(listingAddress, state, orderIds, count, isBuy)**: Prepares and applies primary updates.
- **transferToLiquidity(listingAddress, liquidityAddress, state, primaryUpdates, isBuy)**: Transfers tokens to liquidity.
- **processSecondaryUpdates(listingAddress, liquidityAddress, state, orderIds, count, isBuy)**: Prepares and applies secondary updates.
- **prepBuyOrderCore**, **prepSellOrderCore**, **prepBuyOrderPricing**, **prepSellOrderPricing**, **prepBuyOrderAmounts**, **prepSellOrderAmounts**: Prepare order updates.
- **applySinglePrimaryUpdate**, **applySingleSecondaryUpdate**: Apply single updates.
- **prepBuyCores**, **prepSellCores**, **processPrepBuyCores**, **processPrepSellCores**: Process order updates for settlements.

### 3. Design Notes
- **Decimal Handling**: Uses `normalize`/`denormalize` from `MainPartial`.
- **Gas Efficiency**: Splits updates to avoid stack issues. Loops bounded by `count`.
- **Access Control**: Public for user-facing functions.
- **Registry Usage**: Relies on listing contract for registry interactions.

## System Considerations
- **Security**: Ownable (`OMFAgent`), `onlyRouter` guards, non-reentrant functions, `SafeERC20`.
- **Gas Efficiency**: Sparse storage, `maxIterations`, batch updates. Trend queries and `globalizeUpdate` risk high gas.
- **Decimal Normalization**: 18 decimals using ERC20 `decimals` or oracle data.
- **Registry Integration**: Optional in liquidity contracts, used in listings for balance tracking.
- **Modularity**: Logic contracts and partials enhance maintainability.

