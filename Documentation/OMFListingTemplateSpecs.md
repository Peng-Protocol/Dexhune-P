# OMFListingTemplate Documentation

## Overview
The `OMFListingTemplate` contract (Solidity ^0.8.2) extends `MFPListingTemplate` to support decentralized trading for a token pair, with price discovery via external oracles (e.g., Chainlink) for tokenA and a base token, instead of `IERC20.balanceOf`. It manages buy and sell orders, normalized (1e18 precision) balances, and tracks volumes in `_historicalData` during order settlement or cancellation. Auto-generated historical data is used if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch for external calls.

**Version**: 0.3.10 (Updated 2025-09-07)

**Changes**:
- v0.3.10: Added base token oracle parameters (`baseOracleAddress`, `baseOracleFunction`, `baseOracleBitSize`, `baseOracleIsSigned`, `baseOracleDecimals`, `_baseOracleSet`) and `setBaseOracleParams`; updated `prices` to compute `baseTokenPrice / tokenAPrice`, normalized to 18 decimals.
- v0.3.9: Added `oracleAddress`, `oracleFunction`, `oracleBitSize`, `oracleIsSigned`, `oracleDecimals`, and `setOracleParams`; updated `prices` to fetch and normalize oracle data to 18 decimals.
- v0.3.8: Added minimum price "1" in `prices`.
- v0.3.7: Derived "MFP" from "CC", removed Uniswap functionality.

**Compatibility**:
- CCLiquidityTemplate.sol (v0.1.9)

## Interfaces
- **IERC20**: Defines `decimals()`, `transfer(address, uint256)`, `balanceOf(address)`.
- **ICCLiquidityTemplate**: Defines `liquidityDetail()`.
- **ITokenRegistry**: Defines `initializeTokens(address, address[])`.
- **ICCGlobalizer**: Defines `globalizeOrders(address, address)`.
- **ICCAgent**: Defines `getLister(address)`, `getRouters()`.
- **IOracle**: Defines `latestAnswer()` for price feeds (e.g., Chainlink).

