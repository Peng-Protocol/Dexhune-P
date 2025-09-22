# OMFListingTemplate Documentation

## Overview
The `OMFListingTemplate` contract (Solidity ^0.8.2) extends `MFPListingTemplate` for decentralized trading of a token pair, using external oracles (e.g., Chainlink) for price discovery of tokenA and a base token, replacing `IERC20.balanceOf` for pricing. It manages buy/sell orders, normalized balances (1e18 precision), and tracks volumes in `_historicalData` during order settlement/cancellation. Auto-generated historical data is used if not provided by routers. Licensed under BSL 1.1 - Peng Protocol 2025, it uses explicit casting, avoids inline assembly, and ensures graceful degradation with try-catch.

**Version**: 0.3.13 (Updated 2025-09-22)

**Changes**:
- v0.3.13: Patched `prices` function to compute `tokenAUSDPrice / baseTokenUSDPrice` for XAU/USD base token compatibility with `MFPSettlementRouter` and `MFPLiquidRouter`.
- v0.3.12: Patched `_processHistoricalUpdate` to use `HistoricalUpdate` struct directly, removing `uint2str` usage. Updated `_updateHistoricalData` and `_updateDayStartIndex` to align with `CCListingTemplate`’s struct-based approach, ensuring new `HistoricalData` entries per update while preserving OMF’s oracle-based pricing.
- v0.3.11: Replaced `UpdateType` with `BuyOrderUpdate`, `SellOrderUpdate`, `BalanceUpdate`, `HistoricalUpdate` structs. Updated `ccUpdate` to accept new struct arrays, removing `updateType`, `updateSort`, `updateData`. Modified `_processBuyOrderUpdate` and `_processSellOrderUpdate` to use structs directly, eliminating encoding/decoding. Updated `_processHistoricalUpdate` with helpers `_updateHistoricalData`, `_updateDayStartIndex`. Incremented `nextOrderId` in `_processBuyOrderUpdate`, `_processSellOrderUpdate` for new orders.
- v0.3.10: Added base token oracle parameters and `setBaseOracleParams`; updated `prices` to compute `baseTokenPrice / tokenAPrice`.
- v0.3.9: Added oracle parameters and `setOracleParams`; updated `prices` to use oracle data.
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
- **IOracle**: Defines `latestAnswer()` for price feeds.

## Structs
- **DayStartFee**: `dayStartXFeesAcc`, `dayStartYFeesAcc`, `timestamp`.
- **HistoricalData**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **BuyOrderCore**: `makerAddress`, `recipientAddress`, `status` (0: cancelled, 1: pending, 2: partially filled, 3: filled).
- **BuyOrderPricing**: `maxPrice`, `minPrice` (1e18).
- **BuyOrderAmounts**: `pending` (tokenB), `filled` (tokenB), `amountSent` (tokenA).
- **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**: Similar, with `pending` (tokenA), `amountSent` (tokenB).
- **BuyOrderUpdate**: `structId` (0: Core, 1: Pricing, 2: Amounts), `orderId`, `makerAddress`, `recipientAddress`, `status`, `maxPrice`, `minPrice`, `pending`, `filled`, `amountSent`.
- **SellOrderUpdate**: Same fields as `BuyOrderUpdate` for sell orders.
- **BalanceUpdate**: `xBalance`, `yBalance` (normalized).
- **HistoricalUpdate**: `price`, `xBalance`, `yBalance`, `xVolume`, `yVolume`, `timestamp`.
- **OrderStatus**: `hasCore`, `hasPricing`, `hasAmounts`.

## State Variables
- **`routers`**: `mapping(address => bool) public` - Authorized routers.
- **`routerAddresses`**: `address[] private` - Router address list.
- **`_routersSet`**: `bool private` - Locks router settings.
- **`tokenA`, `tokenB`**: `address public` - Token pair (ETH as `address(0)`).
- **`decimalsA`, `decimalsB`**: `uint8 public` - Token decimals.
- **`listingId`**: `uint256 public` - Listing identifier.
- **`agentView`**: `address public` - Agent address.
- **`registryAddress`**: `address public` - Registry address.
- **`liquidityAddressView`**: `address public` - Liquidity contract.
- **`globalizerAddress`, `_globalizerSet`**: `address public`, `bool private` - Globalizer contract.
- **`nextOrderId`**: `uint256 private` - Order ID counter.
- **`oracleAddress`, `oracleFunction`, `oracleBitSize`, `oracleIsSigned`, `oracleDecimals`, `_oracleSet`**: Oracle settings for tokenA price.
- **`baseOracleAddress`, `baseOracleFunction`, `baseOracleBitSize`, `baseOracleIsSigned`, `baseOracleDecimals`, `_baseOracleSet`**: Base token oracle settings.
- **`dayStartFee`**: `DayStartFee public` - Daily fee tracking.
- **`_pendingBuyOrders`, `_pendingSellOrders`**: `uint256[] private` - Pending order IDs.
- **`makerPendingOrders`**: `mapping(address => uint256[]) private` - Maker order IDs.
- **`_historicalData`**: `HistoricalData[] private` - Price/volume history.
- **`_dayStartIndices`**: `mapping(uint256 => uint256) private` - Midnight timestamps to indices.
- **`buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`**: Order data mappings.
- **`orderStatus`**: `mapping(uint256 => OrderStatus) private` - Order completeness.

