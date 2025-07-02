# Marker Foundry : Pairing Contracts Documentation
The system is functionally a clone of ShockSpace, with only minor adjustments to MFPAgent and removal of drivers, this enables spot trading without leverage. 
Payout structs - mappings and functions are retained but are functionally useless.
It comprises of MFPAgent -  SSListingLogic - SSLiquidityLogic - SSLiquidityTemplate - SSListingTemplate and SSRouter

## SSLiquidityLogic Contract

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new SSLiquidityTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed SSLiquidityTemplate contract.

## SSListingLogic Contract

### Mappings and Arrays
- None defined in this contract.

### State Variables
- None defined in this contract.

### Functions

#### deploy
- **Parameters:**
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions:**
  - Deploys a new SSListingTemplate contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns:**
  - `address`: Address of the newly deployed SSListingTemplate contract.

## MFPAgent Contract

### Mappings and Arrays
- `getListing` (mapping - address, address, address): Maps tokenA to tokenB to the listing address for a trading pair.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed.
- `queryByAddress` (mapping - address, uint256[]): Maps a token to an array of listing IDs involving that token.
- `liquidityProviders` (mapping - uint256, address[]): Maps listing ID to an array of users who provided liquidity.
- `globalLiquidity` (mapping - address, address, address, uint256): Tracks liquidity per user for each tokenA-tokenB pair.
- `totalLiquidityPerPair` (mapping - address, address, uint256): Total liquidity for each tokenA-tokenB pair.
- `userTotalLiquidity` (mapping - address, uint256): Total liquidity contributed by each user across all pairs.
- `listingLiquidity` (mapping - uint256, address, uint256): Liquidity per user for each listing ID.
- `historicalLiquidityPerPair` (mapping - address, address, uint256, uint256): Historical liquidity for each tokenA-tokenB pair at specific timestamps.
- `historicalLiquidityPerUser` (mapping - address, address, address, uint256, uint256): Historical liquidity per user for each tokenA-tokenB pair at specific timestamps.
- `globalOrders` (mapping - address, address, uint256, GlobalOrder): Stores order details for each tokenA-tokenB pair by order ID.
- `pairOrders` (mapping - address, address, uint256[]): Array of order IDs for each tokenA-tokenB pair.
- `userOrders` (mapping - address, uint256[]): Array of order IDs created by each user.
- `historicalOrderStatus` (mapping - address, address, uint256, uint256, uint8): Historical status of orders for each tokenA-tokenB pair at specific timestamps.
- `userTradingSummaries` (mapping - address, address, address, uint256): Trading volume per user for each tokenA-tokenB pair.

### State Variables
- `routers` (address[]): Array of router addresses for operations, set post-deployment via addRouter.
- `listingLogicAddress` (address): Address of the SSListingLogic contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the SSLiquidityLogic contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.

### Functions

#### Setter Functions
- **addRouter**
  - **Parameters:**
    - `router` (address): Address to add to the routers array.
  - **Actions:**
    - Requires non-zero address and that the router does not already exist.
    - Appends the router to the routers array.
    - Emits RouterAdded event.
    - Restricted to owner via onlyOwner modifier.
- **removeRouter**
  - **Parameters:**
    - `router` (address): Address to remove from the routers array.
  - **Actions:**
    - Requires non-zero address and that the router exists.
    - Removes the router by swapping with the last element and popping the array.
    - Emits RouterRemoved event.
    - Restricted to owner via onlyOwner modifier.
- **getRouters**
  - **Actions:**
    - Returns the current array of router addresses.
  - **Returns:**
    - `address[]`: Array of router addresses.
- **setListingLogic**
  - **Parameters:**
    - `_listingLogic` (address): Address to set as the listing logic contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates listingLogicAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setLiquidityLogic**
  - **Parameters:**
    - `_liquidityLogic` (address): Address to set as the liquidity logic contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates liquidityLogicAddress state variable.
    - Restricted to owner via onlyOwner modifier.
- **setRegistry**
  - **Parameters:**
    - `_registryAddress` (address): Address to set as the registry contract.
  - **Actions:**
    - Requires non-zero address.
    - Updates registryAddress state variable.
    - Restricted to owner via onlyOwner modifier.

#### Listing Functions
- **listToken**
  - **Parameters:**
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
  - **Actions:**
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies routers array is non-empty, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract with routers array, listing ID, liquidity address, tokens, agent, and registry.
    - Calls _initializeLiquidity to set up liquidity contract with routers array, listing ID, listing address, tokens, and agent.
    - Calls _updateState to update mappings and arrays.
    - Emits ListingCreated event.
    - Increments listingCount.
  - **Returns:**
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **listNative**
  - **Parameters:**
    - `token` (address): Token to pair with native currency.
    - `isA` (bool): If true, native currency is tokenA; else, tokenB.
  - **Actions:**
    - Sets nativeAddress to address(0) for native currency.
    - Determines tokenA and tokenB based on isA.
    - Checks tokens are not identical and pair isn’t already listed.
    - Verifies routers array is non-empty, listingLogicAddress, liquidityLogicAddress, and registryAddress are set.
    - Calls _deployPair to create listing and liquidity contracts.
    - Calls _initializeListing to set up listing contract.
    - Calls _initializeLiquidity to set up liquidity contract.
    - Calls _updateState to update mappings and arrays.
    - Emits ListingCreated event.
    - Increments listingCount.
  - **Returns:**
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.

#### Liquidity Management Functions
- **globalizeLiquidity**
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `user` (address): User providing or removing liquidity.
    - `amount` (uint256): Liquidity amount to add or remove.
    - `isDeposit` (bool): True for deposit, false for withdrawal.
  - **Actions:**
    - Validates non-zero tokens, user, and valid listingId.
    - Retrieves listing address from caller (liquidity contract) via IMFLiquidityTemplate.
    - Verifies listing validity and details via isValidListing.
    - Confirms caller is the associated liquidity contract.
    - Calls _updateGlobalLiquidity to adjust liquidity mappings.
    - Emits GlobalLiquidityChanged event.
- **_updateGlobalLiquidity** (Internal)
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `user` (address): User providing or removing liquidity.
    - `amount` (uint256): Liquidity amount to add or remove.
    - `isDeposit` (bool): True for deposit, false for withdrawal.
  - **Actions:**
    - If isDeposit, adds amount to globalLiquidity, totalLiquidityPerPair, userTotalLiquidity, and listingLiquidity, and appends user to liquidityProviders if their liquidity was previously zero.
    - If not isDeposit, checks sufficient liquidity, then subtracts amount from mappings.
    - Updates historicalLiquidityPerPair and historicalLiquidityPerUser with current timestamp.
    - Emits GlobalLiquidityChanged event.
- **userExistsInProviders** (Internal)
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `user` (address): User to check.
  - **Actions:**
    - Checks if the user exists in the liquidityProviders array for the given listingId.
  - **Returns:**
    - `bool`: True if the user exists in liquidityProviders, false otherwise.
- **routerExists** (Internal)
  - **Parameters:**
    - `router` (address): Router address to check.
  - **Actions:**
    - Checks if the router exists in the routers array.
  - **Returns:**
    - `bool`: True if the router exists, false otherwise.

#### Order Management Functions
- **globalizeOrders**
  - **Parameters:**
    - `listingId` (uint256): ID of the listing.
    - `tokenA` (address): First token in the pair.
    - `tokenB` (address): Second token in the pair.
    - `orderId` (uint256): Unique order identifier.
    - `isBuy` (bool): True if buy order, false if sell.
    - `maker` (address): Address creating the order.
    - `recipient` (address): Address receiving the order outcome.
    - `amount` (uint256): Order amount.
    - `status` (uint8): Order status (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled).
  - **Actions:**
    - Validates non-zero tokens, maker, and valid listingId.
    - Checks caller is the listing contract via getListing.
    - If new order (maker is zero and status not cancelled), initializes GlobalOrder struct and adds orderId to pairOrders and userOrders.
    - If existing order, updates amount, status, and timestamp.
    - Updates historicalOrderStatus with current timestamp.
    - Adds amount to userTradingSummaries if non-zero.
    - Emits GlobalOrderChanged event.

#### View Functions
- **isValidListing**
  - **Parameters:**
    - `listingAddress` (address): Address to check.
  - **Actions:**
    - Iterates allListings to find matching address.
    - If found, retrieves tokenA and tokenB via IMFListingTemplate.getTokens.
    - Retrieves liquidity address via IMFListing.liquidityAddressView.
    - Constructs ListingDetails struct with listing details.
  - **Returns:**
    - `isValid` (bool): True if listing is valid.
    - `details` (ListingDetails): Struct with listingAddress, liquidityAddress, tokenA, tokenB, and listingId.
