# Marker Foundry : Oracle Contracts Documentation
The system is functionally a clone of ShockSpace, with substantial adjustments to all contracts and removal of drivers, this enables oracle type listing for stablecoins without leverage. 
Payout structs - mappings and functions are retained but are functionally useless.
It comprises of OMFAgent -  OMFListingLogic - OMFLiquidityLogic - OMFLiquidityTemplate - OMFListingTemplate and OMFRouter.

## OMFLiquidityLogic Contract

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new OMFLiquidityTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed OMFLiquidityTemplate contract.

## OMFListingLogic Contract

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new OMFListingTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed OMFListingTemplate contract.

# OMFAgent Contract Documentation

## Overview
The `OMFAgent` contract, implemented in Solidity (^0.8.2), serves as a central coordinator for creating and managing token pair listings and liquidity pools in a decentralized trading system, integrating with `OMFListingTemplate`, `OMFLiquidityTemplate`, and `TokenRegistry` contracts. It uses `SafeERC20` for secure token operations and `Ownable` for restricted access, managing listings, liquidity, and orders with a focus on ERC-20 tokens and oracle-based pricing. State variables are private, accessed via view functions, and support pagination for queries.

**Inheritance**: `Ownable`

**SPDX License**: BSD-3-Clause

**Version**: 0.0.7 (last updated 2025-07-02)

## State Variables
- **routers** (address[], private): Array of router addresses for operations.
- **_listingLogicAddress** (address, private): `OMFListingLogic` contract address.
- **_liquidityLogicAddress** (address, private): `OMFLiquidityLogic` contract address.
- **_baseToken** (address, private): Reference token (Token-1) for pairs.
- **_registryAddress** (address, private): `TokenRegistry` contract address.
- **_listingCount** (uint256, private): Total number of listings.
- **_getListing** (mapping(address => mapping(address => address)), private): Maps `tokenA => baseToken => listingAddress`.
- **_allListings** (address[], private): Array of all listing addresses.
- **_allListedTokens** (address[], private): Array of listed tokenAs.
- **_queryByAddress** (mapping(address => uint256[]), private): Maps `tokenA => listingId[]`.
- **_globalLiquidity** (mapping(address => mapping(address => mapping(address => uint256))), private): Maps `tokenA => baseToken => user => amount`.
- **_totalLiquidityPerPair** (mapping(address => mapping(address => uint256)), private): Maps `tokenA => baseToken => amount`.
- **_userTotalLiquidity** (mapping(address => uint256), private): Maps `user => total liquidity`.
- **_listingLiquidity** (mapping(uint256 => mapping(address => uint256)), private): Maps `listingId => user => amount`.
- **_historicalLiquidityPerPair** (mapping(address => mapping(address => mapping(uint256 => uint256))), private): Maps `tokenA => baseToken => timestamp => amount`.
- **_historicalLiquidityPerUser** (mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))), private): Maps `tokenA => baseToken => user => timestamp => amount`.
- **_globalOrders** (mapping(address => mapping(address => mapping(uint256 => GlobalOrder))), private): Maps `tokenA => baseToken => orderId => GlobalOrder`.
- **_pairOrders** (mapping(address => mapping(address => uint256[])), private): Maps `tokenA => baseToken => orderId[]`.
- **_userOrders** (mapping(address => uint256[]), private): Maps `user => orderId[]`.
- **_historicalOrderStatus** (mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))), private): Maps `tokenA => baseToken => orderId => timestamp => status`.
- **_userTradingSummaries** (mapping(address => mapping(address => mapping(address => uint256))), private): Maps `user => tokenA => baseToken => volume`.

## Structs
- **GlobalOrder**: Contains `orderId` (uint256), `isBuy` (bool), `maker` (address), `recipient` (address), `amount` (uint256), `status` (uint8: 0=cancelled, 1=pending, 2=partially filled, 3=filled), `timestamp` (uint256).
- **PrepData**: Includes `listingSalt` (bytes32), `liquiditySalt` (bytes32), `tokenA` (address), `oracleAddress` (address), `oracleDecimals` (uint8), `oracleViewFunction` (bytes4).
- **InitData**: Includes `listingAddress` (address), `liquidityAddress` (address), `tokenA` (address), `tokenB` (address), `listingId` (uint256), `oracleAddress` (address), `oracleDecimals` (uint8), `oracleViewFunction` (bytes4).
- **TrendData**: Contains `token` (address), `timestamp` (uint256), `amount` (uint256).
- **OrderData**: Contains `orderId` (uint256), `isBuy` (bool), `maker` (address), `recipient` (address), `amount` (uint256), `status` (uint8), `timestamp` (uint256).

## External Functions

### addRouter(address router)
- **Parameters**: `router` (address): Router address to add.
- **Behavior**: Adds a router to the `routers` array, emits `RouterAdded`.
- **Internal Call Flow**: Validates non-zero address, checks `routerExists`, appends to `routers`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `routers`.
- **Restrictions**: `onlyOwner`, reverts if `router` is zero (`"Invalid router address"`) or already exists (`"Router already exists"`).
- **Gas Usage Controls**: Single array append, single loop in `routerExists`.

### removeRouter(address router)
- **Parameters**: `router` (address): Router address to remove.
- **Behavior**: Removes a router from the `routers` array, emits `RouterRemoved`.
- **Internal Call Flow**: Validates non-zero address, finds and removes router by swapping with last element and popping.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `routers`.
- **Restrictions**: `onlyOwner`, reverts if `router` is zero (`"Invalid router address"`) or not found (`"Router not found"`).
- **Gas Usage Controls**: Single loop, array modification.

### setListingLogic(address listingLogic)
- **Parameters**: `listingLogic` (address): `OMFListingLogic` address.
- **Behavior**: Sets `_listingLogicAddress`.
- **Internal Call Flow**: Validates non-zero address, updates `_listingLogicAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingLogicAddress`.
- **Restrictions**: `onlyOwner`, reverts if `listingLogic` is zero (`"Invalid logic address"`).
- **Gas Usage Controls**: Single state write.

### setLiquidityLogic(address liquidityLogic)
- **Parameters**: `liquidityLogic` (address): `OMFLiquidityLogic` address.
- **Behavior**: Sets `_liquidityLogicAddress`.
- **Internal Call Flow**: Validates non-zero address, updates `_liquidityLogicAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_liquidityLogicAddress`.
- **Restrictions**: `onlyOwner`, reverts if `liquidityLogic` is zero (`"Invalid logic address"`).
- **Gas Usage Controls**: Single state write.

### setBaseToken(address baseToken)
- **Parameters**: `baseToken` (address): Reference token (Token-1).
- **Behavior**: Sets `_baseToken`.
- **Internal Call Flow**: Validates non-zero address, updates `_baseToken`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_baseToken`.
- **Restrictions**: `onlyOwner`, reverts if `baseToken` is zero (`"Base token cannot be NATIVE"`).
- **Gas Usage Controls**: Single state write.

### setRegistry(address registryAddress)
- **Parameters**: `registryAddress` (address): `TokenRegistry` address.
- **Behavior**: Sets `_registryAddress`.
- **Internal Call Flow**: Validates non-zero address, updates `_registryAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_registryAddress`.
- **Restrictions**: `onlyOwner`, reverts if `registryAddress` is zero (`"Invalid registry address"`).
- **Gas Usage Controls**: Single state write.

### listToken(address tokenA, address oracleAddress, uint8 oracleDecimals, bytes4 oracleViewFunction)
- **Parameters**: `tokenA` (address): Token-0. `oracleAddress` (address): Oracle contract. `oracleDecimals` (uint8): Oracle price decimals. `oracleViewFunction` (bytes4): Oracle view function selector.
- **Behavior**: Deploys and initializes listing and liquidity contracts, updates state, emits `ListingCreated`.
- **Internal Call Flow**:
  - Calls `prepListing` to validate and generate salts.
  - Calls `executeListing` to deploy contracts via `_deployPair`, initialize via `_initializeListing` and `_initializeLiquidity`, and update state via `_updateState`.
  - Increments `_listingCount`.
- **Balance Checks**: Caller must own 1% of `tokenA` supply.
- **Mappings/Structs Used**: `_getListing`, `_allListings`, `_allListedTokens`, `_queryByAddress`, `_listingCount`.
- **Restrictions**: Reverts if `_baseToken`, `routers` is empty, `_listingLogicAddress`, `_liquidityLogicAddress`, or `_registryAddress` is unset, `tokenA` is zero (`"TokenA cannot be NATIVE"`), `tokenA` equals `_baseToken` (`"Identical tokens"`), pair exists (`"Pair already listed"`), or `oracleAddress` is zero (`"Invalid oracle address"`).
- **Gas Usage Controls**: Two deployments, multiple external calls, single loop in `tokenExists`.

### globalizeLiquidity(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit)
- **Parameters**: `listingId` (uint256): Listing ID. `tokenA` (address): Token-0. `tokenB` (address): BaseToken. `user` (address): Liquidity provider. `amount` (uint256): Liquidity amount. `isDeposit` (bool): True for deposit.
- **Behavior**: Updates global liquidity mappings, emits `GlobalLiquidityChanged`.
- **Internal Call Flow**:
  - Validates `tokenA`, `tokenB`, `user`, `listingId`, and caller as liquidity contract.
  - Calls `_updateGlobalLiquidity` to adjust `_globalLiquidity`, `_totalLiquidityPerPair`, `_userTotalLiquidity`, `_listingLiquidity`, and historical mappings.
- **Balance Checks**: For withdrawals, checks `_globalLiquidity`, `_totalLiquidityPerPair`, `_userTotalLiquidity`, `_listingLiquidity` for sufficiency.
- **Mappings/Structs Used**: `_getListing`, `_globalLiquidity`, `_totalLiquidityPerPair`, `_userTotalLiquidity`, `_listingLiquidity`, `_historicalLiquidityPerPair`, `_historicalLiquidityPerUser`.
- **Restrictions**: Reverts if tokens or user are zero (`"Invalid tokens"`, `"Invalid user"`), `tokenB` is not `_baseToken` (`"TokenB must be baseToken"`), `listingId` is invalid (`"Invalid listing ID"`), or caller is not liquidity contract (`"Caller is not liquidity contract"`).
- **Gas Usage Controls**: Minimal state writes, single external call.

### globalizeOrders(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, address recipient, uint256 amount, uint8 status)
- **Parameters**: `listingId` (uint256): Listing ID. `tokenA` (address): Token-0. `tokenB` (address): BaseToken. `orderId` (uint256): Order ID. `isBuy` (bool): True for buy order. `maker` (address): Order creator. `recipient` (address): Order recipient. `amount` (uint256): Order amount. `status` (uint8): Order status.
- **Behavior**: Updates order data, tracks historical status, updates trading summaries, emits `GlobalOrderChanged`.
- **Internal Call Flow**:
  - Validates `tokenA`, `tokenB`, `maker`, `listingId`, and caller as listing contract.
  - Updates `_globalOrders`, `_pairOrders`, `_userOrders`, `_historicalOrderStatus`, `_userTradingSummaries`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_getListing`, `_globalOrders`, `_pairOrders`, `_userOrders`, `_historicalOrderStatus`, `_userTradingSummaries`.
