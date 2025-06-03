# OMF Contracts System Specification

This document specifies the decentralized exchange (DEX) system comprising `OMFAgent.sol`, `OMFLiquidityTemplate.sol`, `OMFListingTemplate.sol`, `OMFListingLogic.sol`, `OMFLiquidityLogic.sol`, and `OMFRouter.sol` (incorporating `MainPartial.sol`, `OrderPartial.sol`, and `SettlementPartial.sol` as a single contract via imports). Built for Solidity 0.8.2 with BSD-3-Clause license, the contracts manage token listings, liquidity pools, order books, and settlements. Price is acquired from an oracle address and function supplied in each listing, with all assets listed as ASSET/USD. The system ensures security, gas efficiency, and decimal normalization (18 decimals). `TokenRegistry.sol` is referenced for balance tracking but is not part of the OMF system. This specification details data structures, operations, and design considerations, incorporating updates to `OMFAgent.sol` for the implementation of `validateListing` to ensure compatibility with `OrderPartial.sol`.

## OMFAgent.sol

`OMFAgent.sol` is an ownable contract orchestrating token listings, liquidity aggregation, and order tracking. It deploys listing and liquidity contracts via logic contracts, maintains global state, and validates listings for order creation. The contract was updated in version 0.0.14 to implement `validateListing` for compatibility with `OrderPartial.sol`.

### 1. Configuration
- **State Variables**:
  - `routerAddress`: Address of the router contract mediating interactions.
  - `listingLogicAddress`: Address of `OMFListingLogic` for proxy deployment.
  - `liquidityLogicAddress`: Address of `OMFLiquidityLogic` for proxy deployment.
  - `baseToken`: Reference token (Token-1) for all pairs, set via `setBaseToken`.
  - `registryAddress`: Address of `TokenRegistry.sol`, set via `setRegistry` for balance tracking.
  - `listingCount`: Counter for deployed listings, incremented per new listing.
- **Setters** (onlyOwner):
  - `setRouter(_routerAddress)`: Sets `routerAddress`, requires non-zero address.
  - `setListingLogic(_listingLogic)`: Sets `listingLogicAddress`, requires non-zero address.
  - `setLiquidityLogic(_liquidityLogic)`: Sets `liquidityLogicAddress`, requires non-zero address.
  - `setBaseToken(_baseToken)`: Sets `baseToken`, requires non-zero address (native token disallowed).
  - `setRegistry(_registryAddress)`: Sets `registryAddress`, requires non-zero address.

### 2. Token Listing
- **listToken(tokenA, oracleAddress, oracleDecimals, oracleViewFunction) → (listingAddress, liquidityAddress)**:
  - **Parameters**:
    - `tokenA`: Address of Token-0, must be non-zero and distinct from `baseToken`.
    - `oracleAddress`: Address of the price oracle, must be non-zero.
    - `oracleDecimals`: Decimals of oracle price data.
    - `oracleViewFunction`: Function selector for oracle price query.
  - **Validations**:
    - Ensures `baseToken` is set, `tokenA` is unlisted (`getListing[tokenA][baseToken] == address(0)`), and caller holds ≥1% of `tokenA` supply (via `checkCallerBalance`).
    - Checks non-zero `routerAddress`, `listingLogicAddress`, `liquidityLogicAddress`, and `oracleAddress`.
  - **Operations**:
    - Generates deterministic salts: `listingSalt = keccak256(tokenA, baseToken, listingCount)`, `liquiditySalt = keccak256(baseToken, tokenA, listingCount)`.
    - Deploys listing via `OMFListingLogic.deploy(listingSalt)` and liquidity via `OMFLiquidityLogic.deploy(liquiditySalt)`.
    - Initializes listing with `setRouter`, `setListingId`, `setLiquidityAddress`, `setTokens`, `setOracleDetails`, `setAgent`, `setRegistry`.
    - Initializes liquidity with `setRouter`, `setListingId`, `setListingAddress`, `setTokens`, `setAgent`.
    - Stores pair in `getListing[tokenA][baseToken]`, adds to `allListings`, adds `tokenA` to `allListedTokens` if new.
    - Increments `listingCount`.
  - **Returns**: Deployed `listingAddress` and `liquidityAddress`.
  - **Events**:
    - `ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingId)`.

### 3. Liquidity Aggregation
- **Mappings**:
  - `globalLiquidity[token0][baseToken][user]`: User’s liquidity for a pair.
  - `totalLiquidityPerPair[token0][baseToken]`: Total liquidity for a pair.
  - `userTotalLiquidity[user]`: User’s total liquidity across pairs.
  - `listingLiquidity[listingId][user]`: User’s liquidity for a listing.
  - `historicalLiquidityPerPair[token0][baseToken][timestamp]`: Pair liquidity at timestamp.
  - `historicalLiquidityPerUser[token0][baseToken][user][timestamp]`: User liquidity at timestamp.