- **getPairLiquidityTrend**
  - **Parameters:**
    - `tokenA` (address): Token to focus on.
    - `focusOnTokenA` (bool): If true, tracks tokenA liquidity; else, tokenB.
    - `startTime` (uint256): Start timestamp for trend.
    - `endTime` (uint256): End timestamp for trend.
  - **Actions:**
    - Validates time range and non-zero tokenA.
    - If focusOnTokenA, checks historicalLiquidityPerPair for tokenA with first listed token.
    - Else, checks all tokenB pairings with tokenA.
    - Collects non-zero amounts into TrendData array.
    - Returns timestamps and amounts arrays.
  - **Returns:**
    - `timestamps` (uint256[]): Timestamps with liquidity changes.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityTrend**
  - **Parameters:**
    - `user` (address): User to track.
    - `focusOnTokenA` (bool): If true, tracks tokenA; else, tokenB.
    - `startTime` (uint256): Start timestamp for trend.
    - `endTime` (uint256): End timestamp for trend.
  - **Actions:**
    - Validates time range and non-zero user.
    - Iterates allListedTokens, checks historicalLiquidityPerUser for non-zero amounts.
    - Collects data into TrendData array.
    - Returns tokens, timestamps, and amounts arrays.
  - **Returns:**
    - `tokens` (address[]): Tokens involved in liquidity.
    - `timestamps` (uint256[]): Timestamps with liquidity changes.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityAcrossPairs**
  - **Parameters:**
    - `user` (address): User to track.
    - `maxIterations` (uint256): Maximum pairs to check.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits pairs to maxIterations or allListedTokens length.
    - Iterates allListedTokens, collects non-zero globalLiquidity amounts.
    - Returns tokenAs, tokenBs, and amounts arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `amounts` (uint256[]): Liquidity amounts.
- **getTopLiquidityProviders**
  - **Parameters:**
    - `listingId` (uint256): Listing ID to analyze.
    - `maxIterations` (uint256): Maximum users to return.
  - **Actions:**
    - Validates non-zero maxIterations and valid listingId.
    - Limits to maxIterations or liquidityProviders length for the listing.
    - Collects non-zero listingLiquidity amounts into TrendData array.
    - Sorts in descending order via _sortDescending.
    - Returns users and amounts arrays.
  - **Returns:**
    - `users` (address[]): Top liquidity providers.
    - `amounts` (uint256[]): Corresponding liquidity amounts.
- **getUserLiquidityShare**
  - **Parameters:**
    - `user` (address): User to check.
    - `tokenA` (address): First token in pair.
    - `tokenB` (address): Second token in pair.
  - **Actions:**
    - Retrieves total liquidity for the pair from totalLiquidityPerPair.
    - Gets user’s liquidity from globalLiquidity.
    - Calculates share as (userAmount * 1e18) / total if total is non-zero.
  - **Returns:**
    - `share` (uint256): User’s share of liquidity (scaled by 1e18).
    - `total` (uint256): Total liquidity for the pair.
- **getAllPairsByLiquidity**
  - **Parameters:**
    - `minLiquidity` (uint256): Minimum liquidity threshold.
    - `focusOnTokenA` (bool): If true, focuses on tokenA; else, tokenB.
    - `maxIterations` (uint256): Maximum pairs to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListedTokens length.
    - Collects pairs with totalLiquidityPerPair >= minLiquidity into TrendData array.
    - Returns tokenAs, tokenBs, and amounts arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `amounts` (uint256[]): Liquidity amounts.
- **getOrderActivityByPair**
  - **Parameters:**
    - `tokenA` (address): First token in pair.
    - `tokenB` (address): Second token in pair.
    - `startTime` (uint256): Start timestamp for activity.
    - `endTime` (uint256): End timestamp for activity.
  - **Actions:**
    - Validates time range and non-zero tokens.
    - Retrieves order IDs from pairOrders.
    - Filters globalOrders by timestamp range, constructs OrderData array.
    - Returns orderIds and orders arrays.
  - **Returns:**
    - `orderIds` (uint256[]): IDs of orders in the range.
    - `orders` (OrderData[]): Array of order details.
- **getUserTradingProfile**
  - **Parameters:**
    - `user` (address): User to profile.
  - **Actions:**
    - Iterates allListedTokens, collects non-zero trading volumes from userTradingSummaries.
    - Returns tokenAs, tokenBs, and volumes arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `volumes` (uint256[]): Trading volumes.
- **getTopTradersByVolume**
  - **Parameters:**
    - `listingId` (uint256): Listing ID to analyze.
    - `maxIterations` (uint256): Maximum traders to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListings length.
    - Identifies tokenA for each listing, collects non-zero trading volumes from userTradingSummaries.
    - Sorts in descending order via _sortDescending.
    - Returns traders and volumes arrays.
  - **Returns:**
    - `traders` (address[]): Top traders.
    - `volumes` (uint256[]): Corresponding trading volumes.
- **getAllPairsByOrderVolume**
  - **Parameters:**
    - `minVolume` (uint256): Minimum order volume threshold.
    - `focusOnTokenA` (bool): If true, focuses on tokenA; else, tokenB.
    - `maxIterations` (uint256): Maximum pairs to return.
  - **Actions:**
    - Validates non-zero maxIterations.
    - Limits to maxIterations or allListedTokens length.
    - Calculates total volume per pair from globalOrders via pairOrders.
    - Collects pairs with volume >= minVolume into TrendData array.
    - Returns tokenAs, tokenBs, and volumes arrays.
  - **Returns:**
    - `tokenAs` (address[]): First tokens in pairs.
    - `tokenBs` (address[]): Second tokens in pairs.
    - `volumes` (uint256[]): Order volumes.
- **queryByIndex**
  - **Parameters:**
    - `index` (uint256): Index to query.
  - **Actions:**
    - Validates index is within allListings length.
    - Retrieves listing address from allListings array.
  - **Returns:**
    - `address`: Listing address at the index.
- **queryByAddressView**
  - **Parameters:**
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions:**
    - Retrieves indices from queryByAddress mapping.
    - Calculates start and end bounds based on step and maxIteration.
    - Returns a subset of indices for pagination.
  - **Returns:**
    - `uint256[]`: Array of listing IDs for the target token.
- **queryByAddressLength**
  - **Parameters:**
    - `target` (address): Token to query.
  - **Actions:**
    - Retrieves length of queryByAddress array for the target token.
  - **Returns:**
    - `uint256`: Number of listing IDs for the target token.
- **allListingsLength**
  - **Actions:**
    - Retrieves length of allListings array.
  - **Returns:**
    - `uint256`: Total number of listings.
- **allListedTokensLength**
  - **Actions:**
    - Retrieves length of allListedTokens array.
  - **Returns:**
    - `uint256`: Total number of listed tokens.

# SSListingTemplate Documentation

## Overview
The `SSListingTemplate` contract, implemented in Solidity (^0.8.2), forms part of a decentralized trading platform. `SSListingTemplate` manages buy/sell orders, payouts, and volume balances, it inherits `ReentrancyGuard` for security and use `SafeERC20` for token operations, integrating with `ISSAgent` and `ITokenRegistry` for global updates and synchronization. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contracts avoid reserved keywords, use explicit casting, and ensure graceful degradation.

**SPDX License**: BSD-3-Clause

**Version**: 0.0.10 (Updated 2025-06-23)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set, prevents re-setting.
- **`tokenX`**: `address private` - Address of token X (or ETH if zero).
- **`tokenY`**: `address private` - Address of token Y (or ETH if zero).
- **`decimalX`**: `uint8 private` - Decimals of token X (18 for ETH).
- **`decimalY`**: `uint8 private` - Decimals of token Y (18 for ETH).
- **`listingId`**: `uint256 public` - Unique identifier for the listing.
- **`agent`**: `address public` - Address of the agent contract for global updates.
- **`registryAddress`**: `address public` - Address of the token registry contract.
- **`liquidityAddress`**: `address public` - Address of the liquidity contract.
- **`nextOrderId`**: `uint256 public` - Next available order ID for payouts/orders.
- **`lastDayFee`**: `LastDayFee public` - Stores `xFees`, `yFees`, and `timestamp` for daily fee tracking.
- **`volumeBalance`**: `VolumeBalance public` - Stores `xBalance`, `yBalance`, `xVolume`, `yVolume`.
- **`price`**: `uint256 public` - Current price, calculated as `(xBalance * 1e18) / yBalance`.
- **`pendingBuyOrders`**: `uint256[] public` - Array of pending buy order IDs.
- **`pendingSellOrders`**: `uint256[] public` - Array of pending sell order IDs.
- **`longPayoutsByIndex`**: `uint256[] public` - Array of long payout order IDs.
- **`shortPayoutsByIndex`**: `uint256[] public` - Array of short payout order IDs.
- **`historicalData`**: `HistoricalData[] public` - Array of historical market data.

### Mappings
- **`routers`**: `mapping(address => bool)` - Maps addresses to authorized routers.
- **`buyOrderCores`**: `mapping(uint256 => BuyOrderCore)` - Maps order ID to buy order core data (`makerAddress`, `recipientAddress`, `status`).
- **`buyOrderPricings`**: `mapping(uint256 => BuyOrderPricing)` - Maps order ID to buy order pricing (`maxPrice`, `minPrice`).
- **`buyOrderAmounts`**: `mapping(uint256 => BuyOrderAmounts)` - Maps order ID to buy order amounts (`pending`, `filled`, `amountSent`).
- **`sellOrderCores`**: `mapping(uint256 => SellOrderCore)` - Maps order ID to sell order core data (`makerAddress`, `recipientAddress`, `status`).
- **`sellOrderPricings`**: `mapping(uint256 => SellOrderPricing)` - Maps order ID to sell order pricing (`maxPrice`, `minPrice`).
- **`sellOrderAmounts`**: `mapping(uint256 => SellOrderAmounts)` - Maps order ID to sell order amounts (`pending`, `filled`, `amountSent`).
- **`longPayouts`**: `mapping(uint256 => LongPayoutStruct)` - Maps order ID to long payout data (`makerAddress`, `recipientAddress`, `required`, `filled`, `orderId`, `status`).
- **`shortPayouts`**: `mapping(uint256 => ShortPayoutStruct)` - Maps order ID to short payout data (`makerAddress`, `recipientAddress`, `amount`, `filled`, `orderId`, `status`).
- **`makerPendingOrders`**: `mapping(address => uint256[])` - Maps maker address to their pending order IDs.
- **`userPayoutIDs`**: `mapping(address => uint256[])` - Maps user address to their payout order IDs.