## Structs
- **DayStartFee**: `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **UpdateType**: `updateType` (0: balance, 1: buy, 2: sell, 3: historical), `structId` (0: Core, 1: Pricing, 2: Amounts), `index`, `value`, `addr`, `recipient`, `maxPrice`, `minPrice`, `amountSent`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## State Variables
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`routerAddresses`**: `address[] private` - List of router addresses.
- **`_routersSet`**: `bool private` - Locks router settings.
- **`tokenA`, `tokenB`**: `address public` - Token pair (ETH as `address(0)`).
- **`decimalsA`, `decimalsB`**: `uint8 public` - Token decimals.
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agentView`**: `address public` - Agent address.
- **`registryAddress`**: `address public` - Registry address.
- **`liquidityAddressView`**: `address public` - Liquidity contract.
- **`globalizerAddress`, `_globalizerSet`**: `address public`, `bool private` - Globalizer contract.
- **`nextOrderId`**: `uint256 private` - Order ID counter.
- **`oracleAddress`**: `address public` - Oracle contract address.
- **`oracleFunction`**: `bytes4 public` - Oracle function selector (e.g., `0x50d25bcd` for `latestAnswer`).
- **`oracleBitSize`**: `uint16 public` - Bit size of oracle return type (e.g., 256 for `int256`/`uint256`).
- **`oracleIsSigned`**: `bool public` - True for signed (`int`), false for unsigned (`uint`).
- **`oracleDecimals`**: `uint8 public` - Oracle decimals (e.g., 8 for Chainlink).
- **`_oracleSet`**: `bool private` - Locks oracle settings.
- **`dayStartFee`**: `DayStartFee public` - Daily fee tracking.
- **`_pendingBuyOrders`, `_pendingSellOrders`**: `uint256[] private` - Pending order IDs.
- **`makerPendingOrders`**: `mapping(address => uint256[]) private` - Maker order IDs.
- **`_historicalData`**: `HistoricalData[] private` - Price/volume history.
- **`_dayStartIndices`**: `mapping(uint256 => uint256) private` - Midnight timestamps to indices.
- **`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`**: `mapping(uint256 => ...)` - Buy order data.
- **`sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`**: `mapping(uint256 => ...)` - Sell order data.
- **`orderStatus`**: `mapping(uint256 => OrderStatus) private` - Order completeness.
- **`baseOracleAddress`**: `address public` - Base token oracle contract address.
- **`baseOracleFunction`**: `bytes4 public` - Base token oracle function selector (e.g., `0x50d25bcd` for `latestAnswer`).
- **`baseOracleBitSize`**: `uint16 public` - Bit size of base token oracle return type (e.g., 256 for `int256`/`uint appointee256`).
- **`baseOracleIsSigned`**: `bool public` - True for signed (`int`), false for unsigned (`uint`) base token oracle.
- **`baseOracleDecimals`**: `uint8 public` - Base token oracle decimals (e.g., 8 for Chainlink).
- **`_baseOracleSet`**: `bool private` - Locks base oracle settings.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets `globalizerAddress` for `globalizeUpdate` calls (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Restrictions**: Reverts if already set or `globalizerAddress_` is zero.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `globalizerAddress_` for `ICCGlobalizer.globalizeOrders` in `globalizeUpdate`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers for `ccUpdate`, `transactToken`, `transactNative`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if `_routersSet` or `routers_` invalid/empty.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `routers` entries to true, populates `routerAddresses`.

#### resetRouters()
- **Purpose**: Clears `routers`, updates with `ICCAgent.getRouters`, restricted to lister via `ICCAgent.getLister`.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if caller not lister or no routers.
- **Internal Call Tree**: None (direct external calls to `ICCAgent.getLister`, `ICCAgent.getRouters`).
- **Parameters/Interactions**: Uses `agentView`, updates `routers` and `routerAddresses`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, initializes `_historicalData`, `dayStartFee` (callable once).
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Calls `IERC20.decimals` for `tokenA_`, `tokenB_`.

#### setAgent(address agent_)
- **Purpose**: Sets `agentView` for `resetRouters` (callable once).
- **State Changes**: `agentView`.
- **Restrictions**: Reverts if `agentView` set or `agent_` invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `agentView`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `listingId` for event emissions (callable once).
- **State Changes**: `listingId`.
- **Restrictions**: Reverts if `listingId` set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `listingId`.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` for `_updateRegistry` (callable once).
- **State Changes**: `registryAddress`.
- **Restrictions**: Reverts if `registryAddress` set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `registryAddress`.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView` for fee fetching in `ccUpdate` (callable once).
- **State Changes**: `liquidityAddressView`.
- **Restrictions**: Reverts if `liquidityAddressView` set or `_liquidityAddress` invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets `liquidityAddressView` for `ICCLiquidityTemplate.liquidityDetail`.

#### setOracleParams(address _oracleAddress, bytes4 _oracleFunction, uint16 _oracleBitSize, bool _oracleIsSigned, uint8 _oracleDecimals)
- **Purpose**: Sets oracle parameters for price fetching in `prices` (callable once).
- **State Changes**: `oracleAddress`, `oracleFunction`, `oracleBitSize`, `oracleIsSigned`, `oracleDecimals`, `_oracleSet`.
- **Restrictions**: Reverts if `_oracleSet`, `_oracleAddress` is zero, `_oracleFunction` is zero, `_oracleBitSize` is zero or >256, or `_oracleDecimals` >18.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets oracle parameters, emits `OracleParamsSet`.

#### setBaseOracleParams(address _baseOracleAddress, bytes4 _baseOracleFunction, uint16 _baseOracleBitSize, bool _baseOracleIsSigned, uint8 _baseOracleDecimals)
- **Purpose**: Sets base token oracle parameters for price fetching in `prices` (callable once).
- **State Changes**: `baseOracleAddress`, `baseOracleFunction`, `baseOracleBitSize`, `baseOracleIsSigned`, `baseOracleDecimals`, `_baseOracleSet`.
- **Restrictions**: Reverts if `_baseOracleSet`, `_baseOracleAddress` is zero, `_baseOracleFunction` is zero, `_baseOracleBitSize` is zero or >256, or `_baseOracleDecimals` >18.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Sets base oracle parameters, emits `OracleParamsSet`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens via `IERC20.transfer`, checks pre/post balances.
- **State Changes**: None directly (token balances change externally).
- **Restrictions**: Router-only, `token` must be `tokenA` or `tokenB`, `recipient` non-zero, `amount` non-zero.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `IERC20.balanceOf`, `IERC20.transfer`, emits `TransactionFailed` if transfer fails or no tokens received.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH via low-level `call`, checks pre/post balances.
- **State Changes**: None directly (ETH balances change externally).
- **Restrictions**: Router-only, one token must be `address(0)`, `recipient` non-zero, `amount` non-zero, `msg.value` must equal `amount`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Uses low-level `call`, emits `TransactionFailed` if transfer fails or no ETH received.

#### ccUpdate(uint8[] calldata updateType, uint8[] calldata updateSort, uint256[] calldata updateData)
- **Purpose**: Updates orders or historical data, callable by routers.
- **Parameters**:
  - `updateType`: Array of update types (0: balance, 1: buy order, 2: sell order, 3: historical).
  - `updateSort`: Array specifying struct to update (0: Core, 1: Pricing, 2: Amounts).
  - `updateData`: Array of encoded data for updates.
- **Logic**:
  1. Verifies router caller and array length consistency.
  2. Computes current midnight timestamp (`(block.timestamp / 86400) * 86400`).
  3. Initializes `updatedOrders`, `updatedCount`.
  4. Processes updates:
     - **Balance (`updateType=0`)**: Skipped (handled by `volumeBalances`).
     - **Buy Order (`updateType=1`)**: Calls `_processBuyOrderUpdate`:
       - `structId=0` (Core): Decodes `updateData[i]` as `(address, address, uint8)`, updates `buyOrderCore`, manages `_pendingBuyOrders`, `makerPendingOrders` via `removePendingOrder` if `status=0` or `3`. Sets `orderStatus.hasCore`. Emits `OrderUpdated`.
       - `structId=1` (Pricing): Decodes `updateData[i]` as `(uint256, uint256)`, updates `buyOrderPricing`. Sets `orderStatus.hasPricing`.
       - `structId=2` (Amounts): Decodes `updateData[i]` as `(uint256, uint256, uint256)`, updates `buyOrderAmounts`, adds `filled` difference to `_historicalData.yVolume`, `amountSent` to `_historicalData.xVolume`. Sets `orderStatus.hasAmounts`.
       - Invalid `structId` emits `UpdateFailed`.
     - **Sell Order (`updateType=2`)**: Similar, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`, adds `filled` difference to `_historicalData.xVolume`, `amountSent` to `_historicalData.yVolume`.
     - **Historical (`updateType=3`)**: Calls `_processHistoricalUpdate` to create `HistoricalData` with `price=updateData[i]`, current balances, timestamp, updates `_dayStartIndices`.
  5. Updates `dayStartFee` if not same day, fetching fees via `ICCLiquidityTemplate.liquidityDetail`.
  6. Checks `orderStatus` for completeness, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  7. Calls `globalizeUpdate`.
- **State Changes**: `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **External Interactions**: `IERC20.balanceOf` (`_processHistoricalUpdate`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`).
- **Internal Call Tree**: `_processBuyOrderUpdate` (calls `removePendingOrder`, `uint2str`, `_updateRegistry`), `_processSellOrderUpdate` (calls `removePendingOrder`, `uint2str`, `_updateRegistry`), `_processHistoricalUpdate` (calls `_floorToMidnight`, `normalize`), `globalizeUpdate` (calls `uint2str`), `_updateRegistry` (calls `uint2str`), `_floorToMidnight`, `_isSameDay`, `removePendingOrder`, `uint2str`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate` (`_processHistoricalUpdate`), `prices`, `volumeBalances`.
- **External Callers**: `prices`, `volumeBalances`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`, `oracleDecimals`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: None (unused in current version).
- **External Callers**: None.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **External Callers**: None (exposed via `isSameDayView`).
- **Parameters/Interactions**: Used for `dayStartFee` updates.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate` (`_processHistoricalUpdate`).
- **External Callers**: None (exposed via `floorToMidnightView`).
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None (intended for analytics).
- **External Callers**: None.
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `ccUpdate` (`_processBuyOrderUpdate`, `_processSellOrderUpdate`).
- **External Callers**: None.
- **Parameters/Interactions**: Calls `ITokenRegistry.initializeTokens` with `tokenA`, `tokenB`, emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Calls `ICCGlobalizer.globalizeOrders` with `maker`, `tokenA` or `tokenB`, emits `GlobalUpdateFailed`, `ExternalCallFailed`.

#### uint2str(uint256 _i) returns (string str)
- **Purpose**: Converts uint to string for error messages.
- **Callers**: `ccUpdate` (`_processBuyOrderUpdate`, `_processSellOrderUpdate`), `globalizeUpdate`, `_updateRegistry`.
- **External Callers**: None.
- **Parameters/Interactions**: Supports error messages.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes order ID from array.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Modifies `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`.

#### _processBuyOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`, `_historicalData.xVolume`, calls `removePendingOrder`, `uint2str`, `_updateRegistry`.

#### _processSellOrderUpdate(uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount) returns (uint256)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`, `_historicalData.yVolume`, calls `removePendingOrder`, `uint2str`, `_updateRegistry`.

#### _processHistoricalUpdate(uint8 structId, uint256 value) returns (bool historicalUpdated)
- **Purpose**: Creates `HistoricalData` entry with balances and price.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Uses `value` as `price`, calls `_floorToMidnight`, `normalize`, `IERC20.balanceOf`.

### View Functions
#### getTokens()
- **Purpose**: Returns `tokenA` and `tokenB`.
- **State Changes**: None.
- **Restrictions**: Reverts if tokens not set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### getNextOrderId()
- **Purpose**: Returns `nextOrderId`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### routerAddressesView()
- **Purpose**: Returns `routerAddresses`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### prices(uint256 _listingId)
- **Purpose**: Fetches tokenA and base token prices from oracles, computes `baseTokenPrice / tokenAPrice`, normalizes to 1e18 precision.
- **State Changes**: None.
- **Restrictions**: Reverts if `oracleAddress` or `baseOracleAddress` not set, oracle calls fail, prices are non-positive, or `tokenAPrice` is zero.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Calls `oracleAddress` and `baseOracleAddress` with respective `oracleFunction` and `baseOracleFunction`, decodes responses as `int256` (if `oracleIsSigned` or `baseOracleIsSigned`) or `uint256`, normalizes using `oracleDecimals` and `baseOracleDecimals`, computes `baseTokenPrice / tokenAPrice`.

#### floorToMidnightView(uint256 inputTimestamp)
- **Purpose**: Rounds timestamp to midnight UTC.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp)
- **Purpose**: Checks if timestamps are in the same day.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### getDayStartIndex(uint256 midnightTimestamp)
- **Purpose**: Returns `_historicalData` index for midnight timestamp.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_dayStartIndices`.

#### volumeBalances(uint256 _listingId)
- **Purpose**: Returns normalized `xBalance`, `yBalance`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Calls `IERC20.balanceOf` for `tokenA`, `tokenB`.

#### pendingBuyOrdersView()
- **Purpose**: Returns `_pendingBuyOrders`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### pendingSellOrdersView()
- **Purpose**: Returns `_pendingSellOrders`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

#### makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations)
- **Purpose**: Returns pending buy order IDs for `maker`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, `buyOrderCore`, uses `maxIterations`, `step`.

#### makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations)
- **Purpose**: Returns pending sell order IDs for `maker`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, `sellOrderCore`, uses `maxIterations`, `step`.

#### getBuyOrderCore(uint256 orderId)
- **Purpose**: Returns `buyOrderCore` details.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderCore`.

#### getBuyOrderPricing(uint256 orderId)
- **Purpose**: Returns `buyOrderPricing` details.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderPricing`.

#### getBuyOrderAmounts(uint256 orderId)
- **Purpose**: Returns `buyOrderAmounts` details.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `buyOrderAmounts`.

#### getSellOrderCore(uint256 orderId)
- **Purpose**: Returns `sellOrderCore` details.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderCore`.

#### getSellOrderPricing(uint256 orderId)
- **Purpose**: Returns `sellOrderPricing` details.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderPricing`.

#### getSellOrderAmounts(uint256 orderId)
- **Purpose**: Returns `sellOrderAmounts` details.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `sellOrderAmounts`.

#### makerOrdersView(address maker, uint256 step, uint256 maxIterations)
- **Purpose**: Returns order IDs for `maker`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`, uses `maxIterations`, `step`.

#### makerPendingOrdersView(address maker)
- **Purpose**: Returns all pending order IDs for `maker`.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `makerPendingOrders`.

#### getHistoricalDataView(uint256 index)
- **Purpose**: Returns `HistoricalData` at `index`.
- **State Changes**: None.
- **Restrictions**: Reverts if `index` out of bounds.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Queries `_historicalData`.

#### historicalDataLengthView()
- **Purpose**: Returns `_historicalData` length.
- **State Changes**: None.
- **Restrictions**: None.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: None.

## Parameters and Interactions
- **Orders**: `ccUpdate` with `updateType=1` (buy) inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`), adds to `yVolume`. `updateType=2` (sell) inputs `tokenA`, outputs `tokenB`, adds to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Fetched via oracle (`oracleAddress`, `oracleFunction`), decoded as `int256` (if `oracleIsSigned`) or `uint256`, normalized to 1e18 using `oracleDecimals`.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate` with `maker`, `tokenA` or `tokenB`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`, stored in `dayStartFee`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`updateType=3`) or auto-generated, using oracle price.
- **External Calls**: `IERC20.balanceOf` (`volumeBalances`, `_processHistoricalUpdate`), `IERC20.transfer` (`transactToken`), `IERC20.decimals` (`setTokens`), `ICCLiquidityTemplate.liquidityDetail` (`ccUpdate`), `ITokenRegistry.initializeTokens` (`_updateRegistry`), `ICCGlobalizer.globalizeOrders` (`globalizeUpdate`), `ICCAgent.getLister` (`resetRouters`), `ICCAgent.getRouters` (`resetRouters`), `IOracle` call (`prices`), low-level `call` (`transactNative`).
- **Security**: Router checks, try-catch, explicit casting, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`, `OracleParamsSet`.
- **Optimization**: Normalized amounts, `maxIterations` in view functions, auto-generated historical data, helper functions in `ccUpdate`.
- **Buy Conversions**: To get tokenA from tokenB, use `tokenBAmount * (baseTokenPrice / tokenAPrice)`, which simplifies to `tokenBAmount * price` if tokenB is the base token, matching the original formula.
- **Sell Conversions**: To get tokenB from tokenA, use `tokenAAmount / (baseTokenPrice / tokenAPrice)`, which simplifies to `tokenAAmount / price`, matching the original formula.
