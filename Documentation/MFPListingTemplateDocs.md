# MFPListingTemplate Documentation

## Overview
The `MFPListingTemplate` contract (Solidity ^0.8.2) supports decentralized trading for a token pair, with price discovery via `IERC20.balanceOf`. It manages buy/sell orders and normalized (1e18 precision) balances. Volumes are tracked in `_historicalData` during order settlement/cancellation, with auto-generated historical data if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

**Version**: 0.3.11 (Updated 2025-09-16)

**Changes**:
- v0.3.11: Integrated `CCListingTemplate` v0.3.11 changes. Updated `_processHistoricalUpdate` to use full `HistoricalUpdate` struct, removing `structId` and `value` parameters. Added `_updateHistoricalData` and `_updateDayStartIndex` helper functions for modularity. Removed `uint2str` in error messages. Preserved MFP-specific price calculation in `prices` and `ccUpdate` balance updates using contract balances.
- v0.3.10: Updated `ccUpdate` to accept `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` arrays, removing `updateType`, `updateSort`, `updateData`. Modified `_processBuyOrderUpdate` and `_processSellOrderUpdate` for direct struct handling. Removed `uint2str` in error messages.
- v0.3.9: Replaced `UpdateType` with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` structs. Updated `_processBuyOrderUpdate`, `_processSellOrderUpdate`, and `_processHistoricalUpdate` for direct struct assignments. Ensured MFP price calculation in `prices`.
- v0.3.8: Added minimum price "1" in `prices`.
- v0.3.7: Derived "MFP" from "CC".

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
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **BuyOrderUpdate**: `structId` (0: Core, 1: Pricing, 2: Amounts), `orderId`, `makerAddress`, `recipientAddress`, `status`, `maxPrice`, `minPrice`, `pending`, `filled`, `amountSent`.
- **SellOrderUpdate**: Similar to `BuyOrderUpdate`.
- **BalanceUpdate**: `xBalance`, `yBalance` (normalized, 1e18).
- **HistoricalUpdate**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## State Variables
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`routerAddresses`**: `address[] private` - Router addresses.
- **`_routersSet`**: `bool private` - Locks router settings.
- **`tokenA`, `tokenB`**: `address public` - Token pair (ETH as `address(0)`).
- **`decimalsA`, `decimalsB`**: `uint8 public` - Token decimals.
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agentView`**: `address public` - Agent address.
- **`registryAddress`**: `address public` - Registry address.
- **`liquidityAddressView`**: `address public` - Liquidity contract.
- **`globalizerAddress`**: `address public` - Globalizer contract.
- **`_globalizerSet`**: `bool private` - Locks globalizer setting.
- **`nextOrderId`**: `uint256 private` - Order ID counter.
- **`dayStartFee`**: `DayStartFee public` - Daily fee tracking.
- **`_pendingBuyOrders`, `_pendingSellOrders`**: `uint256[] private` - Pending order IDs.
- **`makerPendingOrders`**: `mapping(address => uint256[]) private` - Maker order IDs.
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
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if `_routersSet` or `routers_` invalid/empty.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `routers` entries to true, populates `routerAddresses`.

