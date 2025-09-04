# MFPListingTemplate Documentation

## Overview
The `MFPListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, price discovery via `IERC20.balanceOf`. It manages buy and sell orders and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement or cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

**Version**: 0.3.8 (Updated 2025-09-04)

**Changes**:
- v0.3.8: Added minimum price "1", in prices. 
- v0.3.7: Created "MFP" from "SS", removed Uniswap functionality. 

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.9)


## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail()`.
- **ITokenRegistry**: Defines `initializeTokens(address, address[])`.
- **ICCGlobalizer**: Defines `globalizeOrders(address, address)`.
- **ICCAgent**: Defines `getLister(address)`, `getRouters()`.

## Structs
- **DayStartFee**: `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **Balance**: `xBalance`, `yBalance` (normalized, 1e18).
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **UpdateType**: `updateType` (0: balance, 1: buy, 2: sell, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## State Variables
- **`_routers`**: `mapping(address => bool) public` - Authorized routers.
- **`_routersSet`**: `bool private` - Locks router settings.
- **`tokenA`, `tokenB`**: `address public` - Token pair (ETH as `address(0)`).
- **`decimalsA`, `decimalsB`**: `uint8 public` - Token decimals.
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agentView`**: `address public` - Agent address.
- **`registryAddress`**: `address public` - Registry address.
- **`liquidityAddressView`**: `address public` - Liquidity contract.
- **`globalizerAddress`, `_globalizerSet`**: `address public`, `bool private` - Globalizer contract.
- **`nextOrderId`**: `uint256 private` - Order ID counter.
- **`dayStartFee`**: `DayStartFee public` - Daily fee tracking.
- **`_pendingBuyOrders`, `_pendingSellOrders`**: `uint256[] private` - Pending order IDs.
- **`makerPendingOrders`**: `mapping(address => uint256[]) public` - Maker order IDs.
- **`_historicalData`**: `HistoricalData[] private` - Price/volume history.
- **`_dayStartIndices`**: `mapping(uint256 => uint256) private` - Midnight timestamps to indices.
- **`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`**: `mapping(uint256 => ...)` - Buy order data.
- **`sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`**: `mapping(uint256 => ...)` - Sell order data.
- **`orderStatus`**: `mapping(uint256 => OrderStatus) private` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets globalizer contract address (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Restrictions**: Reverts if already set or invalid address.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `globalizerAddress_` for `globalizeUpdate` calls to `ICCGlobalizer.globalizeOrders`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `transactToken`, `transactNative`.
- **State Changes**: `_routers`, `_routersSet`.
- **Restrictions**: Reverts if `_routersSet` or `routers_` invalid/empty.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `_routers` entries to true.

#### resetRouters()
- **Purpose**: Fetches lister via `ICCAgent.getLister`, restricts to lister, clears `_routers`, updates with `ICCAgent.getRouters`.
- **State Changes**: `_routers`, `_routersSet`.
- **Restrictions**: Reverts if `msg.sender` not lister or no routers.
- **Internal Call Tree**: `_clearRouters` (`ICCAgent.getRouters`), `_fetchAgentRouters` (`ICCAgent.getRouters`), `_setNewRouters`.
- **Parameters/Interactions**: Uses `agentView`, `listingId`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB` (callable once).
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `dayStartFee`.
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Calls `IERC20.decimals` for `tokenA_`, `tokenB_`.

#### setAgent(address agent_)
- **Purpose**: Sets `agentView` (callable once).
- **State Changes**: `agentView`.
- **Restrictions**: Reverts if `agentView` set or `agent_` invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `agentView` for `resetRouters`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `listingId` (callable once).
- **State Changes**: `listingId`.
- **Restrictions**: Reverts if `listingId` set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `listingId` for event emissions.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` (callable once).
- **State Changes**: `registryAddress`.
- **Restrictions**: Reverts if `registryAddress` set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `registryAddress` for `_updateRegistry`.

#### transactToken(address recipient, address token, uint256 amount)
- **Purpose**: Transfers ERC20 tokens via `IERC20.transfer`, updates `_balance`, calls `_updateRegistry`.
- **State Changes**: `_balance.xBalance` or `yBalance`.
- **Restrictions**: Router-only, sufficient balance.
- **Internal Call Tree**: `denormalize`, `_updateRegistry` (`ITokenRegistry.initializeTokens`, `uint2str`).
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `registryAddress`.

#### transactNative(address recipient, uint256 amount)
- **Purpose**: Transfers ETH via low-level `call`, updates `_balance`, calls `_updateRegistry`.
- **State Changes**: `_balance.xBalance` or `yBalance`.
- **Restrictions**: Router-only, sufficient balance.
- **Internal Call Tree**: `denormalize`, `_updateRegistry` (`ITokenRegistry.initializeTokens`, `uint2str`).
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `registryAddress`.

#### ccUpdate(uint8[] calldata updateType, uint8[] calldata updateSort, uint256[] calldata updateData)
- **Purpose**: Updates balances, buy/sell orders, or historical data, callable by routers.
- **Parameters**:
  - `updateType`: Array of update types (0: balance, 1: buy order, 2: sell order, 3: historical).
  - `updateSort`: Array specifying struct to update (0: Core, 1: Pricing, 2: Amounts for orders;  assent
- **Logic**:
  1. Verifies router caller and array length consistency.
  2. Computes current midnight timestamp (`(block.timestamp / 86400) * 86400`).
  3. Initializes `balanceUpdated`, `updatedOrders`, `updatedCount`.
  4. Processes updates:
     - **Balance (`updateType=0`)**: unused, retained for compatibility. 
     - **Buy Order (`updateType=1`)**: Calls `_processBuyOrderUpdate`:
       - `structId=0` (Core): Decodes `updateData[i]` as `(address makerAddress, address recipientAddress, uint8 status)`. Updates `buyOrderCore[orderId]`, manages `_pendingBuyOrders`, `makerPendingOrders` via `removePendingOrder` if `status=0` or `3`. Sets `orderStatus.hasCore`. Emits `OrderUpdated`.
       - `structId=1` (Pricing): Decodes `updateData[i]` as `(uint256 maxPrice, uint256 minPrice)`. Updates `buyOrderPricing[orderId]`. Sets `orderStatus.hasPricing`.
       - `structId=2` (Amounts): Decodes `updateData[i]` as `(uint256 pending, uint256 filled, uint256 amountSent)`. Updates `buyOrderAmounts[orderId]`, adds difference of old and new `filled` to `_historicalData.yVolume`, same for `amountSent` to `_historicalData.xVolume`. Sets `orderStatus.hasAmounts`.
       - Invalid `structId` emits `UpdateFailed`.
     - **Sell Order (`updateType=2`)**: Similar, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`, adds differenc of old and new `filled` to `_historicalData.xVolume`, same for `amountSent` to `_historicalData.yVolume`.
     - **Historical (`updateType=3`)**: Calls `_processHistoricalUpdate` to create `HistoricalData` with `price=updateData[i]`, current balances, timestamp, updates `_dayStartIndices`.
  5. Updates `dayStartFee` if not same day, fetching fees via `ICCLiquidityTemplate.liquidityDetail`.
  6. Checks `orderStatus` for completeness, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  7. Calls `globalizeUpdate`.
- **State Changes**: `_balance`, `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.balanceOf`, `ICCLiquidityTemplate.liquidityDetail`, `ITokenRegistry.initializeTokens` (via `_updateRegistry`), `ICCGlobalizer.globalizeOrders` (via `globalizeUpdate`).
- **Internal Call Tree**: `_processBalanceUpdate` (sets `_balance`, emits `BalancesUpdated`), `_processBuyOrderUpdate` (updates buy orders, calls `removePendingOrder`, `uint2str`, `_updateRegistry`), `_processSellOrderUpdate` (updates sell orders, calls `removePendingOrder`, `uint2str`, `_updateRegistry`), `_processHistoricalUpdate` (creates `HistoricalData`, calls `_floorToMidnight`), `_updateRegistry` (calls `ITokenRegistry.initializeTokens`), `globalizeUpdate` (calls `ICCGlobalizer.globalizeOrders`, `uint2str`), `_floorToMidnight` (timestamp rounding), `_isSameDay` (day check), `removePendingOrder` (array management), `uint2str` (error messages).
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.
- **Parameters/Interactions**: `updateType`, `updateSort`, `updateData` allow flexible updates. `updateData` encodes struct fields (e.g., `(address, address, uint8)` for Core) via `abi.decode`. Balances use `tokenA`, `tokenB` via `IERC20.balanceOf`. Fees and global updates interact with external contracts.


### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate` (`_processBalanceUpdate`, `_processBuyOrderUpdate`, `_processSellOrderUpdate`), `prices`, `volumeBalances`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: `transactToken`, `transactNative`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: Used for `dayStartFee` updates.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate` (`_processHistoricalUpdate`).
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (analytics in `CCDexlytan`).
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `ccUpdate` (`_processBuyOrderUpdate`, `_processSellOrderUpdate`), `transactToken`, `transactNative`.
- **Internal Call Tree**: `uint2str`.
- **Parameters/Interactions**: Calls `ITokenRegistry.initializeTokens` with `tokenA`, `tokenB`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `uint2str`.
- **Parameters/Interactions**: Calls `ICCGlobalizer.globalizeOrders` with `maker`, `tokenA` or `tokenB`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Callers**: `ccUpdate`, `transactToken`, `transactNative`, `_updateRegistry`, `globalizeUpdate`.
- **Parameters/Interactions**: Supports error messages.

#### _processBuyOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `uint2str`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`, `_historicalData.xVolume`.

#### _processSellOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `uint2str`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`, `_historicalData.yVolume`.

#### _processHistoricalUpdate(uint8 structId, uint256 value) returns (bool historicalUpdated)
- **Purpose**: Creates `HistoricalData` entry.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Uses `value` as `price`, `balanceA` - `balanceB`, and timestamp.

#### _clearRouters()
- **Purpose**: Clears `_routers` mapping using `ICCAgent.getRouters`.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: `ICCAgent.getRouters`.
- **Parameters/Interactions**: Resets `_routers`, `_routersSet`.

#### _fetchAgentRouters() returns (address[] memory newRouters)
- **Purpose**: Fetches routers from `ICCAgent.getRouters`.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: `ICCAgent.getRouters`.
- **Parameters/Interactions**: Returns router array or empty array.

#### _setNewRouters(address[] memory newRouters)
- **Purpose**: Updates `_routers` mapping with new routers.
- **Callers**: `resetRouters`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `_routers` entries to true, updates `_routersSet`.

## View Functions
#### getTokens()
* **Purpose**: Returns the addresses of the two tokens in the trading pair, `tokenA` and `tokenB`.
* **State Changes**: None.
* **Restrictions**: Reverts if the tokens have not been set.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: None.

#### getNextOrderId()
* **Purpose**: Returns the next available order ID. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: None.

#### routerAddressesView()
* **Purpose**: Returns the addresses of the authorized routers. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: None.

#### prices(uint256 _listingId)
* **Purpose**: Computes and returns the current price based on the contract's normalized token balances. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: `normalize`. 
* **Parameters/Interactions**: It normalizes the balances of `tokenA` and `tokenB` to 1e18 precision using `normalize` and then calculates the price as `$$(balanceB * 1e18) / balanceA$$` or returns `1` if either balance is zero. [cite: 377, 378, 379]

#### floorToMidnightView(uint256 inputTimestamp)
* **Purpose**: Rounds a given timestamp down to the start of its day in UTC (midnight). 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Takes `inputTimestamp` and returns the midnight timestamp by dividing by `86400` (the number of seconds in a day) and then multiplying by `86400`. [cite: 380]

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp)
* **Purpose**: Checks if two timestamps fall within the same calendar day (UTC). 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Compares the integer division of both timestamps by `86400`. 

#### getDayStartIndex(uint256 midnightTimestamp)
* **Purpose**: Returns the index in the `_historicalData` array for a given midnight timestamp. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `_dayStartIndices` mapping with the `midnightTimestamp`. 

#### volumeBalances(uint256 _listingId)
* **Purpose**: Returns the normalized, real-time token balances (`xBalance` and `yBalance`) of the contract. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: `normalize`. 
* **Parameters/Interactions**: Calls `IERC20.balanceOf` for `tokenA` and `tokenB` and then normalizes the amounts. 

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations)
* **Purpose**: Returns a list of pending buy order IDs for a specific maker. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `makerPendingOrders` mapping, filters for pending buy orders (`status == 1`), and returns up to `maxIterations` results starting from `step`. 

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations)
* **Purpose**: Returns a list of pending sell order IDs for a specific maker. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `makerPendingOrders` mapping, filters for pending sell orders (`status == 1`), and returns up to `maxIterations` results starting from `step`. 