### Structs
1. **LastDayFee**:
   - `xFees`: `uint256` - Token X fees at start of day.
   - `yFees`: `uint256` - Token Y fees at start of day.
   - `timestamp`: `uint256` - Timestamp of last fee update.

2. **VolumeBalance**:
   - `xBalance`: `uint256` - Normalized balance of token X.
   - `yBalance`: `uint256` - Normalized balance of token Y.
   - `xVolume`: `uint256` - Normalized trading volume of token X.
   - `yVolume`: `uint256` - Normalized trading volume of token Y.

3. **BuyOrderCore**:
   - `makerAddress`: `address` - Address of the order creator.
   - `recipientAddress`: `address` - Address to receive tokens.
   - `status`: `uint8` - Order status (0=cancelled, 1=pending, 2=partially filled, 3=filled).

4. **BuyOrderPricing**:
   - `maxPrice`: `uint256` - Maximum acceptable price (normalized).
   - `minPrice`: `uint256` - Minimum acceptable price (normalized).

5. **BuyOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenY).
   - `filled`: `uint256` - Normalized filled amount (tokenY).
   - `amountSent`: `uint256` - Normalized amount of tokenX sent during settlement.

6. **SellOrderCore**:
   - Same as `BuyOrderCore` for sell orders.

7. **SellOrderPricing**:
   - Same as `BuyOrderPricing` for sell orders.

8. **SellOrderAmounts**:
   - `pending`: `uint256` - Normalized pending amount (tokenX).
   - `filled`: `uint256` - Normalized filled amount (tokenX).
   - `amountSent`: `uint256` - Normalized amount of tokenY sent during settlement.

9. **PayoutUpdate**:
   - `payoutType`: `uint8` - Type of payout (0=long, 1=short).
   - `recipient`: `address` - Address to receive payout.
   - `required`: `uint256` - Normalized amount required.

10. **LongPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `required`: `uint256` - Normalized amount required (tokenY).
    - `filled`: `uint256` - Normalized amount filled (tokenY).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).

11. **ShortPayoutStruct**:
    - `makerAddress`: `address` - Address of the payout creator.
    - `recipientAddress`: `address` - Address to receive payout.
    - `amount`: `uint256` - Normalized payout amount (tokenX).
    - `filled`: `uint256` - Normalized amount filled (tokenX).
    - `orderId`: `uint256` - Unique payout order ID.
    - `status`: `uint8` - Payout status (0=pending, others undefined).

12. **HistoricalData**:
    - `price`: `uint256` - Market price at timestamp (normalized).
    - `xBalance`: `uint256` - Token X balance (normalized).
    - `yBalance`: `uint256` - Token Y balance (normalized).
    - `xVolume`: `uint256` - Token X volume (normalized).
    - `yVolume`: `uint256` - Token Y volume (normalized).
    - `timestamp`: `uint256` - Time of data snapshot.

13. **UpdateType**:
    - `updateType`: `uint8` - Update type (0=balance, 1=buy order, 2=sell order, 3=historical).
    - `structId`: `uint8` - Struct to update (0=core, 1=pricing, 2=amounts).
    - `index`: `uint256` - Order ID or balance index (0=xBalance, 1=yBalance, 2=xVolume, 3=yVolume).
    - `value`: `uint256` - Normalized amount or price.
    - `addr`: `address` - Maker address.
    - `recipient`: `address` - Recipient address.
    - `maxPrice`: `uint256` - Max price or packed xBalance/yBalance (historical).
    - `minPrice`: `uint256` - Min price or packed xVolume/yVolume (historical).
    - `amountSent`: `uint256` - Normalized amount of opposite token sent during settlement.

### Formulas
1. **Price Calculation**:
   - **Formula**: `price = (xBalance * 1e18) / yBalance`
   - **Used in**: `update`, `transact`
   - **Description**: Computes current price when `xBalance` and `yBalance` are non-zero, used for order pricing and historical data.

2. **Daily Yield**:
   - **Formula**: `dailyYield = ((feeDifference * 0.0005) * 1e18) / liquidity * 365`
   - **Used in**: `queryYield`
   - **Description**: Calculates annualized yield from `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`), using 0.05% fee rate and liquidity from `SSLiquidityTemplate`.

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet` to true.
- **Restrictions**: Reverts if `routersSet` is true or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` - Listing ID.
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setLiquidityAddress(address _liquidityAddress)
- **Parameters**: `_liquidityAddress` - Liquidity contract address.
- **Behavior**: Sets `liquidityAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `liquidityAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` - Token addresses.
- **Behavior**: Sets `tokenX`, `tokenY`, `decimalX`, `decimalY`, callable once.
- **Internal Call Flow**: Fetches decimals via `IERC20.decimals` (18 for ETH).
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes and external calls.

#### setAgent(address _agent)
- **Parameters**: `_agent` - Agent contract address.
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setRegistry(address _registryAddress)
- **Parameters**: `_registryAddress` - Registry contract address.
- **Behavior**: Sets `registryAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `registryAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - Router address.
  - `updates` - Array of update structs.
- **Behavior**: Updates balances, orders, or historical data, triggers `globalizeUpdate`.
- **Internal Call Flow**:
  - Checks `volumeUpdated` to update `lastDayFee` if new day.
  - Processes `updates`:
    - `updateType=0`: Updates `xBalance`, `yBalance`, `xVolume`, `yVolume`.
    - `updateType=1`: Updates buy order `core`, `pricing`, or `amounts` (including `amountSent` for tokenX), adjusts `pendingBuyOrders`, `makerPendingOrders`, `yBalance`, `yVolume`, `xBalance`.
    - `updateType=2`: Updates sell order `core`, `pricing`, or `amounts` (including `amountSent` for tokenY), adjusts `pendingSellOrders`, `makerPendingOrders`, `xBalance`, `xVolume`, `yBalance`.
    - `updateType=3`: Adds `HistoricalData` with packed balances/volumes.
  - Updates `price`, calls `globalizeUpdate`, emits `BalancesUpdated` or `OrderUpdated`.
- **Balance Checks**: Ensures sufficient `xBalance`/`yBalance` for order updates, adjusts for `amountSent`.
- **Mappings/Structs Used**:
  - **Mappings**: `buyOrderCores`, `buyOrderPricings`, `buyOrderAmounts`, `sellOrderCores`, `sellOrderPricings`, `sellOrderAmounts`, `pendingBuyOrders`, `pendingSellOrders`, `makerPendingOrders`, `historicalData`.
  - **Structs**: `UpdateType`, `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`, `HistoricalData`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, emits events for updates.

#### ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates)
- **Parameters**:
  - `caller` - Router address.
  - `payoutUpdates` - Array of payout updates.
- **Behavior**: Creates long/short payout orders, increments `nextOrderId`.
- **Internal Call Flow**:
  - Creates `LongPayoutStruct` (tokenY) or `ShortPayoutStruct` (tokenX), updates `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - Increments `nextOrderId`, emits `PayoutOrderCreated`.
- **Balance Checks**: None, defers to `transact`.
- **Mappings/Structs Used**:
  - **Mappings**: `longPayouts`, `shortPayouts`, `longPayoutsByIndex`, `shortPayoutsByIndex`, `userPayoutIDs`.
  - **Structs**: `PayoutUpdate`, `LongPayoutStruct`, `ShortPayoutStruct`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`.
- **Gas Usage Controls**: Loop over `payoutUpdates`, dynamic arrays, minimal state writes.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - Router address.
  - `token` - TokenX or tokenY.
  - `amount` - Denormalized amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers tokens/ETH, updates balances, and registry.
- **Internal Call Flow**:
  - Normalizes `amount` using `decimalX` or `decimalY`.
  - Checks `xBalance` (tokenX) or `yBalance` (tokenY).
  - Transfers via `SafeERC20.safeTransfer` or ETH call with try-catch.
  - Updates `xVolume`/`yVolume`, `lastDayFee`, `price`.
  - Calls `_updateRegistry`, emits `BalancesUpdated`.
- **Balance Checks**: Pre-transfer balance check for `xBalance` or `yBalance`.
- **Mappings/Structs Used**:
  - **Mappings**: `volumeBalance`.
  - **Structs**: `VolumeBalance`.
- **Restrictions**: `nonReentrant`, requires `routers[caller]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch error handling.

#### queryYield(bool isA, uint256 maxIterations)
- **Parameters**:
  - `isA` - True for tokenX, false for tokenY.
  - `maxIterations` - Max historical data iterations.
- **Behavior**: Returns annualized yield based on daily fees.
- **Internal Call Flow**:
  - Checks `lastDayFee.timestamp`, ensures same-day calculation.
  - Computes `feeDifference` (`xVolume - lastDayFee.xFees` or `yVolume - lastDayFee.yFees`).
  - Fetches liquidity (`xLiquid` or `yLiquid`) via `ISSLiquidityTemplate.liquidityAmounts`.
  - Calculates `dailyYield = (feeDifference * 0.0005 * 1e18) / liquidity * 365`.