- **Restrictions**: Reverts if tokens or maker are zero (`"Invalid tokens"`, `"Invalid maker"`), `tokenB` is not `_baseToken` (`"TokenB must be baseToken"`), `listingId` is invalid (`"Invalid listing ID"`), or caller is not listing contract (`"Caller is not listing contract"`).
- **Gas Usage Controls**: Minimal state writes, single external call.

## View Functions

### getRouters()
- **Parameters**: None.
- **Behavior**: Returns `routers` array.
- **Internal Call Flow**: Reads `routers`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `routers`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### listingLogicAddressView()
- **Parameters**: None.
- **Behavior**: Returns `_listingLogicAddress`.
- **Internal Call Flow**: Reads `_listingLogicAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingLogicAddress`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### liquidityLogicAddressView()
- **Parameters**: None.
- **Behavior**: Returns `_liquidityLogicAddress`.
- **Internal Call Flow**: Reads `_liquidityLogicAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_liquidityLogicAddress`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### baseTokenView()
- **Parameters**: None.
- **Behavior**: Returns `_baseToken`.
- **Internal Call Flow**: Reads `_baseToken`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_baseToken`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### registryAddressView()
- **Parameters**: None.
- **Behavior**: Returns `_registryAddress`.
- **Internal Call Flow**: Reads `_registryAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_registryAddress`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### listingCountView()
- **Parameters**: None.
- **Behavior**: Returns `_listingCount`.
- **Internal Call Flow**: Reads `_listingCount`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingCount`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### getListingView(address tokenA, address tokenB)
- **Parameters**: `tokenA` (address): Token-0. `tokenB` (address): BaseToken.
- **Behavior**: Returns `_getListing[tokenA][tokenB]`.
- **Internal Call Flow**: Reads `_getListing`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_getListing`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### allListingsLengthView()
- **Parameters**: None.
- **Behavior**: Returns `_allListings.length`.
- **Internal Call Flow**: Reads `_allListings`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_allListings`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### allListedTokensLengthView()
- **Parameters**: None.
- **Behavior**: Returns `_allListedTokens.length`.
- **Internal Call Flow**: Reads `_allListedTokens`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_allListedTokens`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

### validateListing(address listingAddress)
- **Parameters**: `listingAddress` (address): Listing contract address.
- **Behavior**: Returns validity and token details for a listing.
- **Internal Call Flow**: Checks `_allListedTokens` for `listingAddress`, returns `(true, listingAddress, tokenA, _baseToken)` if valid, else `(false, 0, 0, 0)`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_getListing`, `_allListedTokens`, `_baseToken`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Single loop over `_allListedTokens`.

### getPairLiquidityTrend(address tokenA, bool focusOnTokenA, uint256 startTime, uint256 endTime)
- **Parameters**: `tokenA` (address): Token-0 or baseToken. `focusOnTokenA` (bool): True to focus on tokenA. `startTime` (uint256): Start timestamp. `endTime` (uint256): End timestamp.
- **Behavior**: Returns timestamps and liquidity amounts for a pair.
- **Internal Call Flow**: Iterates `_historicalLiquidityPerPair` for non-zero amounts within time range, filters by `focusOnTokenA`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_getListing`, `_historicalLiquidityPerPair`, `_allListedTokens`.
- **Restrictions**: Reverts if `endTime < startTime` or `tokenA` is zero (`"Invalid parameters"`) or `_baseToken` is unset (`"Base token not set"`).
- **Gas Usage Controls**: Dynamic array resizing, single loop over time range.

### getUserLiquidityTrend(address user, bool focusOnTokenA, uint256 startTime, uint256 endTime)
- **Parameters**: `user` (address): Liquidity provider. `focusOnTokenA` (bool): True to focus on tokenA. `startTime` (uint256): Start timestamp. `endTime` (uint256): End timestamp.
- **Behavior**: Returns tokens, timestamps, and liquidity amounts for a user.
- **Internal Call Flow**: Iterates `_historicalLiquidityPerUser` for non-zero amounts, filters by `focusOnTokenA`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_allListedTokens`, `_historicalLiquidityPerUser`, `_baseToken`.
- **Restrictions**: Reverts if `endTime < startTime`, `user` is zero (`"Invalid parameters"`), or `_baseToken` is unset (`"Base token not set"`).
- **Gas Usage Controls**: Dynamic array resizing, nested loops over tokens and time range.

### getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
- **Parameters**: `user` (address): Liquidity provider. `maxIterations` (uint256): Maximum pairs to return.
- **Behavior**: Returns token pairs and liquidity amounts for a user.
- **Internal Call Flow**: Iterates `_globalLiquidity` for non-zero amounts, capped at `maxIterations`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_globalLiquidity`, `_allListedTokens`, `_baseToken`.
- **Restrictions**: Reverts if `maxIterations` is zero (`"Invalid maxIterations"`) or `_baseToken` is unset (`"Base token not set"`).
- **Gas Usage Controls**: Single loop, dynamic array resizing.

### getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
- **Parameters**: `listingId` (uint256): Listing ID. `maxIterations` (uint256): Maximum users to return.
- **Behavior**: Returns top users and their liquidity amounts for a listing, sorted descending.
- **Internal Call Flow**: Iterates `_listingLiquidity` for non-zero amounts, sorts via `_sortDescending`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingLiquidity`, `_allListedTokens`, `_getListing`.
- **Restrictions**: Reverts if `maxIterations` is zero (`"Invalid maxIterations"`) or `listingId` is invalid (`"Invalid listing ID"`).
- **Gas Usage Controls**: Nested loops, bubble sort, dynamic array resizing.

### getUserLiquidityShare(address user, address tokenA, address tokenB)
- **Parameters**: `user` (address): Liquidity provider. `tokenA` (address): Token-0. `tokenB` (address): BaseToken.
- **Behavior**: Returns user's liquidity share and total pair liquidity.
- **Internal Call Flow**: Reads `_globalLiquidity` and `_totalLiquidityPerPair`, calculates share with 18 decimals.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_globalLiquidity`, `_totalLiquidityPerPair`.
- **Restrictions**: Reverts if `tokenB` is not `_baseToken` (`"TokenB must be baseToken"`).
- **Gas Usage Controls**: Minimal reads, single calculation.

### getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
- **Parameters**: `minLiquidity` (uint256): Minimum liquidity threshold. `focusOnTokenA` (bool): True to focus on tokenA. `maxIterations` (uint256): Maximum pairs to return.
- **Behavior**: Returns token pairs with liquidity above `minLiquidity`, capped at `maxIterations`.
- **Internal Call Flow**: Iterates `_totalLiquidityPerPair` for qualifying pairs, filters by `focusOnTokenA`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_totalLiquidityPerPair`, `_allListedTokens`, `_baseToken`.
- **Restrictions**: Reverts if `maxIterations` is zero (`"Invalid maxIterations"`) or `_baseToken` is unset (`"Base token not set"`).
- **Gas Usage Controls**: Single loop, dynamic array resizing.

### getOrderActivityByPair(address tokenA, address tokenB, uint256 startTime, uint256 endTime)
- **Parameters**: `tokenA` (address): Token-0. `tokenB` (address): BaseToken. `startTime` (uint256): Start timestamp. `endTime` (uint256): End timestamp.
- **Behavior**: Returns order IDs and details within time range for a pair.
- **Internal Call Flow**: Iterates `_pairOrders` and `_globalOrders` for orders within time range.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_pairOrders`, `_globalOrders`.
- **Restrictions**: Reverts if `endTime < startTime`, tokens are zero (`"Invalid parameters"`), or `tokenB` is not `_baseToken` (`"TokenB must be baseToken"`).
- **Gas Usage Controls**: Single loop, dynamic array resizing.

### getUserTradingProfile(address user)
- **Parameters**: `user` (address): Trader address.
- **Behavior**: Returns token pairs and trading volumes for a user.
- **Internal Call Flow**: Iterates `_userTradingSummaries` for non-zero volumes.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_userTradingSummaries`, `_allListedTokens`, `_baseToken`.
- **Restrictions**: Reverts if `_baseToken` is unset (`"Base token not set"`).
- **Gas Usage Controls**: Single loop, dynamic array resizing.

### getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
- **Parameters**: `listingId` (uint256): Listing ID. `maxIterations` (uint256): Maximum traders to return.
- **Behavior**: Returns top traders and their volumes, sorted descending.
- **Internal Call Flow**: Iterates `_userTradingSummaries` for non-zero volumes, sorts via `_sortDescending`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_userTradingSummaries`, `_allListings`, `_allListedTokens`, `_getListing`.
- **Restrictions**: Reverts if `maxIterations` is zero (`"Invalid maxIterations"`).
- **Gas Usage Controls**: Nested loops, bubble sort, dynamic array resizing.

### queryByIndex(uint256 index)
- **Parameters**: `index` (uint256): Listing index.
- **Behavior**: Returns listing address at `_allListings[index]`.
- **Internal Call Flow**: Reads `_allListings`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_allListings`.
- **Restrictions**: Reverts if `index` exceeds `_allListings.length` (`"Invalid index"`).
- **Gas Usage Controls**: Minimal read.

### queryByAddressView(address target, uint256 maxIteration, uint256 step)
- **Parameters**: `target` (address): Token address. `maxIteration` (uint256): Listings per step. `step` (uint256): Pagination step.
- **Behavior**: Returns paginated listing IDs for a token.
- **Internal Call Flow**: Slices `_queryByAddress[target]` based on `maxIteration` and `step`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_queryByAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: Single loop for slicing, dynamic array resizing.