#### resetRouters()
- **Purpose**: Fetches lister via `ICCAgent.getLister`, restricts to lister, clears `routers`, updates with `ICCAgent.getRouters`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if `msg.sender` not lister or no routers.
- **Internal Call Tree**: None (directly calls `ICCAgent.getLister`, `ICCAgent.getRouters`).
- **Parameters/Interactions**: Uses `agentView`, updates `routers`, `routerAddresses`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, initializes `_historicalData`, `dayStartFee` (callable once).
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
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

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView` (callable once).
- **State Changes**: `liquidityAddressView`.
- **Restrictions**: Reverts if `liquidityAddressView` set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `liquidityAddressView` for `ccUpdate` fee fetching.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens via `IERC20.transfer` with pre/post balance checks.
- **State Changes**: None directly (affects token balances).
- **Restrictions**: Router-only, valid token (`tokenA` or `tokenB`), non-zero `amount`, valid `recipient`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Uses `routers`, `tokenA`, `tokenB`, `IERC20.transfer`, `IERC20.balanceOf`. Emits `TransactionFailed` on failure.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH via low-level `call` with pre/post balance checks.
- **State Changes**: None directly (affects ETH balance).
- **Restrictions**: Router-only, one token must be `address(0)`, non-zero `amount`, valid `recipient`, `msg.value` matches `amount`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Uses `routers`, `tokenA`, `tokenB`, low-level `call`. Emits `TransactionFailed` on failure.

#### ccUpdate(BuyOrderUpdate[] calldata buyUpdates, SellOrderUpdate[] calldata sellUpdates, BalanceUpdate[] calldata balanceUpdates, HistoricalUpdate[] calldata historicalUpdates)
- **Purpose**: Updates buy/sell orders, balances, or historical data, callable by routers.
- **Parameters**:
  - `buyUpdates`: Array of `BuyOrderUpdate` structs for buy orders.
  - `sellUpdates`: Array of `SellOrderUpdate` structs for sell orders.
  - `balanceUpdates`: Array of `BalanceUpdate` structs for balances.
  - `historicalUpdates`: Array of `HistoricalUpdate` structs for historical data.
- **Logic**:
  1. Verifies router caller via `routers`.
  2. Processes `buyUpdates` via `_processBuyOrderUpdate`:
     - `structId=0` (Core): Updates `buyOrderCore`, manages `_pendingBuyOrders`, `makerPendingOrders` via `removePendingOrder` if `status=0` or `3`, increments `nextOrderId` if `status=1`. Sets `orderStatus.hasCore`. Emits `OrderUpdated`.
     - `structId=1` (Pricing): Updates `buyOrderPricing`. Sets `orderStatus.hasPricing`.
     - `structId=2` (Amounts): Updates `buyOrderAmounts`, adds difference of old/new `filled` to `_historicalData.yVolume`, `amountSent` to `_historicalData.xVolume`. Sets `orderStatus.hasAmounts`.
     - Invalid `structId` emits `UpdateFailed`.
  3. Processes `sellUpdates` via `_processSellOrderUpdate` (similar, updates `sellOrder*`, `_pendingSellOrders`, `_historicalData.xVolume`, `_historicalData.yVolume`).
  4. Processes `balanceUpdates`: Pushes `HistoricalData` with current price (`(balanceB * 1e18) / balanceA` or 1), `xBalance`, `yBalance`. Emits `BalancesUpdated`.
  5. Processes `historicalUpdates` via `_processHistoricalUpdate`: Creates new `HistoricalData` entry with `price`, balances, timestamp using `_updateHistoricalData`, updates `_dayStartIndices` via `_updateDayStartIndex`. Emits `UpdateFailed` if `price=0`.
  6. Checks `orderStatus` for completeness, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  7. Updates `dayStartFee` if not same day, fetching fees via `ICCLiquidityTemplate.liquidityDetail`.
  8. Calls `globalizeUpdate`.
- **State Changes**: `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `nextOrderId`.
- **External Interactions**: `IERC20.balanceOf` (`ccUpdate`, `prices`, `_updateHistoricalData`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`).
- **Internal Call Tree**: `_processBuyOrderUpdate` (`removePendingOrder`, `_updateRegistry`), `_processSellOrderUpdate` (`removePendingOrder`, `_updateRegistry`), `_processHistoricalUpdate` (`_updateHistoricalData`, `_updateDayStartIndex`, `_floorToMidnight`), `_updateHistoricalData` (`normalize`, `_floorToMidnight`), `_updateDayStartIndex` (`_floorToMidnight`), `_updateRegistry` (`ITokenRegistry.initializeTokens`), `globalizeUpdate` (`ICCGlobalizer.globalizeOrders`), `_floorToMidnight`, `_isSameDay`, `removePendingOrder`, `normalize`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`, `BalancesUpdated`, `OrderUpdated`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate`, `prices`, `volumeBalances`, `_updateHistoricalData`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: `transactToken`, `transactNative`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **Parameters/Interactions**: Used for `dayStartFee`, `_dayStartIndices`.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate`, `_updateHistoricalData`, `_updateDayStartIndex`.
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (intended for analytics).
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `ITokenRegistry.initializeTokens` with `tokenA`, `tokenB`. Emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `ICCGlobalizer.globalizeOrders` with `maker`, `tokenA` or `tokenB`. Emits `GlobalUpdateFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes order ID from array.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **Parameters/Interactions**: Modifies `_pendingBuyOrders` or `_pendingSellOrders`.

#### _processBuyOrderUpdate(BuyOrderUpdate memory update)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`, `_historicalData.xVolume`, `orderStatus`, `nextOrderId`. Emits `OrderUpdated`, `UpdateFailed`.

#### _processSellOrderUpdate(SellOrderUpdate memory update)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `removePendingOrder`, `_updateRegistry`.
- **Parameters/Interactions**: Updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`, `_historicalData.yVolume`, `orderStatus`, `nextOrderId`. Emits `OrderUpdated`, `UpdateFailed`.

#### _processHistoricalUpdate(HistoricalUpdate memory update) returns (bool historicalUpdated)
- **Purpose**: Creates new `HistoricalData` entry with full `HistoricalUpdate` struct.
- **Callers**: `ccUpdate`.
- **Internal Call Tree**: `_updateHistoricalData`, `_updateDayStartIndex`, `_floorToMidnight`.
- **Parameters/Interactions**: Uses `price`, balances, timestamp. Updates `_historicalData`, `_dayStartIndices`. Emits `UpdateFailed` if `price=0`.

#### _updateHistoricalData(HistoricalUpdate memory update)
- **Purpose**: Pushes new `HistoricalData` entry with `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **Callers**: `_processHistoricalUpdate`.
- **Internal Call Tree**: `normalize`, `_floorToMidnight`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `IERC20.balanceOf`. Defaults to contract balances if `xBalance` or `yBalance` is zero.

#### _updateDayStartIndex(uint256 timestamp)
- **Purpose**: Updates `_dayStartIndices` for midnight timestamp.
- **Callers**: `_processHistoricalUpdate`.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Updates `_dayStartIndices` with `_historicalData.length - 1` if unset.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Callers**: `_updateRegistry`, `globalizeUpdate`, `transactToken`, `transactNative`.
- **Parameters/Interactions**: Supports error messages.

### View Functions
#### getTokens() returns (address tokenA_, address tokenB_)
- **Purpose**: Returns `tokenA`, `tokenB`.
- **Restrictions**: Reverts if tokens not set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### getNextOrderId() returns (uint256 orderId_)
- **Purpose**: Returns `nextOrderId`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### routerAddressesView() returns (address[] memory addresses)
- **Purpose**: Returns `routerAddresses`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### prices(uint256 _listingId) returns (uint256 price)
- **Purpose**: Computes price as `(balanceB * 1e18) / balanceA` or 1 if either balance is zero.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `IERC20.balanceOf`, `decimalsA`, `decimalsB`.

#### floorToMidnightView(uint256 inputTimestamp) returns (uint256 midnight)
- **Purpose**: Rounds `inputTimestamp` to midnight UTC.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### getDayStartIndex(uint256 midnightTimestamp) returns (uint256 index)
- **Purpose**: Returns `_dayStartIndices[midnightTimestamp]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_dayStartIndices`.

#### volumeBalances(uint256 _listingId) returns (uint256 xBalance, uint256 yBalance)
- **Purpose**: Returns normalized `tokenA`, `tokenB` balances.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Uses `tokenA`, `tokenB`, `IERC20.balanceOf`, `decimalsA`, `decimalsB`.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending buy order IDs for `maker`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, `buyOrderCore`.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns pending sell order IDs for `maker`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, `sellOrderCore`.

#### getBuyOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns `buyOrderCore[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderCore`.

#### getBuyOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns `buyOrderPricing[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderPricing`.

#### getBuyOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns `buyOrderAmounts[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderAmounts`.

#### getSellOrderCore(uint256 orderId) returns (address makerAddress, address recipientAddress, uint8 status)
- **Purpose**: Returns `sellOrderCore[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderCore`.

#### getSellOrderPricing(uint256 orderId) returns (uint256 maxPrice, uint256 minPrice)
- **Purpose**: Returns `sellOrderPricing[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderPricing`.

#### getSellOrderAmounts(uint256 orderId) returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Purpose**: Returns `sellOrderAmounts[orderId]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderAmounts`.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations) returns (uint256[] memory orderIds)
- **Purpose**: Returns `makerPendingOrders[maker]` subset.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`.

#### makerPendingOrdersView(address maker) returns (uint256[] memory orderIds)
- **Purpose**: Returns all `makerPendingOrders[maker]`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`.

#### getHistoricalDataView(uint256 index) returns (HistoricalData memory data)
- **Purpose**: Returns `_historicalData[index]`.
- **Restrictions**: Reverts if `index` out of bounds.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_historicalData`.

#### historicalDataLengthView() returns (uint256 length)
- **Purpose**: Returns `_historicalData.length`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `buyUpdates`/`sellUpdates` updates orders. Buy: inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`). Sell: inputs `tokenA` (`amounts.filled`), outputs `tokenB` (`amounts.amountSent`). Buy adds to `yVolume`, sell to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Computed via `IERC20.balanceOf` in `prices`, returns `(balanceB * 1e18) / balanceA` or 1.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`historicalUpdates`) or auto-generated in `balanceUpdates`, using `prices`. Each `historicalUpdates` entry creates a new `HistoricalData` record.
- **External Calls**: `IERC20.balanceOf` (`prices`, `volumeBalances`, `transactToken`, `ccUpdate`, `_updateHistoricalData`), `IERC20.transfer` (`transactToken`), `IERC20.decimals` (`setTokens`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`), `ICCAgent.getLister` (`resetRouters`), `ICCAgent.getRouters` (`resetRouters`), low-level `call` (`transactNative`).
- **Security**: Router checks, try-catch, explicit casting, relaxed validation, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`, `OrderUpdated`, `BalancesUpdated`, `OrderUpdatesComplete`, `OrderUpdateIncomplete`.
- **Optimization**: Normalized amounts, `maxIterations` in view functions, auto-generated historical data, direct struct assignments in `ccUpdate`, modular `_processHistoricalUpdate` with helper functions.