- **Balance Checks**: None, relies on external `liquidityAmounts` call.
- **Mappings/Structs Used**:
  - **Mappings**: `volumeBalance`, `lastDayFee`.
  - **Structs**: `LastDayFee`, `VolumeBalance`.
- **Restrictions**: Reverts if `maxIterations` is zero or no historical data/same-day timestamp.
- **Gas Usage Controls**: Minimal, single external call, try-catch for `liquidityAmounts`.

#### prices(uint256) view returns (uint256)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns current `price`.
- **Gas Usage Controls**: Minimal, single state read.

#### volumeBalances(uint256) view returns (uint256 xBalance, uint256 yBalance)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `xBalance`, `yBalance` from `volumeBalance`.
- **Mappings/Structs Used**: `volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### liquidityAddressView(uint256) view returns (address)
- **Parameters**: Ignored listing ID.
- **Behavior**: Returns `liquidityAddress`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenA() view returns (address)
- **Behavior**: Returns `tokenX`.
- **Gas Usage Controls**: Minimal, single state read.

#### tokenB() view returns (address)
- **Behavior**: Returns `tokenY`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsA() view returns (uint8)
- **Behavior**: Returns `decimalX`.
- **Gas Usage Controls**: Minimal, single state read.

#### decimalsB() view returns (uint8)
- **Behavior**: Returns `decimalY`.
- **Gas Usage Controls**: Minimal, single state read.

#### getListingId() view returns (uint256)
- **Behavior**: Returns `listingId`.
- **Gas Usage Controls**: Minimal, single state read.

#### getNextOrderId() view returns (uint256)
- **Behavior**: Returns `nextOrderId`.
- **Gas Usage Controls**: Minimal, single state read.

#### listingVolumeBalancesView() view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume)
- **Behavior**: Returns all fields from `volumeBalance`.
- **Mappings/Structs Used**: `volumeBalance` (`VolumeBalance`).
- **Gas Usage Controls**: Minimal, single state read.

#### listingPriceView() view returns (uint256)
- **Behavior**: Returns `price`.
- **Gas Usage Controls**: Minimal, single state read.

#### pendingBuyOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `pendingBuyOrders`.
- **Mappings/Structs Used**: `pendingBuyOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### pendingSellOrdersView() view returns (uint256[] memory)
- **Behavior**: Returns `pendingSellOrders`.
- **Mappings/Structs Used**: `pendingSellOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### makerPendingOrdersView(address maker) view returns (uint256[] memory)
- **Parameters**: `maker` - Maker address.
- **Behavior**: Returns maker's pending order IDs.
- **Mappings/Structs Used**: `makerPendingOrders`.
- **Gas Usage Controls**: Minimal, array read.

#### longPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `longPayoutsByIndex`.
- **Mappings/Structs Used**: `longPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### shortPayoutByIndexView() view returns (uint256[] memory)
- **Behavior**: Returns `shortPayoutsByIndex`.
- **Mappings/Structs Used**: `shortPayoutsByIndex`.
- **Gas Usage Controls**: Minimal, array read.

#### userPayoutIDsView(address user) view returns (uint256[] memory)
- **Parameters**: `user` - User address.
- **Behavior**: Returns user's payout order IDs.
- **Mappings/Structs Used**: `userPayoutIDs`.
- **Gas Usage Controls**: Minimal, array read.