### queryByAddressLength(address target)
- **Parameters**: `target` (address): Token address.
- **Behavior**: Returns number of listings for a token.
- **Internal Call Flow**: Reads `_queryByAddress[target].length`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_queryByAddress`.
- **Restrictions**: None.
- **Gas Usage Controls**: Minimal read.

## Additional Details
- **Decimal Handling**: Adjusts for non-18 decimal tokens in `checkCallerBalance`.
- **Access Control**: `onlyOwner` for setter functions, specific caller restrictions for `globalizeLiquidity` and `globalizeOrders`.
- **Gas Optimization**: Dynamic array resizing, bubble sort in `_sortDescending`, pagination in `queryByAddressView`.
- **Events**: `ListingCreated`, `GlobalLiquidityChanged`, `GlobalOrderChanged`, `RouterAdded`, `RouterRemoved`.
- **Safety**: Explicit casting, no inline assembly, validation for non-zero addresses.
- **Interface Compliance**: Integrates with `IOMFListingTemplate`, `IOMFLiquidityTemplate`, `IOMFListingLogic`, `IOMFListing`, `IERC20`.

# OMFListingTemplate Contract Documentation

## Overview
The `OMFListingTemplate` contract, implemented in Solidity (^0.8.2), manages a decentralized order book for trading ERC-20 token pairs, integrating with external oracle pricing, liquidity pools, and agent contracts. It uses `SafeERC20` for secure token operations and `ReentrancyGuard` for protection against reentrancy attacks. The contract handles balance updates, buy/sell orders, historical data storage, and yield calculations, ensuring decimal precision and gas efficiency. State variables are hidden and accessed via dedicated view functions, adhering to strict interface compliance with `IOMFListing`, `IOMFAgent`, `ITokenRegistry`, and `IOMFLiquidityTemplate`.

**Inheritance**: `ReentrancyGuard`

**SPDX License**: BSD-3-Clause

**Version**: 0.0.32 (last updated 2025-06-30)

## State Variables
- **_routers** (mapping(address => bool), private): Tracks authorized router addresses.
- **_routersSet** (bool, private): Indicates if routers are initialized.
- **_token0** (address, private): Address of the listed token (token0).
- **_baseToken** (address, private): Address of the reference token (baseToken).
- **_decimal0** (uint8, private): Decimals of token0.
- **_baseTokenDecimals** (uint8, private): Decimals of baseToken.
- **_listingId** (uint256, private): Unique identifier for the listing.
- **_oracle** (address, private): Oracle contract address for price feeds.
- **_oracleDecimals** (uint8, private): Decimals used by the oracle.
- **_oracleViewFunction** (bytes4, private): Selector for the oracle’s price view function.
- **_agent** (address, private): Address of the `IOMFAgent` contract.
- **_registryAddress** (address, private): Address of the `ITokenRegistry` contract.
- **_liquidityAddress** (address, private): Address of the `IOMFLiquidityTemplate` contract.
- **_orderIdHeight** (uint256, private): Tracks the next available order ID.
- **_lastDayFee** (LastDayFee, private): Stores daily fee data (xFees, yFees, timestamp).
- **_volumeBalance** (VolumeBalance, private): Tracks token balances and volumes (xBalance, yBalance, xVolume, yVolume).
- **_buyOrderCores** (mapping(uint256 => BuyOrderCore), private): Stores buy order core data (makerAddress, recipientAddress, status).
- **_buyOrderPricings** (mapping(uint256 => BuyOrderPricing), private): Stores buy order pricing (maxPrice, minPrice).
- **_buyOrderAmounts** (mapping(uint256 => BuyOrderAmounts), private): Stores buy order amounts (pending, filled, amountSent).
- **_sellOrderCores** (mapping(uint256 => SellOrderCore), private): Stores sell order core data (makerAddress, recipientAddress, status).
- **_sellOrderPricings** (mapping(uint256 => SellOrderPricing), private): Stores sell order pricing (maxPrice, minPrice).
- **_sellOrderAmounts** (mapping(uint256 => SellOrderAmounts), private): Stores sell order amounts (pending, filled, amountSent).
- **_isBuyOrderComplete** (mapping(uint256 => bool), private): Tracks buy order completeness.
- **_isSellOrderComplete** (mapping(uint256 => bool), private): Tracks sell order completeness.
- **_pendingBuyOrders** (uint256[], private): Lists pending buy order IDs.
- **_pendingSellOrders** (uint256[], private): Lists pending sell order IDs.
- **_makerPendingOrders** (mapping(address => uint256[]), private): Maps maker addresses to their pending order IDs.
- **_historicalData** (HistoricalData[], private): Stores historical price and balance data.

## Structs
- **UpdateType** (defined in `IOMFListing`): Contains `updateType` (uint8: 0=balance, 1=buy order, 2=sell order, 3=historical), `structId` (uint8: 0=Core, 1=Pricing, 2=Amounts), `index` (uint256: orderId or slot), `value` (uint256: amount/price), `addr` (address: maker), `recipient` (address), `maxPrice`, `minPrice`, `amountSent` (uint256).
- **LastDayFee**: Contains `xFees` (uint256: token0 fees), `yFees` (uint256: baseToken fees), `timestamp` (uint256: midnight timestamp).
- **VolumeBalance**: Includes `xBalance` (uint256: token0 balance), `yBalance` (uint256: baseToken balance), `xVolume` (uint256: token0 volume), `yVolume` (uint256: baseToken volume).
- **BuyOrderCore**: Stores `makerAddress` (address), `recipientAddress` (address), `status` (uint8: 0=cancelled, 1=pending, 2=partially filled, 3=filled).
- **BuyOrderPricing**: Holds `maxPrice` (uint256), `minPrice` (uint256).
- **BuyOrderAmounts**: Tracks `pending` (uint256: baseToken pending), `filled` (uint256: baseToken filled), `amountSent` (uint256: token0 sent).
- **SellOrderCore**: Same as `BuyOrderCore`.
- **SellOrderPricing**: Same as `BuyOrderPricing`.
- **SellOrderAmounts**: Tracks `pending` (uint256: token0 pending), `filled` (uint256: token0 filled), `amountSent` (uint256: baseToken sent).
- **HistoricalData**: Contains `price` (uint256), `xBalance`, `yBalance`, `xVolume`, `yVolume` (uint256), `timestamp` (uint256).

## Formulas
1. **Normalization**:
   - **Formula**: `normalizedAmount = decimals == 18 ? amount : decimals < 18 ? amount * 10^(18-decimals) : amount / 10^(decimals-18)`
   - **Used in**: `normalize`, `transact`.
   - **Description**: Adjusts token amounts to 18 decimals for consistency.

2. **Denormalization**:
   - **Formula**: `denormalizedAmount = decimals == 18 ? amount : decimals < 18 ? amount / 10^(18-decimals) : amount * 10^(decimals-18)`
   - **Used in**: `denormalize`, `transact`.
   - **Description**: Converts normalized amounts back to token-specific decimals.

3. **Daily Yield**:
   - **Formula**: `dailyYield = (feeDifference * 0.05% * 1e18) / liquidity`
   - **Used in**: `queryYield`.
   - **Description**: Calculates daily yield based on volume fees and liquidity.

4. **Annualized Yield**:
   - **Formula**: `annualizedYield = dailyYield * 365`
   - **Used in**: `queryYield`.
   - **Description**: Extrapolates daily yield to annual yield.

5. **Volume Change**:
   - **Formula**: `volumeChange = currentVolume - historicalVolume`
   - **Used in**: `_findVolumeChange`.
   - **Description**: Computes volume difference since a given timestamp.

## External Functions

### setRouters(address[] memory routers)
- **Parameters**:
  - `routers` (address[]): Array of router addresses.
- **Behavior**: Sets authorized router addresses, marking `_routersSet` as true.
- **Internal Call Flow**: Iterates `routers`, validates non-zero addresses, sets `_routers[router] = true`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_routers`, `_routersSet`.
- **Restrictions**:
  - Reverts if `_routersSet` is true (`"Routers already set"`) or `routers` is empty (`"No routers provided"`) or contains zero addresses (`"Invalid router address"`).
- **Gas Usage Controls**: Single loop over `routers`, minimal state writes.

### setListingId(uint256 listingId)
- **Parameters**:
  - `listingId` (uint256): Listing identifier.
- **Behavior**: Sets `_listingId` for the contract.
- **Internal Call Flow**: Validates `_listingId == 0`, assigns `listingId`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_listingId`.
- **Restrictions**:
  - Reverts if `_listingId` is set (`"Listing ID already set"`).
- **Gas Usage Controls**: Single state write, minimal gas.

### setLiquidityAddress(address liquidityAddress)
- **Parameters**:
  - `liquidityAddress` (address): Liquidity contract address.
- **Behavior**: Sets `_liquidityAddress` for yield calculations.
- **Internal Call Flow**: Validates `_liquidityAddress == 0` and `liquidityAddress` non-zero, assigns `_liquidityAddress`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_liquidityAddress`.
- **Restrictions**:
  - Reverts if `_liquidityAddress` is set (`"Liquidity already set"`) or `liquidityAddress` is zero (`"Invalid liquidity address"`).
- **Gas Usage Controls**: Single state write, minimal gas.

### setTokens(address token0, address baseToken)
- **Parameters**:
  - `token0` (address): Listed token address.
  - `baseToken` (address): Reference token address.
- **Behavior**: Sets `_token0`, `_baseToken`, `_decimal0`, and `_baseTokenDecimals`.
- **Internal Call Flow**: Validates tokens are unset, non-zero, and distinct. Calls `IERC20.decimals` (input: none, returns: `uint8`) for both tokens. No transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_token0`, `_baseToken`, `_decimal0`, `_baseTokenDecimals`.
- **Restrictions**:
  - Reverts if tokens are set (`"Tokens already set"`), either is zero (`"Tokens must be ERC-20"`), or tokens are identical (`"Tokens must be different"`).
- **Gas Usage Controls**: Two external calls, minimal state writes.

### setOracleDetails(address oracle, uint8 oracleDecimals, bytes4 viewFunction)
- **Parameters**:
  - `oracle` (address): Oracle contract address.
  - `oracleDecimals` (uint8): Oracle price decimals.
  - `viewFunction` (bytes4): Oracle price function selector.
- **Behavior**: Sets `_oracle`, `_oracleDecimals`, and `_oracleViewFunction`.
- **Internal Call Flow**: Validates `_oracle == 0`, `oracle` non-zero, and `viewFunction` non-zero. Assigns values. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_oracle`, `_oracleDecimals`, `_oracleViewFunction`.
- **Restrictions**:
  - Reverts if `_oracle` is set (`"Oracle already set"`), `oracle` is zero (`"Invalid oracle"`), or `viewFunction` is zero (`"Invalid view function"`).
- **Gas Usage Controls**: Three state writes, minimal gas.

### setAgent(address agent)
- **Parameters**:
  - `agent` (address): `IOMFAgent` contract address.
- **Behavior**: Sets `_agent` for order globalization.
- **Internal Call Flow**: Validates `_agent == 0` and `agent` non-zero, assigns `_agent`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_agent`.
- **Restrictions**:
  - Reverts if `_agent` is set (`"Agent already set"`) or `agent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Single state write, minimal gas.

### setRegistry(address registryAddress)
- **Parameters**:
  - `registryAddress` (address): `ITokenRegistry` contract address.
- **Behavior**: Sets `_registryAddress` for maker balance initialization.
- **Internal Call Flow**: Validates `_registryAddress == 0` and `registryAddress` non-zero, assigns `_registryAddress`. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_registryAddress`.
- **Restrictions**:
  - Reverts if `_registryAddress` is set (`"Registry already set"`) or `registryAddress` is zero (`"Invalid registry address"`).
- **Gas Usage Controls**: Single state write, minimal gas.

### nextOrderId()
- **Parameters**: None.
- **Behavior**: Returns and increments `_orderIdHeight`.
- **Internal Call Flow**: Returns `_orderIdHeight`, then increments it. No external calls or transfers.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_orderIdHeight`.
- **Restrictions**:
  - Restricted to `onlyRouter`.