#### getBuyOrderCore(uint256 orderId)
* **Purpose**: Returns the core details of a specific buy order. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `buyOrderCore` mapping with `orderId` to get the `makerAddress`, `recipientAddress`, and `status`. 

#### getBuyOrderPricing(uint256 orderId)
* **Purpose**: Returns the pricing details of a specific buy order. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `buyOrderPricing` mapping with `orderId` to get the `maxPrice` and `minPrice`. 

#### getBuyOrderAmounts(uint256 orderId)
* **Purpose**: Returns the amounts related to a specific buy order.
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `buyOrderAmounts` mapping with `orderId` to get the `pending` amount, `filled` amount, and `amountSent`. 

#### getSellOrderCore(uint256 orderId)
* **Purpose**: Returns the core details of a specific sell order. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `sellOrderCore` mapping with `orderId` to get the `makerAddress`, `recipientAddress`, and `status`. 

#### getSellOrderPricing(uint256 orderId)
* **Purpose**: Returns the pricing details of a specific sell order. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `sellOrderPricing` mapping with `orderId` to get the `maxPrice` and `minPrice`. 

#### getSellOrderAmounts(uint256 orderId)
* **Purpose**: Returns the amounts related to a specific sell order. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `sellOrderAmounts` mapping with `orderId` to get the `pending` amount, `filled` amount, and `amountSent`. 

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations)
* **Purpose**: Returns a list of order IDs for a specific maker.
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Retrieves all orders for the `maker` from `makerPendingOrders` and returns up to `maxIterations` IDs starting from `step`. 