## Functions
### External Functions
#### setGlobalizerAddress(address globalizerAddress_)
- **Purpose**: Sets `globalizerAddress` (callable once).
- **State Changes**: `globalizerAddress`, `_globalizerSet`.
- **Restrictions**: Reverts if set or `globalizerAddress_` is zero.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Used in `globalizeUpdate`.

#### setRouters(address[] memory routers_)
- **Purpose**: Authorizes routers (callable once).
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if set or `routers_` invalid/empty.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Populates `routers`, `routerAddresses`.

#### resetRouters()
- **Purpose**: Updates `routers` from `ICCAgent.getRouters`, lister-only.
- **State Changes**: `routers`, `routerAddresses`, `_routersSet`.
- **Restrictions**: Reverts if not lister or no routers.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `ICCAgent.getLister`, `ICCAgent.getRouters`.

#### setTokens(address tokenA_, address tokenB_)
- **Purpose**: Sets tokens, decimals, initializes `_historicalData`, `dayStartFee` (callable once).
- **State Changes**: `tokenA`, `tokenB`, `decimalsA`, `decimalsB`, `_historicalData`, `_dayStartIndices`, `dayStartFee`.
- **Restrictions**: Reverts if tokens set, identical, or both zero.
- **Internal Call Tree**: `_floorToMidnight`.
- **Parameters/Interactions**: Calls `IERC20.decimals`.

#### setAgent(address agent_)
- **Purpose**: Sets `agentView` (callable once).
- **State Changes**: `agentView`.
- **Restrictions**: Reverts if set or `agent_` invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Used in `resetRouters`.

#### setListingId(uint256 listingId_)
- **Purpose**: Sets `listingId` (callable once).
- **State Changes**: `listingId`.
- **Restrictions**: Reverts if set.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Used in events.

#### setRegistry(address registryAddress_)
- **Purpose**: Sets `registryAddress` (callable once).
- **State Changes**: `registryAddress`.
- **Restrictions**: Reverts if set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Used in `_updateRegistry`.

#### setLiquidityAddress(address _liquidityAddress)
- **Purpose**: Sets `liquidityAddressView` (callable once).
- **State Changes**: `liquidityAddressView`.
- **Restrictions**: Reverts if set or invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Used in `ccUpdate`.

#### setOracleParams(address _oracleAddress, bytes4 _oracleFunction, uint16 _oracleBitSize, bool _oracleIsSigned, uint8 _oracleDecimals)
- **Purpose**: Sets oracle parameters (callable once).
- **State Changes**: `oracleAddress`, `oracleFunction`, `oracleBitSize`, `oracleIsSigned`, `oracleDecimals`, `_oracleSet`.
- **Restrictions**: Reverts if set or parameters invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Emits `OracleParamsSet`.

#### setBaseOracleParams(address _baseOracleAddress, bytes4 _baseOracleFunction, uint16 _baseOracleBitSize, bool _baseOracleIsSigned, uint8 _baseOracleDecimals)
- **Purpose**: Sets base oracle parameters (callable once).
- **State Changes**: `baseOracleAddress`, `baseOracleFunction`, `baseOracleBitSize`, `baseOracleIsSigned`, `baseOracleDecimals`, `_baseOracleSet`.
- **Restrictions**: Reverts if set or parameters invalid.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Emits `OracleParamsSet`.

#### transactToken(address token, uint256 amount, address recipient)
- **Purpose**: Transfers ERC20 tokens, checks balances.
- **State Changes**: None directly.
- **Restrictions**: Router-only, valid token, non-zero `recipient`, `amount`.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Calls `IERC20.balanceOf`, `IERC20.transfer`, emits `TransactionFailed`.

#### transactNative(uint256 amount, address recipient)
- **Purpose**: Transfers ETH, checks balances.
- **State Changes**: None directly.
- **Restrictions**: Router-only, one token must be `address(0)`, non-zero `recipient`, `amount`, `msg.value` match.
- **Internal Call Tree**: None.
- **Parameters/Interactions**: Uses low-level `call`, emits `TransactionFailed`.