- **Gas Usage Controls**: Single state read/write, minimal gas.

### update(address caller, IOMFListing.UpdateType[] memory updates)
- **Parameters**:
  - `caller` (address): Caller address (router).
  - `updates` (UpdateType[]): Array of updates for balances, orders, or historical data.
- **Behavior**: Processes balance updates, buy/sell order creation/fills/cancellations, or historical data updates, validating prices against oracle, updating balances, and syncing with agent.
- **Internal Call Flow**:
  - Calls `getPrice` for oracle price, cached for consistency.
  - Checks `_lastDayFee` for reset using `_floorToMidnight` and `_isSameDay`.
  - Iterates `updates`:
    - **Balance Updates** (`updateType=0`): Updates `_volumeBalance` (xBalance, yBalance, xVolume, yVolume).
    - **Buy Order Updates** (`updateType=1`):
      - **Core** (`structId=0`): Creates/cancels orders in `_buyOrderCores`, updates `_pendingBuyOrders`, `_makerPendingOrders`, `_orderIdHeight`.
      - **Pricing** (`structId=1`): Validates `minPrice <= oraclePrice <= maxPrice`, updates `_buyOrderPricings`.
      - **Amounts** (`structId=2`): Updates `_buyOrderAmounts`, adjusts `_volumeBalance`, sets `_isBuyOrderComplete`.
    - **Sell Order Updates** (`updateType=2`): Similar to buy orders for `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_isSellOrderComplete`.
    - **Historical Data** (`updateType=3`): Pushes to `_historicalData` with packed balances/volumes.
  - Calls `globalizeUpdate`, invoking `IOMFAgent.globalizeOrders` (input: `_listingId`, `_token0`, `_baseToken`, order details, returns: none) for pending orders.
  - Emits `BalancesUpdated` and `OrderUpdated`.
- **Balance Checks**:
  - **Pre-Balance Check (Amounts)**: For buy orders, `amounts.pending >= u.value` ensures sufficient pending amount.
  - **Pre-Balance Check (Historical)**: Oracle price must be non-zero (`"Oracle price fetch failed"`).
- **Mappings/Structs Used**:
  - **Mappings**: `_volumeBalance`, `_buyOrderCores`, `_buyOrderPricings`, `_buyOrderAmounts`, `_sellOrderCores`, `_sellOrderPricings`, `_sellOrderAmounts`, `_pendingBuyOrders`, `_pendingSellOrders`, `_makerPendingOrders`, `_isBuyOrderComplete`, `_isSellOrderComplete`, `_historicalData`.
  - **Structs**: `UpdateType`, `VolumeBalance`, `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`, `HistoricalData`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyRouter`.
  - Reverts on invalid price ranges, insufficient pending amounts, or zero oracle price.
- **Gas Usage Controls**: Single price fetch, pop-and-swap for array removals, no nested loops.

### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` (address): Caller address (router).
  - `token` (address): Token to transfer (token0 or baseToken).
  - `amount` (uint256): Amount to transfer (denormalized).
  - `recipient` (address): Transfer recipient.
- **Behavior**: Transfers tokens, updates `_volumeBalance`, and syncs with registry and agent.
- **Internal Call Flow**:
  - Normalizes `amount` using `normalize` and `IERC20.decimals`.
  - Resets `_lastDayFee` if needed using `_floorToMidnight`.
  - For `token == _token0`:
    - Checks `_volumeBalance.xBalance >= normalizedAmount`.
    - Updates `_volumeBalance.xBalance` and `xVolume`.
    - Transfers `amount` via `IERC20.safeTransfer` (input: `recipient`, `amount`, returns: none).
  - For `token == _baseToken`: Similar, updating `yBalance` and `yVolume`.
  - Calls `_updateRegistry`, invoking `ITokenRegistry.initializeBalances` (input: `token`, maker addresses, returns: none).
  - Calls `globalizeUpdate`.
  - Emits `BalancesUpdated`.
- **Balance Checks**:
  - **Pre-Balance Check**: `xBalance >= normalizedAmount` or `yBalance >= normalizedAmount` for respective tokens.
- **Mappings/Structs Used**:
  - **Mappings**: `_volumeBalance`, `_lastDayFee`, `_token0`, `_baseToken`, `_registryAddress`, `_agent`.
  - **Structs**: `VolumeBalance`, `LastDayFee`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyRouter`.
  - Reverts if `token` is invalid (`"Invalid token"`) or balance is insufficient.
- **Gas Usage Controls**: Single transfer, pop-and-swap in `_updateRegistry`, minimal gas.

### queryYield(bool isX, uint256 maxIterations)
- **Parameters**:
  - `isX` (bool): True for token0, false for baseToken.
  - `maxIterations` (uint256): Maximum historical data iterations.
- **Behavior**: Calculates annualized yield based on volume fees and liquidity.
- **Internal Call Flow**:
  - Validates `maxIterations > 0`.
  - Checks `_lastDayFee` and `_isSameDay` for valid daily data.
  - Calculates `feeDifference` using `_volumeBalance` and `_lastDayFee`.
  - Fetches liquidity via `IOMFLiquidityTemplate.liquidityAmounts` (input: none, returns: `xAmount`, `yAmount`).
  - Applies yield formulas, returning `dailyYield * 365`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_lastDayFee`, `_volumeBalance`, `_liquidityAddress`.
  - **Structs**: `LastDayFee`, `VolumeBalance`.
- **Restrictions**:
  - Reverts if `maxIterations == 0` (`"Invalid maxIterations"`).
  - Returns 0 on invalid data or failed liquidity fetch (graceful degradation).
- **Gas Usage Controls**: View function, single external call, minimal gas.

### getPrice()
- **Parameters**: None.
- **Behavior**: Fetches oracle price, falling back to historical data or 0 if unavailable.
- **Internal Call Flow**:
  - Returns last `_historicalData.price` if `_oracle` or `_oracleViewFunction` is unset.
  - Calls oracle via `staticcall` with `_oracleViewFunction`, decoding via `decodePrice`.
  - Validates non-negative price, scales to 18 decimals based on `_oracleDecimals`.
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Mappings**: `_oracle`, `_oracleDecimals`, `_oracleViewFunction`, `_historicalData`.
  - **Structs**: `HistoricalData`.
- **Restrictions**:
  - Reverts if price is negative (`"Negative price not allowed"`).
- **Gas Usage Controls**: View function, single external call, minimal gas.

### View Functions
- **routersView(address router)**: Returns `_routers[router]`.
- **routersSetView()**: Returns `_routersSet`.
- **token0View()**: Returns `_token0`.
- **baseTokenView()**: Returns `_baseToken`.
- **decimals0View()**: Returns `_decimal0`.
- **baseTokenDecimalsView()**: Returns `_baseTokenDecimals`.
- **listingIdView()**: Returns `_listingId`.
- **oracleView()**: Returns `_oracle`.
- **oracleDecimalsView()**: Returns `_oracleDecimals`.
- **oracleViewFunctionView()**: Returns `_oracleViewFunction`.
- **agentView()**: Returns `_agent`.
- **registryAddressView()**: Returns `_registryAddress`.
- **liquidityAddressView(uint256)**: Returns `_liquidityAddress`.
- **orderIdHeightView()**: Returns `_orderIdHeight`.
- **lastDayFeeView()**: Returns `_lastDayFee` (xFees, yFees, timestamp).
- **volumeBalanceView()**: Returns `_volumeBalance` (xBalance, yBalance, xVolume, yVolume).
- **buyOrderCoreView(uint256 orderId)**: Returns `_buyOrderCores[orderId]` (makerAddress, recipientAddress, status).
- **buyOrderPricingView(uint256 orderId)**: Returns `_buyOrderPricings[orderId]` (maxPrice, minPrice).
- **buyOrderAmountsView(uint256 orderId)**: Returns `_buyOrderAmounts[orderId]` (pending, filled, amountSent).
- **sellOrderCoreView(uint256 orderId)**: Returns `_sellOrderCores[orderId]`.
- **sellOrderPricingView(uint256 orderId)**: Returns `_sellOrderPricings[orderId]`.
- **sellOrderAmountsView(uint256 orderId)**: Returns `_sellOrderAmounts[orderId]`.
- **isOrderCompleteView(uint256 orderId, bool isBuy)**: Returns `_isBuyOrderComplete` or `_isSellOrderComplete`.
- **pendingBuyOrdersView()**: Returns `_pendingBuyOrders`.
- **pendingSellOrdersView()**: Returns `_pendingSellOrders`.
- **makerPendingOrdersView(address maker)**: Returns `_makerPendingOrders[maker]`.
- **getHistoricalDataView(uint256 index)**: Returns `_historicalData[index]`.
- **historicalDataLengthView()**: Returns `_historicalData.length`.
- **getHistoricalDataByNearestTimestamp(uint256 targetTimestamp)**: Returns `_historicalData` entry closest to `targetTimestamp`.

**Common View Function Details**:
- **Internal Call Flow**: Direct mapping/struct access, no external calls or transfers.
- **Balance Checks**: None.
- **Restrictions**: Reverts on invalid inputs (e.g., `index >= _historicalData.length`).
- **Gas Usage Controls**: Minimal gas, view functions.

## Additional Details
- **Decimal Handling**: Normalizes amounts to 18 decimals using `normalize` and `denormalize`.
- **Reentrancy Protection**: `update` and `transact` use `nonReentrant`.
- **Gas Optimization**: Uses `maxIterations`, pop-and-swap for array removals, and cached oracle prices.
- **Oracle Integration**: `getPrice` supports dynamic `viewFunction` selectors with fallback to historical data.
- **Order Lifecycle**: Orders transition from pending (status=1) to partially filled (2), filled (3), or cancelled (0).
- **Events**: `OrderUpdated`, `BalancesUpdated`, `RegistryUpdateFailed`.
- **Safety**: Explicit casting, no inline assembly, and graceful degradation in `getPrice` and `queryYield`.
- **Interface Compliance**: Fully implements `IOMFListing`, interacts with `IOMFAgent`, `ITokenRegistry`, and `IOMFLiquidityTemplate`.

# OMFLiquidityTemplate Contract Documentation

## Overview
The `OMFLiquidityTemplate` contract, implemented in Solidity (^0.8.2), manages liquidity pools for ERC-20 token pairs, handling deposits, withdrawals, and fee claims for a decentralized trading system. It integrates with `OMFListingTemplate`, `OMFAgent`, and `TokenRegistry` contracts, using `SafeERC20` for secure token operations and `ReentrancyGuard` for protection against reentrancy attacks. The contract tracks liquidity slots, cumulative fee volumes, and balances, ensuring decimal precision and gas efficiency. State variables are private, accessed via dedicated view functions, and comply with the `IOMFLiquidityTemplate` interface.