- **globalizeLiquidity(listingId, token0, baseToken, user, amount, isDeposit)**:
  - **Parameters**:
    - `listingId`: ID of the listing, must be less than `listingCount`.
    - `token0`: Token-0 address, must be non-zero.
    - `baseToken`: Base token address, must be non-zero.
    - `user`: User address, must be non-zero.
    - `amount`: Liquidity amount (normalized to 18 decimals).
    - `isDeposit`: True for deposits, false for withdrawals.
  - **Validations**:
    - Ensures non-zero `token0`, `baseToken`, `user`, valid `listingId`.
    - Verifies caller is the liquidity contract (`IOMFListing(listingAddress).liquidityAddress() == msg.sender`).
    - For withdrawals, checks sufficient liquidity in `globalLiquidity`, `totalLiquidityPerPair`, `userTotalLiquidity`, `listingLiquidity`.
  - **Operations**:
    - Updates liquidity mappings: increments for deposits, decrements for withdrawals.
    - Records historical data at `block.timestamp`.
  - **Events**:
    - `GlobalLiquidityChanged(listingId, token0, baseToken, user, amount, isDeposit)`.

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
  - **Parameters**:
    - `listingId`: ID of the listing, must be less than `listingCount`.
    - `token0`: Token-0 address, must be non-zero.
    - `baseToken`: Base token address, must be non-zero.
    - `orderId`: Unique order identifier.
    - `isBuy`: True for buy orders, false for sell orders.
    - `maker`: Order creator, must be non-zero.
    - `recipient`: Order recipient address.
    - `amount`: Order amount (normalized).
    - `status`: Order status (0–3).
  - **Validations**:
    - Ensures non-zero `token0`, `baseToken`, `maker`, valid `listingId`.
    - Verifies caller is the listing contract (`getListing[token0][baseToken] == msg.sender`).
  - **Operations**:
    - For new orders (`maker == address(0)` and `status != 0`): creates `GlobalOrder`, adds to `pairOrders` and `userOrders`.
    - For existing orders: updates `amount`, `status`, `timestamp`.
    - Records `historicalOrderStatus` at `block.timestamp`.
    - Increments `userTradingSummaries` if `amount > 0`.
  - **Events**:
    - `GlobalOrderChanged(listingId, token0, baseToken, orderId, isBuy, maker, amount, status)`.

### 5. Listing Validation
- **validateListing(listingAddress) → (isValid, listingAddress, token0, baseToken)**:
  - **Parameters**:
    - `listingAddress`: Address of the listing contract to validate.
  - **Validations**:
    - Checks if `listingAddress` is non-zero.
    - Ensures `baseToken` is set (non-zero).
    - Searches `allListedTokens` to find `token0` where `getListing[token0][baseToken] == listingAddress`.
  - **Operations**:
    - If `listingAddress` is zero or no matching `token0` is found, returns `(false, address(0), address(0), address(0))`.
    - If valid, returns `(true, listingAddress, token0, baseToken)`.
  - **Purpose**:
    - Used by `OrderPartial.sol` in `createBuyOrder` and `createSellOrder` to verify listing validity before order creation.
    - Ensures `listingAddress` corresponds to a registered pair in `getListing`, providing `token0` and `baseToken` for order processing.
  - **Notes**:
    - Added in version 0.0.14 to ensure compatibility with `OrderPartial.sol`.
    - Iterates `allListedTokens`, which may be gas-intensive for large lists; future optimizations could include a reverse mapping.

### 6. View Functions
- **getUserLiquidityAcrossPairs(user, maxIterations) → (token0s, baseTokens, amounts)**:
  - Returns up to `maxIterations` non-zero liquidity pairs for `user`.
- **getTopLiquidityProviders(listingId, maxIterations) → (users, amounts)**:
  - Returns top liquidity providers for `listingId`, sorted descending, up to `maxIterations`.
- **getUserLiquidityShare(user, token0, baseToken) → (share, total)**:
  - Returns user’s liquidity share (`userAmount * 1e18 / total`) and total pair liquidity.
- **getAllPairsByLiquidity(minLiquidity, focusOnToken0, maxIterations) → (token0s, baseTokens, amounts)**:
  - Lists pairs with liquidity ≥ `minLiquidity`, up to `maxIterations`.
- **getPairLiquidityTrend(token0, focusOnToken0, startTime, endTime) → (timestamps, amounts)**:
  - Returns non-zero liquidity timestamps and amounts for a pair within time range.
- **getUserLiquidityTrend(user, focusOnToken0, startTime, endTime) → (tokens, timestamps, amounts)**:
  - Returns user’s non-zero liquidity tokens, timestamps, amounts within time range.
- **getOrderActivityByPair(token0, baseToken, startTime, endTime) → (orderIds, orders)**:
  - Returns orderIds and details for a pair within time range.
- **getUserTradingProfile(user) → (token0s, baseTokens, volumes)**:
  - Returns user’s trading volumes per pair.