#### ccUpdate(BuyOrderUpdate[] calldata buyUpdates, SellOrderUpdate[] calldata sellUpdates, BalanceUpdate[] calldata balanceUpdates, HistoricalUpdate[] calldata historicalUpdates)
- **Purpose**: Updates orders, balances, historical data, router-only.
- **Parameters**:
  - `buyUpdates`: Array of `BuyOrderUpdate` for buy orders.
  - `sellUpdates`: Array of `SellOrderUpdate` for sell orders.
  - `balanceUpdates`: Array of `BalanceUpdate` for balances.
  - `historicalUpdates`: Array of `HistoricalUpdate` for historical data.
- **Logic**:
  1. Verifies router caller.
  2. Processes `buyUpdates` via `_processBuyOrderUpdate`:
     - `structId=0` (Core): Updates `buyOrderCore`, manages `_pendingBuyOrders`, `makerPendingOrders`, increments `nextOrderId` for `status=1`.
     - `structId=1` (Pricing): Updates `buyOrderPricing`.
     - `structId=2` (Amounts): Updates `buyOrderAmounts`, adds `filled` difference to `_historicalData.yVolume`, `amountSent` to `_historicalData.xVolume`.
  3. Processes `sellUpdates` via `_processSellOrderUpdate`:
     - Similar to buy, updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingSellOrders`, adds `filled` to `_historicalData.xVolume`, `amountSent` to `_historicalData.yVolume`.
  4. Processes `balanceUpdates`: Pushes `HistoricalData` with computed price, emits `BalancesUpdated`.
  5. Processes `historicalUpdates` via `_processHistoricalUpdate`: Creates new `HistoricalData` entry per update, updates `_dayStartIndices`.
  6. Updates `dayStartFee` if not same day, fetches fees via `ICCLiquidityTemplate.liquidityDetail`.
  7. Checks `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
  8. Calls `globalizeUpdate`.
- **State Changes**: `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`, `orderStatus`, `_historicalData`, `_dayStartIndices`, `dayStartFee`, `nextOrderId`.
- **External Interactions**: `IERC20.balanceOf`, `ICCLiquidityTemplate.liquidityDetail`, `ITokenRegistry.initializeTokens`, `ICCGlobalizer.globalizeOrders`.
- **Internal Call Tree**: `_processBuyOrderUpdate` (`removePendingOrder`, `_updateRegistry`), `_processSellOrderUpdate` (`removePendingOrder`, `_updateRegistry`), `_processHistoricalUpdate` (`_updateHistoricalData`, `_updateDayStartIndex`, `_floorToMidnight`, `normalize`), `globalizeUpdate`, `_updateRegistry`, `_floorToMidnight`, `_isSameDay`, `removePendingOrder`.
- **Errors**: Emits `UpdateFailed`, `OrderUpdateIncomplete`, `OrderUpdatesComplete`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`.

### Internal Functions
#### normalize(uint256 amount, uint8 decimals) returns (uint256 normalized)
- **Purpose**: Converts amounts to 1e18 precision.
- **Callers**: `ccUpdate` (`_processHistoricalUpdate`), `prices`, `volumeBalances`.
- **External Callers**: `prices`, `volumeBalances`.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`, `oracleDecimals`, `baseOracleDecimals`.

#### denormalize(uint256 amount, uint8 decimals) returns (uint256 denormalized)
- **Purpose**: Converts amounts from 1e18 to token decimals.
- **Callers**: None.
- **External Callers**: None.
- **Parameters/Interactions**: Uses `decimalsA`, `decimalsB`.

#### _isSameDay(uint256 time1, uint256 time2) returns (bool sameDay)
- **Purpose**: Checks if timestamps are in the same day.
- **Callers**: `ccUpdate`.
- **External Callers**: None (exposed via `isSameDayView`).
- **Parameters/Interactions**: Used for `dayStartFee` updates.

#### _floorToMidnight(uint256 timestamp) returns (uint256 midnight)
- **Purpose**: Rounds timestamp to midnight UTC.
- **Callers**: `setTokens`, `ccUpdate` (`_processHistoricalUpdate`, `_updateDayStartIndex`).
- **External Callers**: None (exposed via `floorToMidnightView`).
- **Parameters/Interactions**: Used for `HistoricalData.timestamp`, `dayStartFee.timestamp`, `_dayStartIndices`.

#### _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) returns (uint256 volumeChange)
- **Purpose**: Returns volume from `_historicalData` at/after `startTime`.
- **Callers**: None.
- **External Callers**: None.
- **Parameters/Interactions**: Queries `_historicalData` with `maxIterations`.

#### _updateRegistry(address maker)
- **Purpose**: Updates registry with token balances.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Calls `ITokenRegistry.initializeTokens`, emits `RegistryUpdateFailed`, `ExternalCallFailed`.

#### globalizeUpdate()
- **Purpose**: Notifies `ICCGlobalizer` of latest order.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Calls `ICCGlobalizer.globalizeOrders`, emits `GlobalUpdateFailed`, `ExternalCallFailed`.