#### makerPendingOrdersView(address maker)
* **Purpose**: Returns all pending order IDs for a specific maker. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Directly returns the array of order IDs from the `makerPendingOrders` mapping. 

#### getHistoricalDataView(uint256 index)
* **Purpose**: Returns a `HistoricalData` struct from the `_historicalData` array at a given index. [cite: 403]
* **State Changes**: None.
* **Restrictions**: Reverts if the index is out of bounds. 
* **Internal Call Tree**: None.
* **Parameters/Interactions**: Queries the `_historicalData` array at the specified `index`.

#### historicalDataLengthView()
* **Purpose**: Returns the number of entries in the `_historicalData` array. 
* **State Changes**: None.
* **Restrictions**: None.
* **Internal Call Tree**: None.
* **Parameters/Interactions**: None.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `updateType=0` updates `_balance`. Buy (`updateType=1`): inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`). Sell (`updateType=2`): inputs `tokenA` (`amounts.filled`), outputs `tokenB` (`amounts.amountSent`). Buy adds to `yVolume`, sell to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Computed via listing balances, `IERC20.balanceOf` in `prices`.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate`, `transactToken`, `transactNative` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`updateType=3`) or auto-generated, using `prices`.
- **External Calls**: `IERC20.balanceOf` (`prices`, `volumeBalances`, `transactToken`), `IERC20.transfer` (`transactToken`), `IERC20.decimals` (`setTokens`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`), `ICCAgent.getLister` (`resetRouters`), `ICCAgent.getRouters` (`resetRouters`, `_clearRouters`, `_fetchAgentRouters`), low-level `call` (`transactNative`).
- **Security**: Router checks, try-catch, explicit casting, relaxed validation, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.
- **Optimization**: Normalized amounts, `maxIterations` in view functions, auto-generated historical data, helper functions in `ccUpdate` and `resetRouters`.