- **getTopTradersByVolume(listingId, maxIterations) → (traders, volumes)**:
  - Returns top traders by volume for `listingId`, sorted descending, up to `maxIterations`.
- **getAllPairsByOrderVolume(minVolume, focusOnToken0, maxIterations) → (token0s, baseTokens, volumes)**:
  - Lists pairs with order volume ≥ `minVolume`, up to `maxIterations`.
- **allListingsLength() → (uint256)**:
  - Returns number of listings.

### 7. Design Notes
- **Decimal Handling**: Normalizes to 18 decimals in `checkCallerBalance` using ERC20 `decimals`.
- **Gas Efficiency**: Sparse mappings; `maxIterations` limits loops. `validateListing` and trend queries may consume high gas due to array iteration.
- **Access Control**: `globalizeOrders` restricted to listing contracts; `globalizeLiquidity` to liquidity contracts; setters restricted to owner.
- **Registry Usage**: Sets `registryAddress` in new listings for balance tracking; does not directly use registry for balances.
- **Updates**: Version 0.0.14 added `validateListing` to support `OrderPartial.sol`’s order creation, ensuring robust listing verification.

## OMFListingLogic.sol

`OMFListingLogic.sol` deploys `OMFListingTemplate` contracts using deterministic salts.

### 1. Core Functions
- **deploy(listingSalt) → (listingAddress)**:
  - Deploys `OMFListingTemplate` with `listingSalt` via CREATE2.
  - Returns deployed contract address.

### 2. Design Notes
- **Purpose**: Separates listing deployment from `OMFAgent`, resolving `SafeERC20` import conflicts.
- **Gas Efficiency**: Minimal logic, uses CREATE2 for deterministic deployment.
- **Access Control**: Public, no restrictions.

## OMFLiquidityLogic.sol

`OMFLiquidityLogic.sol` deploys `OMFLiquidityTemplate` contracts using deterministic salts.

### 1. Core Functions
- **deploy(liquiditySalt) → (liquidityAddress)**:
  - Deploys `OMFLiquidityTemplate` with `liquiditySalt` via CREATE2.
  - Returns deployed contract address.

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
  - Validates caller as depositor, sufficient allocation.
  - Calculates `withdrawAmount0` (capped at `xLiquid`), `withdrawAmount1` (deficit converted via listing’s price, capped at `yLiquid`).
  - Returns `PreparedWithdrawal`.
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
  - Validates listing via `OMFAgent.validateListing`, prepares and applies order updates, emits `OrderCreated`.
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
- **processPrimaryUpdates(listingAddress, state, orderIds, count, isBuy)**:
  - Prepares and applies primary updates using dynamic arrays.
- **transferToLiquidity(listingAddress, liquidityAddress, state, primaryUpdates, isBuy)**:
  - Transfers tokens to liquidity for successful orders.
- **processSecondaryUpdates(listingAddress, liquidityAddress, state, orderIds, count, isBuy)**:
  - Prepares and applies secondary updates.
- **prepBuyOrderCore**, **prepSellOrderCore**, **prepBuyOrderPricing**, **prepSellOrderPricing**, **prepBuyOrderAmounts**, **prepSellOrderAmounts**: Prepare order updates.
- **applySinglePrimaryUpdate**, **applySingleSecondaryUpdate**: Apply single updates.
- **prepBuyCores**, **prepSellCores**, **processPrepBuyCores**, **processPrepSellCores**: Process order updates for settlements.
- **prepareBuyBatchPrimaryUpdates**, **prepareSellBatchPrimaryUpdates**, **prepareBuyBatchSecondaryUpdates**, **prepareSellBatchSecondaryUpdates**: Build dynamic arrays of updates.
- **prepareBuyLiquidSecondaryUpdates**, **prepareSellLiquidSecondaryUpdates**: Similar to batch updates.

### 3. Events
- **OrderProcessingFailed(listingAddress, orderId, isBuy, reason)**:
  - Emitted when an order fails processing.

### 4. Design Notes
- **Decimal Handling**: Uses `normalize`/`denormalize` from `MainPartial`.
- **Gas Efficiency**: Splits updates to avoid stack issues. Loops bounded by `count`.
- **Access Control**: Public for user-facing functions.
- **Registry Usage**: Relies on listing contract for registry interactions.

## System Considerations
- **Security**: Ownable (`OMFAgent`), `onlyRouter` guards, non-reentrant functions, `SafeERC20`, `try/catch` for external calls.
- **Gas Efficiency**: Sparse storage, `maxIterations`, dynamic arrays. Trend queries and `globalizeUpdate` risk high gas.
- **Decimal Normalization**: 18 decimals using ERC20 `decimals` or oracle data.
- **Registry Integration**: Optional in liquidity contracts, used in listings for balance tracking.
- **Modularity**: Logic contracts and partials enhance maintainability.
- **Updates**: `OMFAgent.sol`’s `validateListing` ensures robust listing verification for `OrderPartial.sol`.