#### getLongPayout(uint256 orderId) view returns (LongPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `LongPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `longPayouts` (`LongPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getShortPayout(uint256 orderId) view returns (ShortPayoutStruct memory)
- **Parameters**: `orderId` - Payout order ID.
- **Behavior**: Returns `ShortPayoutStruct` for given `orderId`.
- **Mappings/Structs Used**: `shortPayouts` (`ShortPayoutStruct`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `buyOrderCores` (`BuyOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `buyOrderPricings` (`BuyOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getBuyOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Buy order ID.
- **Behavior**: Returns fields from `buyOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenX).
- **Mappings/Structs Used**: `buyOrderAmounts` (`BuyOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderCore(uint256 orderId) view returns (address makerAddress, address recipientAddress, uint8 status)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderCores[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `sellOrderCores` (`SellOrderCore`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderPricing(uint256 orderId) view returns (uint256 maxPrice, uint256 minPrice)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderPricings[orderId]` with explicit destructuring.
- **Mappings/Structs Used**: `sellOrderPricings` (`SellOrderPricing`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getSellOrderAmounts(uint256 orderId) view returns (uint256 pending, uint256 filled, uint256 amountSent)
- **Parameters**: `orderId` - Sell order ID.
- **Behavior**: Returns fields from `sellOrderAmounts[orderId]` with explicit destructuring, including `amountSent` (tokenY).
- **Mappings/Structs Used**: `sellOrderAmounts` (`SellOrderAmounts`).
- **Gas Usage Controls**: Minimal, single mapping read.

#### getHistoricalDataView(uint256 index) view returns (HistoricalData memory)
- **Parameters**: `index` - Historical data index.
- **Behavior**: Returns `HistoricalData` at given index.
- **Mappings/Structs Used**: `historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if `index` is invalid.
- **Gas Usage Controls**: Minimal, single array read.

#### historicalDataLengthView() view returns (uint256)
- **Behavior**: Returns length of `historicalData`.
- **Mappings/Structs Used**: `historicalData`.
- **Gas Usage Controls**: Minimal, single state read.

#### getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) view returns (HistoricalData memory)
- **Parameters**: `targetTimestamp` - Target timestamp.
- **Behavior**: Returns `HistoricalData` with timestamp closest to `targetTimestamp`.
- **Mappings/Structs Used**: `historicalData` (`HistoricalData`).
- **Restrictions**: Reverts if no historical data exists.
- **Gas Usage Controls**: Loop over `historicalData`, minimal state reads.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals` or `decimalX`/`decimalY`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, try-catch for external calls (`globalizeOrders`, `initializeBalances`, `liquidityAmounts`).
- **Token Usage**:
  - Buy orders: Input tokenY, output tokenX, `amountSent` tracks tokenX.
  - Sell orders: Input tokenX, output tokenY, `amountSent` tracks tokenY.
  - Long payouts: Output tokenY, no `amountSent`.
  - Short payouts: Output tokenX, no `amountSent`.
- **Events**: `OrderUpdated`, `PayoutOrderCreated`, `BalancesUpdated`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ISSListingTemplate`, `IERC20`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls to handle failures gracefully.
  - Hidden state variables (`tokenX`, `tokenY`, `decimalX`, `decimalY`) accessed via view functions.
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
- **Compatibility**: Aligned with `SSRouter` (v0.0.48), `SSAgent` (v0.0.2), `SSLiquidityTemplate` (v0.0.6), `SSOrderPartial` (v0.0.18).

# SSLiquidityTemplate Documentation

## Overview
The `SSLiquidityTemplate`, implemented in Solidity (^0.8.2), forms part of a decentralized trading platform, handling liquidity deposits, withdrawals, and fee claims. It inherits `ReentrancyGuard` for security and uses `SafeERC20` for token operations, integrating with `ISSAgent` and `ITokenRegistry` for global updates and synchronization. State variables are private, accessed via view functions with unique names, and amounts are normalized to 1e18 for precision across token decimals. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License**: BSD-3-Clause

**Version**: 0.0.13 (Updated 2025-06-30)

### State Variables
- **`routersSet`**: `bool public` - Tracks if routers are set, prevents re-setting.
- **`listingAddress`**: `address public` - Address of the listing contract.
- **`tokenA`**: `address public` - Address of token A (or ETH if zero).
- **`tokenB`**: `address public` - Address of token B (or ETH if zero).
- **`listingId`**: `uint256 public` - Unique identifier for the listing.
- **`agent`**: `address public` - Address of the agent contract for global updates.
- **`liquidityDetail`**: `LiquidityDetails public` - Stores `xLiquid`, `yLiquid`, `xFees`, `yFees`, `xFeesAcc`, `yFeesAcc`.
- **`activeXLiquiditySlots`**: `uint256[] public` - Array of active xSlot indices.
- **`activeYLiquiditySlots`**: `uint256[] public` - Array of active ySlot indices.

### Mappings
- **`routers`**: `mapping(address => bool)` - Maps addresses to authorized routers.
- **`xLiquiditySlots`**: `mapping(uint256 => Slot)` - Maps slot index to token A slot data.
- **`yLiquiditySlots`**: `mapping(uint256 => Slot)` - Maps slot index to token B slot data.
- **`userIndex`**: `mapping(address => uint256[])` - Maps user address to their slot indices.

### Structs
1. **LiquidityDetails**:
   - `xLiquid`: `uint256` - Normalized liquidity for token A.
   - `yLiquid`: `uint256` - Normalized liquidity for token B.
   - `xFees`: `uint256` - Normalized fees for token A.
   - `yFees`: `uint256` - Normalized fees for token B.
   - `xFeesAcc`: `uint256` - Cumulative fee volume for token A.
   - `yFeesAcc`: `uint256` - Cumulative fee volume for token B.

2. **Slot**:
   - `depositor`: `address` - Address of the slot owner.
   - `recipient`: `address` - Unused recipient address.
   - `allocation`: `uint256` - Normalized liquidity allocation.
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit or last claim (yFeesAcc for xSlots, xFeesAcc for ySlots).
   - `timestamp`: `uint256` - Slot creation timestamp.

3. **UpdateType**:
   - `updateType`: `uint8` - Update type (0=balance, 1=fees, 2=xSlot, 3=ySlot).
   - `index`: `uint256` - Index (0=xFees/xLiquid, 1=yFees/yLiquid, or slot index).
   - `value`: `uint256` - Normalized amount or allocation.
   - `addr`: `address` - Depositor address.
   - `recipient`: `address` - Unused recipient address.

4. **PreparedWithdrawal**:
   - `amountA`: `uint256` - Normalized withdrawal amount for token A.
   - `amountB`: `uint256` - Normalized withdrawal amount for token B.

5. **FeeClaimContext**:
   - `caller`: `address` - User address.
   - `isX`: `bool` - True for token A, false for token B.
   - `liquid`: `uint256` - Total liquidity (xLiquid or yLiquid).
   - `allocation`: `uint256` - Slot allocation.
   - `fees`: `uint256` - Available fees (yFees for xSlots, xFees for ySlots).
   - `dFeesAcc`: `uint256` - Cumulative fees at deposit or last claim.
   - `liquidityIndex`: `uint256` - Slot index.

### Formulas
1. **Fee Share**:
   - **Formula**: 
     ```
     contributedFees = feesAcc - dFeesAcc
     liquidityContribution = (allocation * 1e18) / liquid
     feeShare = (contributedFees * liquidityContribution) / 1e18
     feeShare = feeShare > fees ? fees : feeShare
     ```
   - **Used in**: `_claimFeeShare`
   - **Description**: Computes fee share for a liquidity slot based on accumulated fees since deposit or last claim (`feesAcc` is `yFeesAcc` for xSlots, `xFeesAcc` for ySlots) and liquidity proportion, capped at available fees (`yFees` for xSlots, `xFees` for ySlots).

### External Functions
#### setRouters(address[] memory _routers)
- **Parameters**: `_routers` - Array of router addresses.
- **Behavior**: Sets authorized routers, callable once.
- **Internal Call Flow**: Updates `routers` mapping, sets `routersSet`.
- **Restrictions**: Reverts if `routersSet` is true or `_routers` is empty/invalid.
- **Gas Usage Controls**: Single loop, minimal state writes.

#### setListingId(uint256 _listingId)
- **Parameters**: `_listingId` - Listing ID.
- **Behavior**: Sets `listingId`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingId` already set.
- **Gas Usage Controls**: Minimal, single state write.

#### setListingAddress(address _listingAddress)
- **Parameters**: `_listingAddress` - Listing contract address.
- **Behavior**: Sets `listingAddress`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `listingAddress` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### setTokens(address _tokenA, address _tokenB)
- **Parameters**: `_tokenA`, `_tokenB` - Token addresses.
- **Behavior**: Sets `tokenA`, `tokenB`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if tokens already set, same, or both zero.
- **Gas Usage Controls**: Minimal, state writes.

#### setAgent(address _agent)
- **Parameters**: `_agent` - Agent contract address.
- **Behavior**: Sets `agent`, callable once.
- **Internal Call Flow**: Direct state update.
- **Restrictions**: Reverts if `agent` already set or invalid.
- **Gas Usage Controls**: Minimal, single state write.

#### update(address caller, UpdateType[] memory updates)
- **Parameters**:
  - `caller` - User address.
  - `updates` - Array of update structs.
- **Behavior**: Updates liquidity or fees, manages slots.
- **Internal Call Flow**:
  - Processes `updates`:
    - `updateType=0`: Updates `xLiquid` or `yLiquid`.
    - `updateType=1`: Updates `xFees` or `yFees`, emits `FeesUpdated`.
    - `updateType=2`: Updates `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, sets `dFeesAcc` to `yFeesAcc`.
    - `updateType=3`: Updates `yLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, sets `dFeesAcc` to `xFeesAcc`.
  - Emits `LiquidityUpdated`.
- **Balance Checks**: Checks `xLiquid` or `yLiquid` for balance updates.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Dynamic array resizing, loop over `updates`, no external calls.

#### changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `slotIndex` - Slot index.
  - `newDepositor` - New depositor address.
- **Behavior**: Transfers slot ownership to `newDepositor`.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots` or `yLiquiditySlots`, adjusts `userIndex`.
  - Emits `SlotDepositorChanged`.
- **Balance Checks**: Verifies slot `allocation` is non-zero.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `userIndex`.
  - **Structs**: `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, caller must be current depositor.
- **Gas Usage Controls**: Single slot update, array adjustments.

#### deposit(address caller, address token, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `token` - Token A or B.
  - `amount` - Denormalized amount.
- **Behavior**: Deposits tokens/ETH to liquidity pool, creates new slot.
- **Internal Call Flow**:
  - Performs pre/post balance checks for tokens, validates `msg.value` for ETH.
  - Transfers via `SafeERC20.transferFrom` or ETH deposit.
  - Normalizes `amount`, creates `UpdateType` for slot allocation (sets `dFeesAcc`).
  - Calls `update`, `globalizeUpdate`, `updateRegistry`.
- **Balance Checks**: Pre/post balance for tokens, `msg.value` for ETH.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `activeXLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal updates, try-catch for external calls.

#### xPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Parameters**:
  - `caller` - User address.
  - `amount` - Normalized amount.
  - `index` - Slot index.
- **Behavior**: Prepares token A withdrawal, calculates compensation in token B.
- **Internal Call Flow**:
  - Checks `xLiquid` and slot `allocation` in `xLiquiditySlots`.
  - Fetches `ISSListing.getPrice` to compute `withdrawAmountB` if liquidity deficit.
  - Returns `PreparedWithdrawal` with `amountA` and `amountB`.
- **Balance Checks**: Verifies `xLiquid`, `yLiquid` sufficiency.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `PreparedWithdrawal`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid slot.
- **Gas Usage Controls**: Minimal, single external call to `getPrice`.

#### xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**:
  - `caller` - User address.
  - `index` - Slot index.
  - `withdrawal` - Withdrawal amounts (`amountA`, `amountB`).
- **Behavior**: Executes token A withdrawal, transfers tokens/ETH.
- **Internal Call Flow**:
  - Updates `xLiquiditySlots`, `liquidityDetail` via `update`.
  - Transfers `amountA` (token A) and `amountB` (token B) via `SafeERC20` or ETH.
  - Calls `globalizeUpdate`, `updateRegistry` for both tokens.
- **Balance Checks**: Verifies `xLiquid`, `yLiquid` before transfers.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `activeXLiquiditySlots`, `userIndex`, `liquidityDetail`.
  - **Structs**: `PreparedWithdrawal`, `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid slot.
- **Gas Usage Controls**: Two transfers, minimal updates, try-catch for transfers.

#### yPrepOut(address caller, uint256 amount, uint256 index) returns (PreparedWithdrawal memory)
- **Parameters**: Same as `xPrepOut`.
- **Behavior**: Prepares token B withdrawal, calculates compensation in token A.
- **Internal Call Flow**: Checks `yLiquid`, `xLiquid`, uses `ISSListing.getPrice` for `withdrawAmountA`.
- **Balance Checks**: Verifies `yLiquid`, `xLiquid` sufficiency.
- **Mappings/Structs Used**: `yLiquiditySlots`, `liquidityDetail`, `PreparedWithdrawal`, `Slot`.
- **Restrictions**: Same as `xPrepOut`.
- **Gas Usage Controls**: Same as `xPrepOut`.

#### yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal)
- **Parameters**: Same as `xExecuteOut`.
- **Behavior**: Executes token B withdrawal, transfers tokens/ETH.
- **Internal Call Flow**: Updates `yLiquiditySlots`, transfers `amountB` (token B) and `amountA` (token A).
- **Balance Checks**: Verifies `yLiquid`, `xLiquid` before transfers.
- **Mappings/Structs Used**: `yLiquiditySlots`, `activeYLiquiditySlots`, `userIndex`, `liquidityDetail`, `PreparedWithdrawal`, `UpdateType`, `Slot`.
- **Restrictions**: Same as `xExecuteOut`.
- **Gas Usage Controls**: Same as `xExecuteOut`.

#### claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume)
- **Parameters**:
  - `caller` - User address.
  - `_listingAddress` - Listing contract address.
  - `liquidityIndex` - Slot index.
  - `isX` - True for token A, false for token B.
  - `volume` - Unused (ignored for compatibility).
- **Behavior**: Claims fees (yFees for xSlots, xFees for ySlots), resets `dFeesAcc` to current `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots).
- **Internal Call Flow**:
  - Validates listing via `ISSListing.volumeBalances`.
  - Creates `FeeClaimContext` to optimize stack usage (~7 variables).
  - Calls `_processFeeClaim`, which:
    - Fetches slot data (`xLiquiditySlots` or `yLiquiditySlots`).
    - Calls `_claimFeeShare` to compute `feeShare` using `contributedFees = feesAcc - dFeesAcc` and liquidity proportion.
    - Updates `xFees`/`yFees` and slot allocation via `update`.
    - Resets `dFeesAcc` to `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots) to track fees since last claim.
    - Transfers fees via `transact` (yFees for xSlots, xFees for ySlots).
    - Emits `FeesClaimed` with fee amounts.
- **Balance Checks**: Verifies `xBalance` (from `volumeBalances`), `xLiquid`/`yLiquid`, `xFees`/`yFees`.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `FeeClaimContext`, `UpdateType`, `LiquidityDetails`, `Slot`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, caller must be depositor, valid listing address.
- **Gas Usage Controls**: Single transfer, struct-based stack optimization, try-catch for `transact`, minimal external calls.

#### transact(address caller, address token, uint256 amount, address recipient)
- **Parameters**:
  - `caller` - User address.
  - `token` - Token A or B.
  - `amount` - Denormalized amount.
  - `recipient` - Recipient address.
- **Behavior**: Transfers tokens/ETH, updates liquidity (`xLiquid` or `yLiquid`).
- **Internal Call Flow**:
  - Normalizes `amount` using `IERC20.decimals`.
  - Checks `xLiquid` (token A) or `yLiquid` (token B).
  - Transfers via `SafeERC20.safeTransfer` or ETH call with try-catch.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Pre-transfer liquidity check for `xLiquid` or `yLiquid`.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`, valid token.
- **Gas Usage Controls**: Single transfer, minimal state updates, try-catch for transfers.

#### addFees(address caller, bool isX, uint256 fee)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `fee` - Normalized fee amount.
- **Behavior**: Adds fees to `xFees`/`yFees` and increments `xFeesAcc`/`yFeesAcc` in `liquidityDetail`.
- **Internal Call Flow**:
  - Increments `xFeesAcc` (isX=true) or `yFeesAcc` (isX=false).
  - Creates `UpdateType` to update `xFees` or `yFees`.
  - Calls `update`, emits `FeesUpdated`.
- **Balance Checks**: None, assumes normalized input.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `UpdateType`, `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routers[msg.sender]`.
- **Gas Usage Controls**: Minimal, single update, additional `xFeesAcc`/`yFeesAcc` write.

#### updateLiquidity(address caller, bool isX, uint256 amount)
- **Parameters**:
  - `caller` - User address.
  - `isX` - True for token A, false for token B.
  - `amount` - Normalized amount.
- **Behavior**: Reduces `xLiquid` or `yLiquid` in `liquidityDetail`.
- **Internal Call Flow**:
  - Checks `xLiquid` or `yLiquid` sufficiency.
  - Updates `liquidityDetail`, emits `LiquidityUpdated`.
- **Balance Checks**: Verifies `xLiquid` or `yLiquid` sufficiency.
- **Mappings/Structs Used**:
  - **Mappings**: `liquidityDetail`.
  - **Structs**: `LiquidityDetails`.
- **Restrictions**: `nonReentrant`, requires `routersเ**Behavior**: Resets `dFeesAcc` to the latest `xFeesAcc` (for ySlots) or `yFeesAcc` (for xSlots) after a successful fee claim in `_processFeeClaim` to prevent double-counting of fees in subsequent claims.
- **Internal Call Flow**: Updates slot's `dFeesAcc` within the `if (feeShare > 0)` block in `_processFeeClaim`, ensuring it reflects the current cumulative fees post-claim.
- **Balance Checks**: None specific to this change, as it relies on existing fee and liquidity checks.
- **Mappings/Structs Used**:
  - **Mappings**: `xLiquiditySlots`, `yLiquiditySlots`, `liquidityDetail`.
  - **Structs**: `Slot`, `LiquidityDetails`.
- **Restrictions**: No additional restrictions beyond existing `claimFees` checks.
- **Gas Usage Controls**: Minimal additional gas cost for single state write to `dFeesAcc`.

### Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` (1e18) for amounts, fetched via `IERC20.decimals`.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Dynamic array resizing, minimal external calls, struct-based stack management in `claimFees` (~7 variables).
- **Token Usage**:
  - xSlots: Provide token A liquidity, claim yFees.
  - ySlots: Provide token B liquidity, claim xFees.
- **Events**: `LiquidityUpdated`, `FeesUpdated`, `FeesClaimed`, `SlotDepositorChanged`, `GlobalizeUpdateFailed`, `UpdateRegistryFailed`.
- **Safety**:
  - Explicit casting for interfaces (e.g., `ISSListing`, `IERC20`, `ITokenRegistry`).
  - No inline assembly, uses high-level Solidity.
  - Try-catch for external calls (`transact`, `globalizeUpdate`, `updateRegistry`, `ISSListing.volumeBalances`, `ISSListing.getPrice`) to handle failures.
  - Hidden state variables accessed via view functions (e.g., `getXSlotView`, `liquidityDetailsView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
- **Fee System**:
  - Cumulative fees_signed char tf8;fees (`xFeesAcc`, `yFeesAcc`) track total fees added, never decrease.
  - `dFeesAcc` stores `yFeesAcc` (xSlots) or `xFeesAcc` (ySlots) at deposit or last claim, reset after claim to track fees since last claim.
  - Fee share based on `contributedFees = feesAcc - dFeesAcc`, proportional to liquidity contribution, capped at available fees.
- **Compatibility**: Aligned with `SSRouter` (v0.0.44), `SSAgent` (v0.0.2), `SSListingTemplate` (v0.0.10), `SSOrderPartial` (v0.0.18).
- **Caller Param**: Functionally unused in `addFees` and `updateLiquidity`, included for router validation.

# SSRouter Contract Documentation

## Overview
The `SSRouter` contract, implemented in Solidity (`^0.8.2`), facilitates order creation, settlement, liquidity management, and order cancellation for a decentralized trading platform. It inherits functionality from `SSSettlementPartial`, which extends `SSOrderPartial` and `SSMainPartial`, integrating with external interfaces (`ISSListingTemplate`, `ISSLiquidityTemplate`, `IERC20`) for token operations, `ReentrancyGuard` for reentrancy protection, and `Ownable` for administrative control. The contract handles buy/sell order creation, settlement, liquidity deposits, withdrawals, fee claims, depositor changes, and order cancellations, with rigorous gas optimization and safety mechanisms. State variables are hidden, accessed via view functions with unique names, and decimal precision is maintained across tokens. The contract avoids reserved keywords, uses explicit casting, and ensures graceful degradation.

**SPDX License:** BSD-3-Clause

**Version:** 0.0.61 (updated 2025-06-30)

**Inheritance Tree:** `SSRouter` → `SSSettlementPartial` → `SSOrderPartial` → `SSMainPartial`

## Mappings
- **orderPendingAmounts**: Tracks pending order amounts per listing and order ID (normalized to 1e18).
- **payoutPendingAmounts**: Tracks pending payout amounts per listing and payout order ID (normalized to 1e18).

## Structs
- **OrderPrep**: Contains `maker` (address), `recipient` (address), `amount` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256).
- **BuyOrderDetails**: Includes `orderId` (uint256), `maker` (address), `recipient` (address), `pending` (uint256, normalized), `filled` (uint256, normalized), `maxPrice` (uint256), `minPrice` (uint256), `status` (uint8).
- **SellOrderDetails**: Same as `BuyOrderDetails` for sell orders.
- **OrderClearData**: Contains `orderId` (uint256), `isBuy` (bool), `amount` (uint256, normalized).
- **OrderContext**: Contains `listingContract` (ISSListingTemplate), `tokenIn` (address), `tokenOut` (address), `liquidityAddr` (address).
- **BuyOrderUpdateContext**: Contains `makerAddress` (address), `recipient` (address), `status` (uint8), `amountReceived` (uint256, denormalized), `normalizedReceived` (uint256), `amountSent` (uint256, denormalized, tokenA for buy).
- **SellOrderUpdateContext**: Same as `BuyOrderUpdateContext`, with `amountSent` (tokenB for sell).
- **PayoutContext**: Contains `listingAddress` (address), `liquidityAddr` (address), `tokenOut` (address), `tokenDecimals` (uint8), `amountOut` (uint256, denormalized), `recipientAddress` (address).

## Formulas
1. **Price Impact**:
   - **Formula**: `impactPrice = (newXBalance * 1e18) / newYBalance`
   - **Used in**: `_computeImpact`, `_checkPricing`, `_prepareLiquidityTransaction`.
   - **Description**: Represents the post-settlement price after processing a buy or sell order, calculated using updated pool balances (`newXBalance` for tokenA, `newYBalance` for tokenB). In `_computeImpact`:
     - Fetches current pool balances via `listingVolumeBalancesView` (includes input amount).
     - Computes `amountOut` using constant product formula:
       - For buy: `amountOut = (inputAmount * xBalance) / yBalance`.
       - For sell: `amountOut = (inputAmount * yBalance) / xBalance`.
     - Adjusts balances: `newXBalance -= amountOut` (buy), `newYBalance -= amountOut` (sell).
     - Normalizes to 1e18 for precision: `impactPrice = (newXBalance * 1e18) / newYBalance`.
   - **Usage**:
     - **Pricing Validation**: In `_checkPricing`, `impactPrice` is compared against order’s `maxPrice` and `minPrice` (fetched via `getBuy/SellOrderPricing`). Ensures trade does not exceed price constraints, preventing unfavorable executions (e.g., excessive slippage).
     - **Output Calculation**: In `_prepareLiquidityTransaction`, used to compute `amountOut` for buy (`amountOut = (inputAmount * impactPrice) / 1e18`) or sell (`amountOut = (inputAmount * 1e18) / impactPrice`), ensuring accurate token swaps.
     - **Settlement**: Critical in `settleBuy/SellOrders` and `settleBuy/SellLiquid` to validate order execution against liquidity pool or listing contract, maintaining market stability.

2. **Buy Order Output**:
   - **Formula**: `amountOut = (inputAmount * xBalance) / yBalance`
   - **Used in**: `executeBuyOrder`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenA) for a buy order given the input amount (tokenB), using constant product formula. Relies on `impactPrice` for validation.

3. **Sell Order Output**:
   - **Formula**: `amountOut = (inputAmount * yBalance) / xBalance`
   - **Used in**: `executeSellOrder`, `_prepareLiquidityTransaction`.
   - **Description**: Computes the output amount (tokenB) for a sell order given the input amount (tokenA), using constant product formula. Relies on `impactPrice` for validation.

## External Functions

### setAgent(address newAgent)
- **Parameters**:
  - `newAgent` (address): New ISSAgent address.
- **Behavior**: Updates `agent` state variable for listing validation.
- **Internal Call Flow**: Direct state update, validates `newAgent` is non-zero. No external calls, transfers, or balance checks.
- **Mappings/Structs Used**:
  - **agent** (state variable): Stores ISSAgent address.
- **Restrictions**:
  - Restricted to `onlyOwner`.
  - Reverts if `newAgent` is zero (`"Invalid agent address"`).
- **Gas Usage Controls**: Minimal gas due to single state write.

### createBuyOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `recipientAddress` (address): Order recipient.
  - `inputAmount` (uint256): Input amount (denormalized, tokenB).
  - `maxPrice` (uint256): Maximum price (normalized).
  - `minPrice` (uint256): Minimum price (normalized).
- **Behavior**: Creates a buy order, transferring tokenB to the listing contract, and updating order state with `amountSent=0`.
- **Internal Call Flow**:
  - Calls `_handleOrderPrep` to validate inputs and create `OrderPrep` struct, normalizing `inputAmount` using `listingContract.decimalsB`.
  - `_checkTransferAmount` transfers `inputAmount` in tokenB from `msg.sender` to `listingAddress` via `IERC20.transferFrom` or ETH transfer, with pre/post balance checks.
  - `_executeSingleOrder` calls `listingContract.getNextOrderId`, creates `UpdateType[]` for pending order status, pricing, and amounts (with `amountSent=0`), invoking `listingContract.update`.
  - Transfer destination: `listingAddress`.
- **Balance Checks**:
  - **Pre-Balance Check**: Captures `listingAddress` balance before transfer.
  - **Post-Balance Check**: Ensures `postBalance > preBalance`, computes `amountReceived`.
- **Mappings/Structs Used**:
  - **Structs**: `OrderPrep`, `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `maker`, `recipient`, or `amount` is invalid, or transfer fails.
- **Gas Usage Controls**: Single transfer, minimal array updates (3 `UpdateType` elements).

### createSellOrder(address listingAddress, address recipientAddress, uint256 inputAmount, uint256 maxPrice, uint256 minPrice)
- **Parameters**: Same as `createBuyOrder`, but for sell orders with tokenA input.
- **Behavior**: Creates a sell order, transferring tokenA to the listing contract, with `amountSent=0`.
- **Internal Call Flow**:
  - Similar to `createBuyOrder`, using tokenA and `listingContract.decimalsA`.
  - `_checkTransferAmount` handles tokenA transfer.
- **Balance Checks**: Same as `createBuyOrder`.
- **Mappings/Structs Used**: Same as `createBuyOrder`.
- **Restrictions**: Same as `createBuyOrder`.
- **Gas Usage Controls**: Same as `createBuyOrder`.

### settleBuyOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles pending buy orders, transferring tokenA to recipients, tracking `amountSent` (tokenA).
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `_processBuyOrder` for each order:
    - Fetches `(pendingAmount, filled, amountSent)` via `getBuyOrderAmounts` with explicit destructuring.
    - Validates pricing via `_checkPricing`, using `_computeImpact` to calculate `impactPrice`, ensuring it is within `maxPrice` and `minPrice` (from `getBuyOrderPricing`).
    - Computes output via `_computeImpact` and `amountOut = (inputAmount * xBalance) / yBalance`.
    - Calls `_prepBuyOrderUpdate` for tokenA transfer via `listingContract.transact`, with denormalized amounts.
    - Updates `orderPendingAmounts` and creates `UpdateType[]` via `_createBuyOrderUpdates`, including `amountSent`.
  - Applies `finalUpdates[]` via `listingContract.update`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - `_prepBuyOrderUpdate` (inherited) ensures transfer success via try-catch.
- **Mappings/Structs Used**:
  - **Mappings**: `orderPendingAmounts`.
  - **Structs**: `UpdateType`, `BuyOrderUpdateContext`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders with zero pending amount or invalid pricing (based on `impactPrice`).
- **Gas Usage Controls**: `maxIterations` limits iteration, dynamic array resizing, `_processBuyOrder` reduces stack depth (~12 variables).

### settleSellOrders(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles pending sell orders, transferring tokenB to recipients, tracking `amountSent` (tokenB).
- **Internal Call Flow**:
  - Similar to `settleBuyOrders`, using `pendingSellOrdersView[]` and `_processSellOrder`.
  - Computes `amountOut = (inputAmount * yBalance) / xBalance`, validated by `impactPrice`.
  - Uses `_prepSellOrderUpdate` for tokenB transfers, includes `amountSent`.
- **Balance Checks**: Same as `settleBuyOrders`.
- **Mappings/Structs Used**: Same as `settleBuyOrders`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyOrders`.
- **Gas Usage Controls**: Same as `settleBuyOrders`, uses `_processSellOrder`.

### settleBuyLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles buy orders with liquidity pool, transferring tokenA to recipients, updating liquidity (tokenB), and tracking `amountSent` (tokenA).
- **Internal Call Flow**:
  - Iterates `pendingBuyOrdersView[]` up to `maxIterations`.
  - Calls `executeSingleBuyLiquid`:
    - Validates pricing via `_checkPricing`, using `_computeImpact` to ensure `impactPrice` is within `maxPrice` and `minPrice`.
    - `_prepBuyLiquidUpdates` uses `_prepareLiquidityTransaction` to compute `amountOut` based on `impactPrice` and tokens.
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
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if pricing invalid (based on `impactPrice`) or transfer fails.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays, try-catch error handling.

### settleSellLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleBuyOrders`.
- **Behavior**: Settles sell orders with liquidity pool, transferring tokenB, updating liquidity (tokenA), and tracking `amountSent` (tokenB).
- **Internal Call Flow**:
  - Similar to `settleBuyLiquid`, using `executeSingleSellLiquid` and `_prepSellLiquidUpdates`.
  - Computes `amountOut` using `impactPrice`, transfers tokenB, updates liquidity (tokenA, isX=true).
- **Balance Checks**: Same as `settleBuyLiquid`.
- **Mappings/Structs Used**: Same as `settleBuyLiquid`, with `SellOrderUpdateContext`.
- **Restrictions**: Same as `settleBuyLiquid`.
- **Gas Usage Controls**: Same as `settleBuyLiquid`.

### settleLongPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Settles long position payouts, transferring tokenB to holders.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `executeLongPayout` (inherited):
    - Uses `_prepPayoutContext` (tokenB, decimalsB).
    - Transfers `amountOut` via `listingContract.transact`.
    - Updates `payoutPendingAmounts` and creates `PayoutUpdate[]` via `_createPayoutUpdate`.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**:
  - `_transferListingPayoutAmount` (inherited) checks pre/post balances.
- **Mappings/Structs Used**:
  - **Mappings**: `payoutPendingAmounts`.
  - **Structs**: `PayoutContext`, `PayoutUpdate`, `LongPayoutStruct`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `listingContract`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortPayouts(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Settles short position payouts, transferring tokenA to holders.
- **Internal Call Flow**:
  - Similar to `settleLongPayouts`, using `shortPayoutByIndexView[]` and `executeShortPayout`.
  - Uses `_prepPayoutContext` with tokenA and `decimalsA`.
- **Balance Checks**: Same as `settleLongPayouts`.
- **Mappings/Structs Used**: Same as `settleLongPayouts`, with `ShortPayoutStruct`.
- **Restrictions**: Same as `settleLongPayouts`.
- **Gas Usage Controls**: Same as `settleLongPayouts`.

### settleLongLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Settles long position payouts from liquidity pool, transferring tokenB to holders.
- **Internal Call Flow**:
  - Iterates `longPayoutByIndexView[]` up to `maxIterations`.
  - Calls `settleSingleLongLiquid` (inherited):
    - Uses `_prepPayoutContext` (tokenB, decimalsB).
    - Checks liquidity via `_checkLiquidityBalance`.
    - Transfers `amountOut` via `liquidityContract.transact`.
    - Updates `payoutPendingAmounts` and creates `PayoutUpdate[]` via `_createPayoutUpdate`.
  - Applies `finalPayoutUpdates[]` via `listingContract.ssUpdate`.
  - Transfer destination: `recipientAddress` (tokenB).
- **Balance Checks**:
  - `_transferPayoutAmount` (inherited) checks liquidity pre/post balances.
- **Mappings/Structs Used**:
  - **Mappings**: `payoutPendingAmounts`.
  - **Structs**: `PayoutContext`, `PayoutUpdate`, `LongPayoutStruct`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
- **Gas Usage Controls**: `maxIterations`, dynamic arrays.

### settleShortLiquid(address listingAddress, uint256 maxIterations)
- **Parameters**: Same as `settleLongPayouts`.
- **Behavior**: Settles short position payouts from liquidity pool, transferring tokenA to holders.
- **Internal Call Flow**:
  - Similar to `settleLongLiquid`, using `settleSingleShortLiquid` and `_prepPayoutContext` with tokenA and `decimalsA`.
- **Balance Checks**: Same as `settleLongLiquid`.
- **Mappings/Structs Used**: Same as `settleLongLiquid`, with `ShortPayoutStruct`.
- **Restrictions**: Same as `settleLongLiquid`.
- **Gas Usage Controls**: Same as `settleLongLiquid`.

### deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isTokenA` (bool): True for tokenA, false for tokenB.
  - `inputAmount` (uint256): Deposit amount (denormalized).
  - `user` (address): User depositing liquidity.
- **Behavior**: Deposits tokens or ETH to the liquidity pool on behalf of `user`, allowing anyone to deposit for any valid `user`.
- **Internal Call Flow**:
  - Validates `isTokenA` to select tokenA or tokenB.
  - For ETH: Checks `msg.value == inputAmount`, calls `liquidityContract.deposit(user, tokenAddress, inputAmount)`.
  - For tokens: Transfers via `IERC20.transferFrom` from `msg.sender` to `this`, with pre/post balance checks, approves `liquidityAddr`, and calls `liquidityContract.deposit(user, tokenAddress, receivedAmount)`.
  - Transfer destinations: `this` (from `msg.sender`), `liquidityAddr` (from `this`).
- **Balance Checks**:
  - Pre/post balance checks for token transfers to handle fee-on-transfer tokens.
  - Relies on `liquidityContract.deposit` for ETH balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero or deposit fails.
- **Gas Usage Controls**: Single transfer and call, minimal state writes.

### claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `liquidityIndex` (uint256): Liquidity slot index.
  - `isX` (bool): True for tokenA (claims yFees), false for tokenB (claims xFees).
  - `volumeAmount` (uint256): Unused parameter (maintained for interface compatibility, internally set to 7777).
  - `user` (address): User claiming fees, must be the slot depositor.
- **Behavior**: Claims fees from the liquidity pool for `user`, restricted to the slot’s depositor.
- **Internal Call Flow**:
  - Calls `liquidityContract.claimFees(user, listingAddress, liquidityIndex, isX, 7777)`, where `volumeAmount` is ignored and internally set to 7777.
  - `liquidityContract` verifies `user` is the slot depositor.
  - No direct transfers or balance checks in `SSRouter`.
- **Balance Checks**: None, handled by `liquidityContract` via `_processFeeClaim` with pre/post balance checks.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero, `user` is not the slot depositor, or claim fails.
- **Gas Usage Controls**: Minimal, single external call.

### withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `inputAmount` (uint256): Withdrawal amount (denormalized).
  - `index` (uint256): Liquidity slot index.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `user` (address): User withdrawing liquidity, must be the slot depositor.
- **Behavior**: Withdraws liquidity from the pool for `user`, restricted to the slot’s depositor.
- **Internal Call Flow**:
  - Calls `xPrepOut` or `yPrepOut` with `user` to prepare withdrawal, verifying `user` is the slot depositor in `liquidityContract`.
  - Executes via `xExecuteOut` or `yExecuteOut` with `user`, transferring tokens to `user`.
  - No direct transfers in `SSRouter`, handled by `liquidityContract`.
- **Balance Checks**: None in `SSRouter`, handled by `liquidityContract` with pre/post balance checks in `xExecuteOut` or `yExecuteOut`.
- **Mappings/Structs Used**:
  - **Structs**: `PreparedWithdrawal`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` is zero, `user` is not the slot depositor, or preparation/execution fails.
- **Gas Usage Controls**: Minimal, two external calls.

### clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `orderIdentifier` (uint256): Order ID.
  - `isBuyOrder` (bool): True for buy, false for sell.
- **Behavior**: Cancels a single order, refunding pending amounts to `recipientAddress`, restricted to the order’s maker via `_clearOrderData`, and accounting for `amountSent`.
- **Internal Call Flow**:
  - Calls `_clearOrderData`:
    - Retrieves order data via `getBuyOrderCore` or `getSellOrderCore`, and `getBuyOrderAmounts` or `getSellOrderAmounts` (including `amountSent`).
    - Verifies `msg.sender` is the order’s maker, reverts if not (`"Only maker can cancel"`).
    - Refunds pending amount via `listingContract.transact` (tokenB for buy, tokenA for sell), using denormalized amount based on `decimalsB` or `decimalsA`.
    - Sets status to 0 (cancelled) via `listingContract.update` with `UpdateType[]`.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - `_clearOrderData` uses try-catch for refund transfer to ensure success or revert (`"Refund failed"`).
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Reverts if `msg.sender` is not the maker, refund fails, or order is not pending (status != 1 or 2).
- **Gas Usage Controls**: Single transfer and update, minimal array (1 `UpdateType`).

### clearOrders(address listingAddress, uint256 maxIterations)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `maxIterations` (uint256): Maximum orders to process.
- **Behavior**: Cancels pending buy and sell orders for `msg.sender` up to `maxIterations`, using `makerPendingOrdersView` to fetch orders, refunding pending amounts, and accounting for `amountSent`.
- **Internal Call Flow**:
  - Fetches `orderIds` via `listingContract.makerPendingOrdersView(msg.sender)`.
  - Iterates up to `maxIterations`:
    - For each `orderId`, checks if `msg.sender` is the maker via `getBuyOrderCore` or `getSellOrderCore`.
    - Calls `_clearOrderData` for valid orders, refunding pending amounts (tokenB for buy, tokenA for sell) and setting status to 0.
  - Transfer destination: `recipientAddress`.
- **Balance Checks**:
  - Same as `clearSingleOrder`, handled by `_clearOrderData` with try-catch.
- **Mappings/Structs Used**:
  - **Structs**: `UpdateType`.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Skips orders where `msg.sender` is not the maker or if order is not pending.
  - Reverts if refund fails in `_clearOrderData`.
- **Gas Usage Controls**: `maxIterations` limits iteration, minimal updates per order (1 `UpdateType`).

### changeDepositor(address listingAddress, bool isX, uint256 slotIndex, address newDepositor, address user)
- **Parameters**:
  - `listingAddress` (address): Listing contract address.
  - `isX` (bool): True for tokenA, false for tokenB.
  - `slotIndex` (uint256): Liquidity slot index.
  - `newDepositor` (address): New depositor address.
  - `user` (address): Current slot owner, must be the slot depositor.
- **Behavior**: Changes the depositor for a liquidity slot on behalf of `user`, restricted to the slot’s depositor.
- **Internal Call Flow**:
  - Calls `liquidityContract.changeSlotDepositor(user, isX, slotIndex, newDepositor)`, which verifies `user` is the slot depositor.
  - No direct transfers or balance checks in `SSRouter`.
- **Balance Checks**: None, handled by `liquidityContract`.
- **Mappings/Structs Used**: None.
- **Restrictions**:
  - Protected by `nonReentrant` and `onlyValidListing`.
  - Requires router registration in `liquidityContract.routers(address(this))`.
  - Reverts if `user` or `newDepositor` is zero, `user` is not the slot depositor, or change fails.
- **Gas Usage Controls**: Minimal, single external call.

## Additional Details
- **Decimal Handling**: Uses `normalize` and `denormalize` from `SSMainPartial.sol` (1e18) for token amounts, fetched via `IERC20.decimals` or `listingContract.decimalsA/B`. Ensures consistent precision across tokens.
- **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier.
- **Gas Optimization**: Uses `maxIterations` to limit loops, dynamic arrays for updates, `_checkAndTransferPrincipal` for efficient transfers, and `_processBuy/SellOrder` to reduce stack depth in `settleBuy/SellOrders` (~12 variables).
- **Listing Validation**: Uses `onlyValidListing` modifier with `ISSAgent.getListing` checks to ensure listing integrity.
- **Router Restrictions**: Functions interacting with `liquidityContract` (e.g., `deposit`, `withdraw`, `claimFees`, `changeDepositor`, `settleBuy/SellLiquid`, `settleLong/ShortLiquid`) require `msg.sender` to be a registered router in `liquidityContract.routers(address(this))`, ensuring only authorized routers can call these functions. The `liquidityContract` further restricts actions like withdrawals and depositor changes to the slot’s depositor via the `caller` parameter.
- **Order Cancellation**:
  - `clearSingleOrder`: Callable by anyone, but restricted to the order’s maker via `_clearOrderData`’s maker check (`msg.sender == maker`).
  - `clearOrders`: Cancels only `msg.sender`’s orders, fetched via `makerPendingOrdersView`, ensuring no unauthorized cancellations.
- **Token Usage**:
  - Buy orders: Input tokenB, output tokenA, `amountSent` tracks tokenA.
  - Sell orders: Input tokenA, output tokenB, `amountSent` tracks tokenB.
  - Long payouts: Output tokenB, no `amountSent`.
  - Short payouts: Output tokenA, no `amountSent`.
- **Events**: No events explicitly defined; relies on `listingContract` and `liquidityContract` events for logging.
- **Safety**:
  - Explicit casting used for all interface and address conversions (e.g., `ISSListingTemplate(listingAddress)`).
  - No inline assembly, adhering to high-level Solidity for safety.
  - Try-catch blocks handle external call failures (e.g., transfers, liquidity updates).
  - Hidden state variables accessed via unique view functions (e.g., `agentView`, `liquidityAddressView`, `makerPendingOrdersView`).
  - Avoids reserved keywords and unnecessary virtual/override modifiers.
  - Ensures graceful degradation with zero-length array returns on failure (e.g., `_prepBuyLiquidUpdates`).
  - Maker-only cancellation enforced in `_clearOrderData` to prevent unauthorized order cancellations.