**Inheritance**: `ReentrancyGuard`, `IOMFLiquidityTemplate`

**SPDX License**: BSD-3-Clause

**Version**: 0.0.15 (last updated 2025-06-30)

## State Variables
- **_routers** (mapping(address => bool), private): Tracks authorized router addresses.
- **_routersSet** (bool, private): Indicates if routers are initialized.
- **_listingAddress** (address, private): `OMFListingTemplate` contract address.
- **_tokenA** (address, private): First token address (tokenA).
- **_tokenB** (address, private): Second token address (tokenB).
- **_decimalA** (uint8, private): Decimals of tokenA.
- **_decimalB** (uint8, private): Decimals of tokenB.
- **_listingId** (uint256, private): Unique identifier for the listing.
- **_agent** (address, private): `IOMFAgent` contract address.
- **_liquidityDetail** (LiquidityDetails, private): Stores liquidity and fee balances (xLiquid, yLiquid, xFees, yFees, xFeesAcc, yFeesAcc).
- **_xLiquiditySlots** (mapping(uint256 => Slot), private): TokenA liquidity slots.
- **_yLiquiditySlots** (mapping(uint256 => Slot), private): TokenB liquidity slots.
- **_activeXLiquiditySlots** (uint256[], private): Active tokenA slot indices.
- **_activeYLiquiditySlots** (uint256[], private): Active tokenB slot indices.
- **_userIndex** (mapping(address => uint256[]), private): Maps user addresses to slot indices.

## Structs
- **LiquidityDetails**: Contains `xLiquid` (uint256: tokenA liquidity), `yLiquid` (uint256: tokenB liquidity), `xFees` (uint256: tokenA fees), `yFees` (uint256: tokenB fees), `xFeesAcc` (uint256: cumulative tokenA fees), `yFeesAcc` (uint256: cumulative tokenB fees).
- **Slot**: Includes `depositor` (address: slot owner), `recipient` (address: unused), `allocation` (uint256: liquidity amount), `dFeesAcc` (uint256: `yFeesAcc` for xSlot, `xFeesAcc` for ySlot at deposit), `timestamp` (uint256: deposit timestamp).
- **UpdateType**: Contains `updateType` (uint8: 0=balance, 1=fees, 2=xSlot, 3=ySlot), `index` (uint256: 0=xFees/xLiquid, 1=yFees/yLiquid, or slot index), `value` (uint256: amount/allocation), `addr` (address: depositor), `recipient` (address: unused).
- **PreparedWithdrawal**: Includes `amountA` (uint256: tokenA withdrawal), `amountB` (uint256: tokenB withdrawal).
- **FeeClaimContext**: Contains `caller` (address), `isX` (bool: true for xSlot), `liquid` (uint256: total liquidity), `allocation` (uint256: slot allocation), `fees` (uint256: available fees), `dFeesAcc` (uint256: cumulative fees at deposit), `liquidityIndex` (uint256: slot index).

## Formulas
1. **Normalization**:
   - **Formula**: `normalizedAmount = decimals == 18 ? amount : decimals < 18 ? amount * 10^(18-decimals) : amount / 10^(decimals-18)`
   - **Used in**: `normalize`, `deposit`, `transact`.
   - **Description**: Adjusts token amounts to 18 decimals.
2. **Denormalization**:
   - **Formula**: `denormalizedAmount = decimals == 18 ? amount : decimals < 18 ? amount / 10^(18-decimals) : amount * 10^(decimals-18)`
   - **Used in**: `denormalize`, `xExecuteOut`, `yExecuteOut`, `claimFees`.
   - **Description**: Converts normalized amounts to token-specific decimals.
3. **Fee Share Calculation**:
   - **Formula**: `feeShare = (contributedFees * allocation * 1e18 / liquid) > fees ? fees : computedValue`, where `contributedFees = fees > dFeesAcc ? fees - dFeesAcc : 0`
   - **Used in**: `_claimFeeShare`.
   - **Description**: Calculates fees based on cumulative fee contribution and liquidity share.
4. **Deficit and Compensation**:
   - **Formula for xPrepOut**:
     ```
     withdrawAmountA = min(amount, xLiquid)
     deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0
     withdrawAmountB = deficit > 0 ? min((deficit * 1e18) / getPrice(), yLiquid) : 0
     ```
   - **Formula for yPrepOut**:
     ```
     withdrawAmountB = min(amount, yLiquid)
     deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0
     withdrawAmountA = deficit > 0 ? min((deficit * getPrice()) / 1e18, xLiquid) : 0
     ```
   - **Used in**: `xPrepOut`, `yPrepOut`
   - **Description**: Calculates withdrawal amounts for token A (`xPrepOut`) or token B (`yPrepOut`), compensating any shortfall (`deficit`) in requested liquidity (`amount`) against available liquidity (`xLiquid` or `yLiquid`) by converting the deficit to the opposite token using the current price from `IOMFListing.getPrice`, ensuring amounts are normalized and capped by available liquidity.

## External Functions

### setRouters(address[] memory routers)
- **Parameters**: `routers` (address[]): Router addresses.
- **Behavior**: Sets `_routers` and `_routersSet`.
- **Internal Call Flow**: Iterates `routers`, validates non-zero addresses, sets `_routers[router] = true`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_routers`, `_routersSet`.
- **Restrictions**: Reverts if `_routersSet` is true (`"Routers already set"`) or `routers` is empty (`"No routers provided"`) or contains zero addresses (`"Invalid router address"`).
- **Gas Usage Controls**: Single loop, minimal state writes.

### setListingId(uint256 listingId)
- **Parameters**: `listingId` (uint256): Listing identifier.
- **Behavior**: Sets `_listingId`.
- **Internal Call Flow**: Validates `_listingId == 0`, assigns `listingId`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingId`.
- **Restrictions**: Reverts if `_listingId` is set (`"Listing ID already set"`).
- **Gas Usage Controls**: Single state write.

### setListingAddress(address listingAddress)
- **Parameters**: `listingAddress` (address): `OMFListingTemplate` address.
- **Behavior**: Sets `_listingAddress`.
- **Internal Call Flow**: Validates `_listingAddress == 0` and `listingAddress` non-zero, assigns `_listingAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingAddress`.
- **Restrictions**: Reverts if `_listingAddress` is set (`"Listing already set"`) or `listingAddress` is zero (`"Invalid listing address"`).
- **Gas Usage Controls**: Single state write.

### setTokens(address tokenA, address tokenB)
- **Parameters**: `tokenA` (address): First token. `tokenB` (address): Second token.
- **Behavior**: Sets `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`.
- **Internal Call Flow**: Validates tokens are unset, non-zero, and distinct. Calls `IERC20.decimals` for both tokens.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`.
- **Restrictions**: Reverts if tokens are set (`"Tokens already set"`), either is zero (`"Tokens must be ERC-20"`), or identical (`"Tokens must be different"`).
- **Gas Usage Controls**: Two external calls, minimal state writes.

### setAgent(address agent)
- **Parameters**: `agent` (address): `IOMFAgent` address.
- **Behavior**: Sets `_agent`.
- **Internal Call Flow**: Validates `_agent == 0` and `agent` non-zero, assigns `_agent`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_agent`.
- **Restrictions**: Reverts if `_agent` is set (`"Agent already set"`) or `agent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Single state write.

### update(address caller, UpdateType[] memory updates)
- **Parameters**: `caller` (address): Router address. `updates` (UpdateType[]): Array of balance, fee, or slot updates.
- **Behavior**: Updates liquidity balances, fees, or slots, setting `dFeesAcc` for new slots, syncing with agent, and emitting events.
- **Internal Call Flow**:
  - Iterates `updates`:
    - **Balance Update** (`updateType=0`): Updates `_liquidityDetail.xLiquid` or `yLiquid`.
    - **Fee Update** (`updateType=1`): Updates `_liquidityDetail.xFees` or `yFees`, emits `FeesUpdated`.
    - **xSlot Update** (`updateType=2`): Updates `_xLiquiditySlots`, `_activeXLiquiditySlots`, `_userIndex`, `_liquidityDetail.xLiquid`, sets `dFeesAcc` to `yFeesAcc`.
    - **ySlot Update** (`updateType=3`): Updates `_yLiquiditySlots`, `_activeYLiquiditySlots`, sets `dFeesAcc` to `xFeesAcc`.
  - Emits `LiquidityUpdated`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_liquidityDetail`, `_xLiquiditySlots`, `_yLiquiditySlots`, `_activeXLiquiditySlots`, `_activeYLiquiditySlots`, `_userIndex`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`.
- **Gas Usage Controls**: Single loop, pop-and-swap for removals, minimal external calls.

### deposit(address caller, address token, uint256 amount)
- **Parameters**: `caller` (address): Depositor. `token` (address): TokenA or tokenB. `amount` (uint256): Deposit amount.
- **Behavior**: Transfers tokens, updates slots with `dFeesAcc`, and syncs with agent and registry.
- **Internal Call Flow**:
  - Validates `token` (`_tokenA` or `_tokenB`), `caller` non-zero.
  - Checks pre/post balance for `IERC20.transferFrom`.
  - Normalizes `amount`, creates `UpdateType` for slot, calls `update`.
  - Calls `globalizeUpdate` and `updateRegistry`.
- **Balance Checks**: Verifies received amount via balance difference.
- **Mappings/Structs Used**: `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`, `_activeXLiquiditySlots`, `_activeYLiquiditySlots`, `_liquidityDetail`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on invalid token (`"Invalid token"`) or caller (`"Invalid caller"`).
- **Gas Usage Controls**: Single transfer, one `update` call, pop-and-swap in `update`.

### xPrepOut(address caller, uint256 amount, uint256 index)
- **Parameters**: `caller` (address): Depositor. `amount` (uint256): Withdrawal amount. `index` (uint256): xSlot index.
- **Behavior**: Prepares tokenA withdrawal, compensating with tokenB if there is a shortfall in available tokenA liquidity.
- **Internal Call Flow**:
  - Validates `caller`, `slot.depositor`, `slot.allocation >= amount`.
  - Calculates `withdrawAmountA` as the minimum of requested `amount` and available `_liquidityDetail.xLiquid`.
  - Computes `deficit` as any shortfall (`amount - withdrawAmountA`).
  - If `deficit` exists, fetches `currentPrice` from `IOMFListing.getPrice`, calculates `withdrawAmountB = (deficit * 1e18) / currentPrice`, capped by `_liquidityDetail.yLiquid`.
  - Returns `PreparedWithdrawal` with `amountA` and `amountB`.
- **Balance Checks**: `amount <= slot.allocation`, `withdrawAmountA <= xLiquid`, `withdrawAmountB <= yLiquid`.
- **Mappings/Structs Used**: `_liquidityDetail`, `_xLiquiditySlots`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on invalid caller (`"Invalid caller"`), depositor mismatch (`"Caller not depositor"`), insufficient allocation (`"Amount exceeds allocation"`), zero price (`"Price cannot be zero"`), or failed price fetch (`"Price fetch failed"`).
- **Gas Usage Controls**: One external call, minimal computation.

### xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**: `caller` (address): Depositor. `index` (uint256): xSlot index. `withdrawal` (PreparedWithdrawal): Withdrawal amounts.
- **Behavior**: Executes tokenA withdrawal, transferring tokens and syncing with agent/registry.
- **Internal Call Flow**:
  - Validates `caller`, `slot.depositor`.
  - Updates slot via `update`, transfers `amountA` and `amountB` via `IERC20.safeTransfer`.
  - Calls `globalizeUpdate` and `updateRegistry` for both tokens if needed.
- **Balance Checks**: None (checked in `xPrepOut`).
- **Mappings/Structs Used**: `_xLiquiditySlots`, `_liquidityDetail`, `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on invalid caller or depositor mismatch.
- **Gas Usage Controls**: Up to two transfers, two external calls, pop-and-swap in `update`.