#### removePendingOrder(uint256[] storage orders, uint256 orderId)
- **Purpose**: Removes order ID from array.
- **Callers**: `_processBuyOrderUpdate`, `_processSellOrderUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Modifies `_pendingBuyOrders`, `_pendingSellOrders`, `makerPendingOrders`.

#### _processBuyOrderUpdate(BuyOrderUpdate memory update) returns (uint256)
- **Purpose**: Updates buy order structs, manages `_pendingBuyOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Updates `buyOrderCore`, `buyOrderPricing`, `buyOrderAmounts`, `_historicalData.yVolume`, `_historicalData.xVolume`, calls `removePendingOrder`, `_updateRegistry`, increments `nextOrderId`.

#### _processSellOrderUpdate(SellOrderUpdate memory update) returns (uint256)
- **Purpose**: Updates sell order structs, manages `_pendingSellOrders`, `makerPendingOrders`.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Updates `sellOrderCore`, `sellOrderPricing`, `sellOrderAmounts`, `_historicalData.xVolume`, `_historicalData.yVolume`, calls `removePendingOrder`, `_updateRegistry`, increments `nextOrderId`.

#### _processHistoricalUpdate(HistoricalUpdate memory update) returns (bool historicalUpdated)
- **Purpose**: Creates new `HistoricalData` entry per update with balances and price.
- **Callers**: `ccUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Calls `_updateHistoricalData`, `_updateDayStartIndex`, `_floorToMidnight`, `normalize`, `IERC20.balanceOf`. Emits `UpdateFailed` if `price` is zero.

#### _updateHistoricalData(HistoricalUpdate memory update)
- **Purpose**: Pushes new `HistoricalData` entry with normalized balances.
- **Callers**: `_processHistoricalUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Uses `normalize`, `IERC20.balanceOf`, sets `timestamp` to `update.timestamp` or midnight.

#### _updateDayStartIndex(uint256 timestamp)
- **Purpose**: Updates `_dayStartIndices` for midnight timestamp.
- **Callers**: `_processHistoricalUpdate`.
- **External Callers**: None.
- **Parameters/Interactions**: Calls `_floorToMidnight`, updates `_dayStartIndices` if unset.

### View Functions
#### getTokens()
- **Purpose**: Returns `tokenA`, `tokenB`.
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
- **Purpose**: Computes `tokenAPrice / baseTokenUSDPrice` using oracles, normalized to 1e18.
- **State Changes**: None.
- **Restrictions**: Reverts if oracles not set, calls fail, prices non-positive, or `tokenAPrice` zero.
- **Internal Call Tree**: `normalize`.
- **Parameters/Interactions**: Calls `oracleAddress`, `baseOracleAddress`, uses `oracleFunction`, `baseOracleFunction`, `oracleDecimals`, `baseOracleDecimals`.

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
- **Parameters/Interactions**: Calls `IERC20.balanceOf`.

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
- **Orders**: `ccUpdate` with `buyUpdates` inputs `tokenB` (`amounts.filled`), outputs `tokenA` (`amounts.amountSent`), adds to `yVolume`. `sellUpdates` inputs `tokenA`, outputs `tokenB`, adds to `xVolume`. Tracked via `orderStatus`, emits `OrderUpdatesComplete` or `OrderUpdateIncomplete`.
- **Price**: Fetched via `oracleAddress`, `baseOracleAddress`, decoded as `int256` or `uint256`, normalized to 1e18.
- **Registry**: Updated via `_updateRegistry` in `ccUpdate` with `tokenA`, `tokenB`.
- **Globalizer**: Updated via `globalizeUpdate` in `ccUpdate`.
- **Liquidity**: `ICCLiquidityTemplate.liquidityDetail` for fees in `ccUpdate`.
- **Historical Data**: Stored in `_historicalData` via `ccUpdate` (`historicalUpdates`) or auto-generated, with new entries per update.
- **External Calls**: `IERC20.balanceOf`, `IERC20.transfer`, `IERC20.decimals`, `ICCLiquidityTemplate.liquidityDetail`, `ITokenRegistry.initializeTokens`, `ICCGlobalizer.globalizeOrders`, `ICCAgent.getLister`, `ICCAgent.getRouters`, `IOracle` calls, low-level `call`.
- **Security**: Router checks, try-catch, explicit casting, emits `UpdateFailed`, `TransactionFailed`, `ExternalCallFailed`, `RegistryUpdateFailed`, `GlobalUpdateFailed`, `OracleParamsSet`.
- **Optimization**: Normalized amounts, `maxIterations`, helper functions in `ccUpdate`.
- **Buy Conversions**: `tokenBAmount * (baseTokenPrice / tokenAPrice)`.
- **Sell Conversions**: `tokenAAmount / (baseTokenPrice / tokenAPrice)`.