### yPrepOut(address caller, uint256 amount, uint256 index)
- **Parameters**: Same as `xPrepOut` for tokenB.
- **Behavior**: Prepares tokenB withdrawal, compensating with tokenA if there is a shortfall in available tokenB liquidity.
- **Internal Call Flow**:
  - Validates `caller`, `slot.depositor`, `slot.allocation >= amount`.
  - Calculates `withdrawAmountB` as the minimum of requested `amount` and available `_liquidityDetail.yLiquid`.
  - Computes `deficit` as any shortfall (`amount - withdrawAmountB`).
  - If `deficit` exists, fetches `currentPrice` from `IOMFListing.getPrice`, calculates `withdrawAmountA = (deficit * currentPrice) / 1e18`, capped by `_liquidityDetail.xLiquid`.
  - Returns `PreparedWithdrawal` with `amountA` and `amountB`.
- **Balance Checks**: `amount <= slot.allocation`, `withdrawAmountB <= yLiquid`, `withdrawAmountA <= xLiquid`.
- **Mappings/Structs Used**: `_liquidityDetail`, `_yLiquiditySlots`.
- **Restrictions**: Same as `xPrepOut`.
- **Gas Usage Controls**: One external call, minimal computation.

### yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**: Same as `xExecuteOut` for tokenB.
- **Behavior**: Executes tokenB withdrawal, transferring tokens and syncing.
- **Internal Call Flow**: Similar to `xExecuteOut`, reversing token roles.
- **Balance Checks**: None (checked in `yPrepOut`).
- **Mappings/Structs Used**: `_yLiquiditySlots`, `_liquidityDetail`, `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`.
- **Restrictions**: Same as `xExecuteOut`.
- **Gas Usage Controls**: Up to two transfers, two external calls.

### claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 /* volume */)
- **Parameters**: `caller` (address): Depositor. `listingAddress` (address): Listing contract. `liquidityIndex` (uint256): Slot index. `isX` (bool): True for xSlot. `volume` (uint256): Ignored.
- **Behavior**: Claims fees based on `dFeesAcc`, updates state, resets `dFeesAcc` to current `yFeesAcc` (xSlot) or `xFeesAcc` (ySlot), and transfers tokens.
- **Internal Call Flow**:
  - Validates `listingAddress`, `caller`, `slot.depositor`, `yBalance > 0` via `IOMFListing.volumeBalanceView`.
  - Builds `FeeClaimContext`, calls `_processFeeClaim` to calculate `feeShare`, update state, reset `dFeesAcc`, and transfer tokens.
  - Emits `FeesClaimed`.
- **Balance Checks**: `yBalance > 0`, `slot.allocation > 0`.
- **Mappings/Structs Used**: `_liquidityDetail`, `_xLiquiditySlots`, `_yLiquiditySlots`, `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on invalid listing (`"Invalid listing address"`), caller (`"Invalid caller"`), depositor mismatch (`"Caller not depositor"`), or invalid listing (`"Invalid listing"`).
- **Gas Usage Controls**: One external call, one transfer, stack optimized via `FeeClaimContext`.

### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**: `caller` (address): Router. `token` (address): TokenA or tokenB. `amount` (uint256): Transfer amount. `recipient` (address): Receiver.
- **Behavior**: Transfers tokens, updates liquidity, and emits `LiquidityUpdated`.
- **Internal Call Flow**:
  - Validates `token`, normalizes `amount`.
  - Checks `_liquidityDetail.xLiquid` or `yLiquid` for sufficiency.
  - Transfers via `IERC20.safeTransfer`.
- **Balance Checks**: `xLiquid >= normalizedAmount` or `yLiquid >= normalizedAmount`.
- **Mappings/Structs Used**: `_liquidityDetail`, `_tokenA`, `_tokenB`, `_decimalA`, `_decimalB`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on invalid token (`"Invalid token"`) or insufficient liquidity (`"Insufficient xLiquid/yLiquid"`).
- **Gas Usage Controls**: Single transfer, minimal state writes.

### addFees(address caller, bool isX, uint256 fee)
- **Parameters**: `caller` (address): Router. `isX` (bool): True for tokenA fees. `fee` (uint256): Fee amount.
- **Behavior**: Increments `xFeesAcc` or `yFeesAcc`, updates fees via `update`, emits `FeesUpdated`.
- **Internal Call Flow**: Creates `UpdateType`, increments cumulative fees, calls `update`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_liquidityDetail`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`.
- **Gas Usage Controls**: Single `update` call.

### updateLiquidity(address caller, bool isX, uint256 amount)
- **Parameters**: `caller` (address): Router. `isX` (bool): True for tokenA. `amount` (uint256): Amount to deduct.
- **Behavior**: Deducts liquidity, emits `LiquidityUpdated`.
- **Internal Call Flow**: Validates `xLiquid` or `yLiquid`, updates `_liquidityDetail`.
- **Balance Checks**: `xLiquid >= amount` or `yLiquid >= amount`.
- **Mappings/Structs Used**: `_liquidityDetail`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on insufficient liquidity.
- **Gas Usage Controls**: Minimal state writes.

### changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**: `caller` (address): Current depositor. `isX` (bool): True for xSlot. `slotIndex` (uint256): Slot index. `newDepositor` (address): New depositor.
- **Behavior**: Transfers slot ownership, updates `_userIndex`, emits `SlotDepositorChanged`.
- **Internal Call Flow**: Validates `caller`, `newDepositor`, `slot.depositor`, `slot.allocation`. Updates slot and indices.
- **Balance Checks**: `slot.allocation > 0`.
- **Mappings/Structs Used**: `_xLiquiditySlots`, `_yLiquiditySlots`, `_userIndex`.
- **Restrictions**: Protected by `nonReentrant` and `onlyRouter`. Reverts on invalid caller (`"Invalid caller"`), new depositor (`"Invalid new depositor"`), depositor mismatch (`"Caller not depositor"`), or invalid slot (`"Invalid slot"`).
- **Gas Usage Controls**: Pop-and-swap for `_userIndex`, minimal writes.

### liquidityAmounts()
- **Parameters**: None.
- **Behavior**: Returns `_liquidityDetail.xLiquid` and `yLiquid`.
- **Internal Call Flow**: Reads `_liquidityDetail`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_liquidityDetail`.
- **Restrictions**: Implements `IOMFLiquidityTemplate`, view function.
- **Gas Usage Controls**: Minimal read.

### getListingAddress(uint256)
- **Parameters**: `listingId` (uint256): Ignored.
- **Behavior**: Returns `_listingAddress`.
- **Internal Call Flow**: Reads `_listingAddress`.
- **Balance Checks**: None.
- **Mappings/Structs Used**: `_listingAddress`.
- **Restrictions**: View function.
- **Gas Usage Controls**: Minimal read.

## View Functions
- **routersView(address router)**: Returns `_routers[router]`.
- **routersSetView()**: Returns `_routersSet`.
- **listingAddressView()**: Returns `_listingAddress`.
- **tokenAView()**: Returns `_tokenA`.
- **tokenBView()**: Returns `_tokenB`.
- **decimalAView()**: Returns `_decimalA`.
- **decimalBView()**: Returns `_decimalB`.
- **listingIdView()**: Returns `_listingId`.
- **agentView()**: Returns `_agent`.
- **liquidityDetailsView()**: Returns `_liquidityDetail` (xLiquid, yLiquid, xFees, yFees, xFeesAcc, yFeesAcc).
- **activeXLiquiditySlotsView()**: Returns `_activeXLiquiditySlots`.
- **activeYLiquiditySlotsView()**: Returns `_activeYLiquiditySlots`.
- **userIndexView(address user)**: Returns `_userIndex[user]`.
- **getXSlotView(uint256 index)**: Returns `_xLiquiditySlots[index]`.
- **getYSlotView(uint256 index)**: Returns `_yLiquiditySlots[index]`.

**Common View Function Details**:
- **Internal Call Flow**: Direct mapping/struct access.
- **Balance Checks**: None.
- **Restrictions**: View functions, minimal gas.
- **Gas Usage Controls**: Direct reads, no external calls.

## Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` for 18-decimal consistency.
- **Reentrancy Protection**: `nonReentrant` on state-modifying functions.
- **Gas Optimization**: Pop-and-swap for array removals, `FeeClaimContext` for stack efficiency.
- **Fee Tracking**: Uses `xFeesAcc`, `yFeesAcc` for cumulative fees, `dFeesAcc` for slot-specific fee baselines, reset to `yFeesAcc` (xSlot) or `xFeesAcc` (ySlot) after fee claims.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `FeesClaimed`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`.
- **Safety**: Try-catch for external calls, explicit casting, no inline assembly, graceful degradation in `globalizeUpdate` and `updateRegistry`.
- **Interface Compliance**: Implements `IOMFLiquidityTemplate`, integrates with `IOMFListing`, `IOMFAgent`, `ITokenRegistry`.

# OMFRouter Contract Documentation

## Overview
The `OMFRouter` contract, implemented in Solidity (`^0.8.2`), facilitates order creation, settlement, and liquidity management for a decentralized trading platform, incorporating a 0.05% fee and oracle-based pricing. It inherits functionality from `OMFSettlementPartial`, which extends `OMFOrderPartial` and `OMFMainPartial`, integrating with external interfaces (`IOMFListingTemplate`, `IOMFLiquidityTemplate`, `IOMFAgent`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles buy/sell order creation with fees, settlement, liquidity deposits, withdrawals, fee claims, depositor changes, and order cancellations, with rigorous gas optimization and safety mechanisms. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License:** BSL-1.1

**Version:** 0.0.81 (updated 2025-07-16)

**Inheritance Tree:** `OMFRouter` → `OMFSettlementPartial` → `OMFOrderPartial` → `OMFMainPartial`

## Mappings
- None explicitly defined in `OMFRouter`; relies on inherited functionality and external contract state (e.g., `listingContract` and `liquidityContract` mappings).

## Structs
- **OrderDetails**: Contains `recipientAddress` (address), `amount` (uint256, denormalized), `maxPrice` (uint256, normalized), `minPrice` (uint256, normalized).
- **OrderUpdate**: Contains `updateType` (uint8, 1 for buy, 2 for sell), `orderId` (uint256), `value` (uint256, normalized), `addr` (address, maker), `recipient` (address), `maxPrice` (uint256), `minPrice` (uint256), `amountSent` (uint256).
- **OrderContext**: Contains `listingContract` (IOMFListingTemplate), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **BuyOrderUpdateContext**: Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized, tokenA for buy).
- **SellOrderUpdateContext**: Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **PrepOrderUpdateResult**: Contains `makerAddress` (address), `recipientAddress` (address), `orderStatus` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized), `tokenDecimals` (uint8).
- **PayoutUpdate**: Contains `index` (uint256, payout order ID), `amount` (uint256, denormalized), `recipient` (address).

## Formulas
1. **Fee Calculation**:
   - **Formula**: `feeAmount = (inputAmount * 5) / 10000`
   - **Used in**: `_handleFeeAndAdd` (in `OMFOrderPartial`).
   - **Description**: Computes a 0.05% fee on the input amount for buy/sell orders, applied before transferring the net amount to the listing contract.
2. **Net Amount**:
   - **Formula**: `netAmount = inputAmount - feeAmount`
   - **Used in**: `_handleFeeAndTransfer` (in `OMFOrderPartial`).
   - **Description**: Calculates the principal amount after deducting the 0.05% fee, transferred to the listing contract.
3. **Buy Order Output**:
   - **Formula**: `amountOut = (inputAmount * 1e18) / price`
   - **Used in**: `_prepBuyLiquidUpdates`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenA, e.g., LINK for LINK/USD) for a buy order using the oracle price from `listingContract.getPrice`, with `inputAmount` (tokenB, e.g., USD) normalized to 1e18.
4. **Sell Order Output**:
   - **Formula**: `amountOut = (inputAmount * price) / 1e18`
   - **Used in**: `_prepSellLiquidUpdates`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenB, e.g., USD for LINK/USD) for a sell order using the oracle price from `listingContract.getPrice`, with `inputAmount` (tokenA, e.g., LINK) normalized to 1e18.

## External Functions

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New IOMFAgent address.
- **Behavior**: Updates `agent` state variable for listing validation.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable in `OMFMainPartial`): Stores IOMFAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### createBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `recipientAddress` (address): Order recipient.
  - `inputAmount` (uint256): Input amount (denormalized, tokenB, e.g., USD for LINK/USD).
  - `maxPrice` (uint256): Maximum price (normalized).
  - `minPrice` (uint256): Minimum price (normalized).
- **Behavior**: Creates a buy order, applying a 0.05% fee, transferring tokenB to the listing contract, and updating order state with `amountSent=0` via a call tree.
- **Internal Call Flow**:
  - Calls `prepAndTransfer` (in `OMFOrderPartial`):
    - Validates inputs and creates `OrderDetails` struct.
    - Computes fee via `_handleFeeAndAdd` (0.05% of `inputAmount`).
    - Transfers fee to liquidity contract and net amount to `listingAddress` via `_handleFeeAndTransfer` using `IERC20.transferFrom` and `IERC20.transfer`.
    - Chains to `prepOrderCore`, `prepOrderAmounts`, and `applyOrderUpdate` to create and apply `OrderUpdate` structs, invoking `listingContract.update`.
  - Transfer destinations: `liquidityAddr` (fee), `listingAddress` (net amount).
- **Balance Checks**:
  - **Pre-Balance Check**: Captures `listingAddress` and `liquidityAddr` balances before transfers.
  - **Post-Balance Check**: Ensures `postBalance > preBalance`, computes `amountReceived` and `actualNetAmount`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderDetails`, `OrderUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing` (uses `IOMFAgent.validateListing`).
  - Reverts if `recipient`, `amount`, or transfer fails, or fee addition fails.
- **Gas Usage Controls**: Call tree in `prepAndTransfer` reduces stack depth (~6 variables), single transfer pair, minimal array updates (2 `UpdateType` elements).

### createSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createBuyOrder`, but for sell orders with tokenA input (e.g., LINK for LINK/USD).
- **Behavior**: Creates a sell order, applying a 0.05% fee, transferring tokenA to the listing contract, with `amountSent=0`.
- **Internal Call Flow**:
  - Similar to `createBuyOrder`, using tokenA and `listingContract.decimals0View`.
  - `prepAndTransfer` handles fee and transfer, chaining to order updates.
- **Balance Checks**: Same as `createBuyOrder`.
- **Mappings/Structs Used**: Same as `createBuyOrder`.
- **Restrictions**: Same as `createBuyOrder`.
- **Gas Usage Controls**: Same as `createBuyOrder`.

### settleBuyOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles pending buy orders, transferring tokenA (e.g., LINK) to recipients, tracking `amountSent` (tokenA).
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `_processBuyOrder` for each order:
    - Fetches `(pendingAmount, filled, amountSent)` via `buyOrderAmountsView` with explicit destructuring.
    - Computes output via `_prepareLiquidityTransaction` using oracle price (`amountOut = (inputAmount * 1e18) / price`).
    - Calls `_prepBuyOrderUpdate` for tokenA transfer via `liquidityContract.transact`, with denormalized amounts.
    - Creates `UpdateType[]` via `_createBuyOrderUpdates`, including `amountSent`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - `_prepBuyOrderUpdate` ensures transfer success via try-catch.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `BuyOrderUpdateContext`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders with zero pending amount.
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing, `_processBuyOrder` reduces stack depth (~12 variables).

### settleSellOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles pending sell orders, transferring tokenB (e.g., USD) to recipients, tracking `amountSent` (tokenB).
- **Internal Call Flow**:
  - Similar to `settleBuyOrders`, using `pendingSellOrdersView[]` and `_processSellOrder`.
  - Computes `amountOut = (inputAmount * price) / 1e18` using oracle price.
  - Uses `_prepSellOrderUpdate` for tokenB transfers.
- **Balance Checks**: Same as `settleBuyOrders`.
- **Mappings/Structs Used**: Same as `settleBuyOrders`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyOrders`.
- **Gas Usage Controls**: Same as `settleBuyOrders`.

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles buy orders with liquidity pool, transferring tokenA (e.g., LINK) to recipients, updating liquidity (tokenB, e.g., USD), and tracking `amountSent` (tokenA).
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `executeSingleBuyLiquid`:
    - `_prepBuyLiquidUpdates` uses `_prepareLiquidityTransaction` to compute `amountOut` based on oracle price.
    - Transfers tokenA via `liquidityContract.transact`.
    - Updates liquidity via `_updateLiquidity` (tokenB, isX=false).
    - Creates `UpdateType[]` via `_createBuyOrderUpdates`, including `amountSent`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destinations: `recipientAddress` (tokenA), `liquidityAddr` (tokenB).
- **Balance Checks**:
  - `_checkAndTransferPrincipal` checks listing and liquidity balances pre/post transfer.
- **Mappings/Structs Used**:
  - **Structs**: `OrderContext`, `BuyOrderUpdateContext`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routersView(address(this))`.
  - Reverts if transfer or liquidity update fails.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays, try-catch error handling.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles sell orders with liquidity pool, transferring tokenB (e.g., USD), updating liquidity (tokenA, e.g., LINK), and tracking `amountSent` (tokenB).
- **Internal Call Flow**:
  - Similar to `settleBuyLiquid`, using `executeSingleSellLiquid` and `_prepSellLiquidUpdates`.
  - Computes `amountOut` using oracle price, transfers tokenB, updates liquidity (tokenA, isX=true).
- **Balance Checks**: Same as `settleBuyLiquid`.
- **Mappings/Structs Used**: Same as `settleBuyLiquid`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long position payouts, transferring tokenB (e.g., USD) to holders.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `settleSingleLongLiquid`:
    - Fetches payout details via `longPayoutDetailsView`.
    - Transfers `amount` via `liquidityContract.transact`.
    - Creates `PayoutUpdate[]` with payout details.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**:
  - Try-catch in `settleSingleLongLiquid` ensures transfer success.
- **Mappings/Structs Used**:
  - **Structs**: `PayoutUpdate`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routersView(address(this))`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Settles short position payouts, transferring tokenA (e.g., LINK) to holders.
- **Internal Call Flow**:
  - Similar to `settleLongPayouts`, using `shortPayoutByIndexView[]` and `settleSingleShortLiquid`.
- **Balance Checks**: Same as `settleLongPayouts`.
- **Mappings/Structs Used**: Same as `settleLongPayouts`.
- **Restrictions**: Same as `settleLongPayouts`.
- **Gas Usage Controls**: Same as `settleLongPayouts`.

### deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `isTokenA` (bool): True for tokenA (e.g., LINK), false for tokenB (e.g., USD).
  - `inputAmount` (uint256): Deposit amount (denormalized).
  - `user` (address): User depositing liquidity; must be non-zero (`require(caller != address(0), "Invalid caller")` in `liquidityContract.deposit`).
- **Behavior**: Deposits ERC-20 tokens to the liquidity pool on behalf of `user`, transferring tokens from `msg.sender` to `this`, then to `liquidityAddr`, updating `_xLiquiditySlots` or `_yLiquiditySlots` and `_liquidityDetail`.
- **Internal Call Flow**:
  - Validates `isTokenA` to select tokenA or tokenB via `token0View` or `baseTokenView`.
  - Transfers tokens via `IERC20.transferFrom` from `msg.sender` to `this`, with pre/post balance checks.
  - Approves `liquidityAddr` and calls `liquidityContract.deposit(user, tokenAddress, receivedAmount)`, which:
    - Validates `token` as `_tokenA` or `_tokenB`.
    - Transfers tokens to `liquidityContract`, normalizes amount, and updates slots via `update`.
    - Calls `globalizeUpdate` (to `IOMFAgent.globalizeLiquidity`) and `updateRegistry` (to `ITokenRegistry.initializeBalances`).
  - Transfer destinations: `this` (from `msg.sender`), `liquidityAddr` (from `this`).
- **Balance Checks**:
  - Pre/post balance checks in `OMFRouter` and `liquidityContract` for token transfers to handle fee-on-transfer tokens.
- **Mappings/Structs Used**: None in `OMFRouter`; `liquidityContract` uses `UpdateType`, `_xLiquiditySlots`, `_yLiquiditySlots`, `_liquidityDetail`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing` in `OMFRouter`, and `nonReentrant` and `onlyRouter` in `liquidityContract`.
  - Reverts if `user` is zero, `listingAddress` is invalid, token is invalid, or deposit fails (e.g., transfer or external call failure).
  - No depositor restriction, allowing any valid `user` to deposit via router.
- **Gas Usage Controls**: Single transfer and call, minimal state writes, try-catch for `globalizeUpdate` and `updateRegistry`.
- **External Dependencies**: `liquidityContract.deposit` calls `IOMFAgent.globalizeLiquidity` and `ITokenRegistry.initializeBalances`, handled with try-catch.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `isX` (bool): True for tokenA (e.g., LINK), false for tokenB (e.g., USD).
- **Behavior**: Withdraws liquidity from the pool for `msg.sender`, restricted to the slot’s depositor, preparing withdrawal with `xPrepOut` or `yPrepOut` (compensating with the opposite token if needed using `IOMFListing.getPrice`), then executing via `xExecuteOut` or `yExecuteOut`.
- **Internal Call Flow**:
  - Validates `msg.sender` as non-zero.
  - Calls `xPrepOut` or `yPrepOut` with `msg.sender` to prepare `PreparedWithdrawal`:
    - Validates `msg.sender` as slot depositor and `inputAmount` against slot allocation.
    - Fetches price via `IOMFListing.getPrice` for compensation.
  - Calls `xExecuteOut` or `yExecuteOut` with `msg.sender`:
    - Updates slot allocation via `update` (1 `UpdateType`).
    - Transfers tokens via `IERC20.safeTransfer`.
    - Calls `globalizeUpdate` (to `IOMFAgent.globalizeLiquidity`) and `updateRegistry` (to `ITokenRegistry.initializeBalances`).
  - Transfer destination: `msg.sender` (withdrawn tokens).
- **Balance Checks**: None in `OMFRouter`; `liquidityContract` checks liquidity availability and uses try-catch for price and external calls.
- **Mappings/Structs Used**: `PreparedWithdrawal`, `UpdateType` in `liquidityContract`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing` in `OMFRouter`, and `nonReentrant` and `onlyRouter` in `liquidityContract`.
  - Requires router registration in `liquidityContract.routersView(address(this))`.
  - Reverts if `msg.sender` is zero, not the slot depositor, `listingAddress` is invalid, `inputAmount` exceeds allocation, price fetch fails, or transfers fail.
- **Gas Usage Controls**: Two external calls (prep, execute), minimal updates (1 `UpdateType`), try-catch for external calls.
- **External Dependencies**: `liquidityContract` calls `IOMFListing.getPrice`, `IOMFAgent.globalizeLiquidity`, and `ITokenRegistry.initializeBalances`, handled with try-catch.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `liquidityIndex` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `isX` (bool): True for tokenA slot (e.g., LINK, claims yFees in tokenB), false for tokenB slot (e.g., USD, claims xFees in tokenA).
  - `volumeAmount` (uint256): Unused (legacy parameter, volume fetched from `volumeBalanceView`).
- **Behavior**: Claims fees for the slot for `msg.sender`, restricted to the slot’s depositor, converting fees to the provider’s token value (xSlots claim yFees in tokenB, ySlots claim xFees in tokenA) using `IOMFListing.getPrice`, transferring the converted amount to `msg.sender`.
- **Internal Call Flow**:
  - Validates `msg.sender` as non-zero and `listingAddress`.
  - Calls `liquidityContract.claimFees(msg.sender, listingAddress, liquidityIndex, isX, volumeAmount)`, which:
    - Validates `msg.sender` as the slot depositor.
    - Fetches volume via `IOMFListing.volumeBalanceView` and price via `IOMFListing.getPrice`.
    - Calls `_processFeeClaim` with `FeeClaimContext`:
      - Computes fee share based on slot allocation and volume.
      - Updates fees and slot via `update` (2 `UpdateType`).
      - Transfers converted fees via `IERC20.safeTransfer`.
  - Transfer destination: `msg.sender` (converted fee amount).
- **Balance Checks**: None in `OMFRouter`; `liquidityContract` uses try-catch for volume and price fetches.
- **Mappings/Structs Used**: `UpdateType`, `FeeClaimContext` in `liquidityContract`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing` in `OMFRouter`, and `nonReentrant` and `onlyRouter` in `liquidityContract`.
  - Requires router registration in `liquidityContract.routersView(address(this))`.
  - Reverts if `msg.sender` is zero, not the slot depositor, `listingAddress` is invalid, volume fetch fails, or price is zero (`require(currentPrice > 0, "Price cannot be zero")`).
- **Gas Usage Controls**: Two external calls (volume, price), minimal updates (2 `UpdateType`), try-catch for robustness.
- **External Dependencies**: `liquidityContract` calls `IOMFListing.volumeBalanceView` and `IOMFListing.getPrice`, handled with try-catch.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `orderIdentifier` (uint256): Order ID.
  - `isBuyOrder` (bool): True for buy (USD→LINK), false for sell (LINK→USD).
- **Behavior**: Cancels a single order, setting status to 0, restricted to the order maker (`msg.sender`).
- **Internal Call Flow**:
  - Validates `msg.sender` as the order maker via `buyOrderCoreView` or `sellOrderCoreView`.
  - Calls `_clearOrderData`:
    - Creates `UpdateType[]` to set order status to 0 via `listingContract.update`.
  - No direct transfers or refunds (handled by listing contract).
- **Balance Checks**: None.
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `msg.sender` is not the order maker or order is invalid (`makerAddress == address(0)`).
- **Gas Usage Controls**: Single update, minimal array (1 `UpdateType`).

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Cancels pending buy and sell orders for `msg.sender` up to `maxIterations`, using `makerPendingOrdersView` to fetch orders.
- **Internal Call Flow**:
  - Iterates `makerPendingOrdersView[]` up to `maxIterations`.
  - Validates order maker and status via `buyOrderCoreView` or `sellOrderCoreView`.
  - Calls `_clearOrderData` for each order.
- **Balance Checks**: None.
- **Mappings/Structs Used**: Same as `clearSingleOrder`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if orders are invalid or not owned by `msg.sender` (`makerBuy != msg.sender` or `sellStatus == 0`).
- **Gas Usage Controls**: `maxIterations` limits iteration, minimal updates per order (1 `UpdateType`).

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `listingAddress` (address): Listing contract address; must match `_listingAddress` in `liquidityContract`.
  - `isX` (bool): True for tokenA slot (e.g., LINK), false for tokenB slot (e.g., USD).
  - `slotIndex` (uint256): Slot index in `_xLiquiditySlots` or `_yLiquiditySlots`.
  - `newDepositor` (address): New slot owner; must be non-zero.
- **Behavior**: Changes the depositor for a liquidity slot for `msg.sender`, restricted to the slot’s depositor, updating `_userIndex` in `liquidityContract`.
- **Internal Call Flow**:
  - Validates `msg.sender` and `newDepositor` as non-zero.
  - Calls `liquidityContract.changeSlotDepositor(msg.sender, isX, slotIndex, newDepositor)`, which:
    - Validates `msg.sender` as the slot depositor and `newDepositor` as non-zero.
    - Updates slot depositor and `_userIndex`.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**: None in `OMFRouter`; `liquidityContract` uses `_userIndex`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing` in `OMFRouter`, and `nonReentrant` and `onlyRouter` in `liquidityContract`.
  - Requires router registration in `liquidityContract.routersView(address(this))`.
  - Reverts if `msg.sender` or `newDepositor` is zero, `msg.sender` is not the slot depositor, `listingAddress` is invalid, or slot allocation is zero (`require(slot.allocation > 0, "Invalid slot")`).
- **Gas Usage Controls**: Minimal, single external call and array operations.
- **External Dependencies**: None beyond `liquidityContract.changeSlotDepositor`.

## Additional Details
- **Fee Structure**: Applies a 0.05% fee on `inputAmount` for buy/sell orders, transferred to `liquidityAddr` via `_handleFeeAndTransfer`.
- **Oracle Pricing**: Uses `listingContract.getPrice` for buy/sell order output calculations (e.g., LINK/USD: buy USD→LINK, sell LINK→USD), replacing constant product formula used in `SSRouter`.
- **Decimal Handling**: Uses `normalize` and `denormalize` from `OMFMainPartial.sol` (1e18) for token amounts, fetched via `IERC20.decimals`, `listingContract.decimals0View`, or `baseTokenDecimalsView`. Ensures consistent precision across tokens.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Uses `maxIterations` to limit loops, dynamic arrays for updates, `_checkAndTransferPrincipal` for efficient transfers, call tree in `prepAndTransfer` to reduce stack depth (~6 variables in `createBuyOrder`/`createSellOrder`), and `_processBuy/SellOrder` (~12 variables).
- **Listing Validation**: Uses `onlyValidListing` modifier with `IOMFAgent.validateListing` checks to ensure listing integrity.
- **Router Restrictions**: Functions interacting with `liquidityContract` (e.g., `deposit`, `withdraw`, `claimFees`, `changeDepositor`, `settleBuy/SellLiquid`, `settleLong/ShortPayouts`) require `msg.sender` to be a registered router in `liquidityContract.routersView(address(this))`, ensuring only authorized routers can call these functions.
- **Order Cancellation**:
  - `clearSingleOrder`: Restricted to the order maker (`msg.sender`) via `buyOrderCoreView` or `sellOrderCoreView`.
  - `clearOrders`: Cancels only `msg.sender`’s orders, fetched via `makerPendingOrdersView`, ensuring no unauthorized cancellations.
- **Token Usage**:
  - Buy orders: Input tokenB (e.g., USD), output tokenA (e.g., LINK), `amountSent` tracks tokenA.
  - Sell orders: Input tokenA (e.g., LINK), output tokenB (e.g., USD), `amountSent` tracks tokenB.
  - Long payouts: Output tokenB (e.g., USD), no `amountSent`.
  - Short payouts: Output tokenA (e.g., LINK), no `amountSent`.
- **Events**: No events explicitly defined; relies on `listingContract` and `liquidityContract` events for logging.
- **Safety**:
  - Explicit casting used for all interface and address conversions (e.g., `IOMFListingTemplate(listingAddress)`).
  - No inline assembly, adhering to high-level Solidity for safety.
  - Try-catch blocks handle external call failures (e.g., transfers, liquidity updates, price fetches).
  - Hidden state variables accessed via unique view functions (e.g., `agentView`, `liquidityAddressView`, `makerPendingOrdersView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
  - Ensures graceful degradation with zero-length array returns on failure (e.g., `_prepBuyLiquidUpdates`).
  - Maker-only cancellation enforced in `clearSingleOrder` and `clearOrders` to prevent unauthorized order cancellations.
  - Call tree in `prepAndTransfer` minimizes stack usage, resolving prior stack-too-deep errors.
