
# Marker Foundry: Pairing (MFP) AMM-Orderbook Hybrid DEX Specification

This document specifies the Marker Foundry: Pairing (MFP) protocol, a decentralized exchange (DEX) combining an automated market maker (AMM) with a limit orderbook. It details arrays, mappings, functions, and structs across its contracts, organized by suite: Router Suite (`MFPMainPartial.sol`, `MFPOrderPartial.sol`, `MFPSettlementPartial.sol`, `MFPRouter.sol`), Agent Suite (`MFPAgent.sol`, `MFPListingLogic.sol`, `MFPLiquidityLogic.sol`), Listing Template (`MFPListingTemplate.sol`, v0.0.16), and Liquidity Template (`MFPLiquidityTemplate.sol`, v0.0.17). All contracts use Solidity ^0.8.2 under the BSD-3-Clause license.

## Protocol Overview

MFP enables hybrid trading with limit orders and AMM liquidity pools, supporting ERC20 tokens and ETH. Users place limit orders, provide liquidity, and earn 0.05% fees. Global tracking enhances integration. Key features:

- **Orderbook**: Limit orders with price bounds, settled within user-defined ranges using impact price validation, supporting partial filling of individual orders over multiple transactions.
- **AMM**: Liquidity pools with fee distribution.
- **Global Sync**: Tracks liquidity/orders across pairs, supporting native ETH pairs.
- **Deterministic Deployment**: Consistent contract addresses.

## Router Suite

Handles user interactions, order creation, settlement with batch partial failure handling, and shared logic. Supports partial settlement of batches (some orders settle, others fail) and incremental partial filling of individual orders.

### Contracts

- **MFPMainPartial.sol** (v0.0.22): Defines structs, interfaces, and helpers. Updated `IMFPListing` to use `liquidityAddress()` without `listingId`.
- **MFPOrderPartial.sol** (v0.0.20): Manages order creation/cancellation with helper functions for buy/sell orders.
- **MFPSettlementPartial.sol** (v0.0.21): Handles orderbook/AMM settlement with batch partial settlement, using try-catch for robust error handling.
- **MFPRouter.sol** (v0.0.26): User-facing interface with helper functions to mitigate stack depth issues and fixed try-catch in `processOrderSettlement`.

### Arrays

- **MFPSettlementPartial.sol**:
  - `ListingUpdateType[]` in `prepBuyLiquid`, `prepSellLiquid`, `executeBuyOrders`, `executeSellOrders`: Stores order updates (core, pricing, amounts) for settlement.
  - `uint256[] memory orderIds`, `uint256[] memory amounts` in settlement functions: Lists order IDs and amounts for batch settlement.

- **MFPRouter.sol**:
  - `ListingUpdateType[]` in `createBuyOrder`, `createSellOrder`, `settleBuyOrders`, `settleSellOrders`, `settleBuyLiquid`, `settleSellLiquid`: Combines order updates for creation and settlement.
  - `uint256[] memory orderIds`, `uint256[] memory amounts` in settlement functions: Lists order IDs and amounts for batch settlement.

### Mappings

- **MFPRouter.sol**:
  - None defined; relies on inherited mappings from parent contracts.

### Structs

- **MFPMainPartial.sol**:
  - `ListingUpdateType`: Defines orderbook update fields (core, pricing, amounts).
  - `VolumeBalance`: Tracks token balances and trading volumes.
  - `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`: Store buy order maker, recipient, status, prices, and amounts.
  - `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`: Store sell order equivalents.
  - `HistoricalData`: Records trade price, balances, volumes, timestamp.
  - `LiquidityDetails`: Tracks AMM pool balances and fees.
  - `Slot`: Defines liquidity slot depositor, allocation, volume, timestamp.
  - `UpdateType`: Defines AMM update fields.
  - `PreparedWithdrawal`: Stores withdrawal amounts and fees.
  - `OrderPrep`, `BuyOrderDetails`, `SellOrderDetails`, `PreparedUpdate`, `SettlementData`: Helper structs for order processing.

- **MFPRouter.sol**:
  - `OrderContext`: Groups `tokenA`, `tokenB`, `listingId`, `liquidityAddress` to reduce stack usage.

### Functions

- **MFPMainPartial.sol (Internal)**:
  - `normalize(uint256 amount, uint8 decimals)`: Converts amount to 18 decimals.
  - `denormalize(uint256 amount, uint8 decimals)`: Converts from 18 decimals.
  - `calculateImpactPrice(uint256 amount, uint256 price, uint256 balance)`: Calculates impact price for validation against order price bounds.
  - `_transferToken(address token, address from, address to, uint256 amount)`: Transfers tokens or ETH, checks for transfer fees.
  - `_normalizeAndFee(address token, uint256 amount, bool isBuy)`: Normalizes amount, applies 0.05% fee.
  - `_createOrderUpdate(...)`: Builds order update array.

- **MFPOrderPartial.sol (Internal)**:
  - `prepBuyOrderCore`, `prepBuyOrderPricing`, `prepBuyOrderAmounts`: Prepare buy order updates (maker, prices, amounts).
  - `prepSellOrderCore`, `prepSellOrderPricing`, `prepSellOrderAmounts`: Prepare sell order updates.
  - `executeBuyOrderCore`, `executeBuyOrderPricing`, `executeBuyOrderAmounts`: Fetch buy order updates for settlement, support partial filling via pending amount updates.
  - `executeSellOrderCore`, `executeSellOrderPricing`, `executeSellOrderAmounts`: Fetch sell order updates for settlement.
  - `executeBuyOrder`, `executeSellOrder`: Combine updates for settlement, validate impact price against price bounds, settle requested amount or return empty array.
  - `clearSingleOrder`, `clearOrders`: Cancel one or multiple orders via `IMFPListing`.

- **MFPSettlementPartial.sol (Internal)**:
  - `prepBuyLiquid`, `prepSellLiquid`: Prepare AMM-based buy/sell settlement updates with try-catch.
  - `executeBuyLiquid`, `executeSellLiquid`: Execute AMM-based settlements, apply updates for successful orders.
  - `executeBuyOrders`, `executeSellOrders`: Execute orderbook-based settlements, apply updates for successful orders with try-catch.
  - `processOrder`: Executes single order settlement, returns updates.
  - Events: 
    - `OrderSettlementFailed(uint256 orderId, string reason)`: Emitted for failed order settlements.

- **MFPRouter.sol**:
  - External: 
    - `createBuyOrder`, `createSellOrder`: Create limit orders, transfer tokens, update via `IMFPListing`.
    - `settleBuyOrders`, `settleSellOrders`: Settle orderbook batches with partial failure handling.
    - `settleBuyLiquid`, `settleSellLiquid`: Settle AMM batches with partial failure handling.
    - `deposit`: Adds tokens to AMM pool.
    - `withdraw`: Removes tokens from AMM pool.
    - `claimFees`: Claims AMM fees for user.
    - `clearSingleOrder`, `clearOrders`: Cancel orders.
    - `viewLiquidity`: Returns liquidity amounts via `IMFPLiquidityTemplate`.
  - External (onlyOwner): 
    - `setListingAgent`, `setOrderLibrary`, `setAgent`, `setRegistry`: Configure contract addresses.
  - Internal:
    - `validateListing`: Verifies listing and returns `OrderContext`.
    - `transferOrderToken`: Transfers tokens for order creation.
    - `prepareOrderUpdates`: Combines order updates for creation.
    - `validateLiquidSettlement`: Validates AMM settlement inputs.
    - `processOrderSettlement`: Processes individual order settlements with try-catch.
    - `finalizeSettlement`: Applies final updates.
  - Events: 
    - `OrderCreated(address indexed listingAddress, address maker, uint256 amount, bool isBuy)`: Emitted on order creation.
    - `OrderCancelled(address listingAddress, uint256 orderId)`: Emitted on order cancellation.
    - `OrderSettlementSkipped(uint256 orderId, string reason)`: Emitted for skipped settlements.
    - `OrderSettlementFailed(uint256 orderId, string reason)`: Emitted for failed settlements.

## Agent Suite

Manages pair listings, deployments, and global tracking, supporting native ETH pairs.

### Contracts

- **MFPAgent.sol** (v0.0.12): Tracks liquidity, orders, and lists pairs, compatible with native token pairs.
- **MFPListingLogic.sol**: Deploys listing templates.
- **MFPLiquidityLogic.sol**: Deploys liquidity templates.

### Arrays

- **MFPAgent.sol**:
  - `address[] public allListings`: Stores all listing contract addresses.
  - `address[] publicAddress`: Lists unique tokens in listings.
  - `uint256[] public queryByAddress`: Maps tokens to listing IDs.
  - `uint256[] public pairOrders`: Tracks order IDs per token pair.
  - `uint256[] public userOrders`: Tracks order IDs per user.

### Mappings

- **MFPAgent.sol**:
  - `mapping(address => mapping(address => address)) public getMapping`: Maps tokenA, tokenB to listing address.
  - `mapping(address => uint256[]) public queryByAddress`: Maps token to listing IDs.
  - `mapping(address => mapping(address => mapping(address => uint256))) public globalLiquidity`: Maps tokenA, tokenB, user to amount.
  - `mapping(address => mapping(address => uint256)) public totalLiquidityPerPair`: Maps tokenA, tokenB to total liquidity.
  - `mapping(address => uint256) public userTotalLiquidity`: Maps user to total liquidity across pairs.
  - `mapping(uint256 => mapping(address => uint256)) public listingLiquidity`: Maps listing ID, user to amount.
  - `mapping(address => mapping(address => mapping(uint256 => uint256))) public historicalLiquidityPerPair`: Maps tokenA, tokenB, timestamp to amount.
  - `mapping(address => mapping(address => mapping(address => uint256))) public historicalLiquidityPerUser`: Maps tokenA, tokenB, user, timestamp to amounts.
  - `mapping(address => mapping(address => mapping(uint256 => GlobalOrder))) public globalOrders`: Maps tokenA, tokenB, order ID to details.
  - `mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))) public historicalOrderStatus`: Maps tokenA, tokenB, order ID, timestamp to status.
  - `mapping(address => mapping(address => mapping(address => uint256))) public userTradingSummaries`: Maps user, tokenA, tokenB to volume.

### Structs

- **MFPAgent.sol**:
  - `InitData`: Stores pair initialization data (tokens, listing ID).
  - `TrendData`: Tracks liquidity/order trends over time.
  - `GlobalOrder`: Stores global order details (maker, amount, price).
  - `OrderData`: Stores order view data for queries.

### Functions

- **MFPListingLogic.sol**:
  - External: 
    - `deploy(bytes32 salt)`: Deploys `MFPListingTemplate` with deterministic salt.

- **MFPLiquidityLogic.sol**:
  - External: 
    - `deploy(bytes32 salt)`: Deploys `MFPLiquidityTemplate` with deterministic salt.

- **MFPAgent.sol**:
  - External: 
    - `listToken`: Deploys and initializes token pair listing.
    - `listNative`: Deploys and initializes native ETH pair listing.
    - `globalizeLiquidity`: Updates global liquidity tracking.
    - `globalizeOrders`: Updates global order, supports native tokens.
  - External (onlyOwner): 
    - `setRouter`, `setListingLogic`, `setLiquidityLogic`, `setRegistry`: Configure contract addresses.
  - View: 
    - `getUserLiquidityAcrossPairs`: Returns user’s liquidity per pair.
    - `getTopLiquidityProviders`: Returns top liquidity providers.
    - `getUserLiquidityShare`: Returns user’s share in a pair.
    - `getAllPairsByLiquidity`: Lists pairs by liquidity.
    - `getPairLiquidityTrend`: Returns liquidity trend for a pair.
    - `getUserLiquidityTrend`: Returns user’s liquidity trend.
    - `getOrderActivityByPair`: Returns order activity for a pair.
    - `getUserTradingProfile`: Returns user’s trading summary.
    - `getTopTradersByVolume`: Lists top traders by volume.
    - `getAllPairsByOrderVolume`: Lists pairs by order volume.
    - `queryByAddressView`: Returns listing IDs for a token.
    - `allListingsLength`: Returns number of listings.
  - Internal: 
    - `tokenExists`: Checks if token is listed.
    - `_deployPair`: Deploys listing and liquidity contracts.
    - `_initializePair`: Initializes pair contracts.
    - `_updateState`: Updates global state.
    - `prepListing`, `executeListing`: Prepare/execute listing deployment.
    - `_updateGlobalLiquidity`: Updates liquidity mappings.
    - `_sortDescending`: Sorts arrays in descending order.
  - Events: 
    - `ListingCreated`: Emitted on pair listing.
    - `GlobalLiquidityChanged`: Emitted on liquidity update.
    - `GlobalOrderChanged`: Emitted on order update.

## Listings Template

Manages orderbooks, balances, and yield queries, supporting partial filling via pending amount updates.

### Arrays

- `uint256[] public pendingBuyOrders`: Lists active buy order IDs.
- `uint256[] public pendingSellOrders`: Lists active sell order IDs.
- `uint256[] public makerPendingOrders`: Lists order IDs per maker.
- `HistoricalData[] public historicalData`: Stores trade history (price, balances, volumes, timestamp).

### Mappings

- `mapping(uint256 => VolumeBalance) public volumeBalances`: Maps listing ID to token balances and volumes.
- `mapping(uint256 => uint256) public prices`: Maps listing ID to current price (xBalance * 1e18 / yBalance).
- `mapping(uint256 => BuyOrderDetailsType) public buyOrders`: Maps order ID to buy order maker, core, pricing, amounts.
- `mapping(uint256 => SellOrderDetailsType) public sellOrders`: Maps order ID to sell order maker, core, pricing, amounts.
- `mapping(uint256 => bool) public isBuyOrderComplete`: Maps order ID to buy order completion status.
- `mapping(uint256 => bool) public isSellOrderComplete`: Maps order ID to sell order completion status.

### Structs

- `ListingUpdateType`: Defines orderbook update fields.
- `VolumeBalance`: Tracks balances and volumes.
- `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`: Store buy order data.
- `SellOrderCore`, `SellOrderPricing`, `SellOrderAmounts`: Store sell order data.
- `HistoricalData`: Stores trade history.

### Functions

- External:
  - `setRouter`: Sets router address.
  - `setListingId`: Sets listing ID.
  - `setLiquidityAddress`: Sets liquidity contract address (single address, v0.0.16).
  - `setTokens`: Sets tokenA, tokenB addresses.
  - `setAgent`: Sets agent address.
  - `setRegistry`: Sets token registry address.
  - `update(address caller, ListingUpdateType[] memory updates)`: Updates balances, orders, historical data, triggers `globalizeOrders`.
  - `transact(address caller, address token, uint256 amount, address recipient)`: Transfers tokens, updates balances.
  - `nextOrderId`: Increments and returns order ID.
  - `queryYield(bool isX, uint256 maxIterations)`: Calculates APY from volume and liquidity.
- View:
  - `listingVolumeBalancesView`: Returns balances and volumes.
  - `listingPriceView`: Returns current price.
  - `pendingBuyOrdersView`, `pendingSellOrdersView`: Return active order IDs.
  - `makerPendingOrdersView`: Returns maker’s orders.
  - `getHistoricalDataView`: Returns trade history.
  - `historicalDataLengthView`: Returns history length.
  - `getHistoricalDataByNearestTimestamp`: Returns history by timestamp.
  - `buyOrderCoreView`, `buyOrderPricingView`, `buyOrderAmountsView`: Return buy order data.
  - `sellOrderCoreView`, `sellOrderPricingView`, `sellOrderAmountsView`: Return sell order data.
  - `isOrderCompleteView`: Returns order completion status.
  - `getListingId`: Returns listing ID.
  - `getRegistryAddress`: Returns registry address.
- Internal:
  - `normalize`, `denormalize`: Adjust decimals.
  - `removePendingOrder`: Removes order from pending lists.
  - `globalizeUpdate`: Syncs updates with agent.
  - `_updateRegistry`: Updates token registry.
  - `_isSameDay`: Checks if timestamps are same day.
  - `_floorToMidnight`: Floors timestamp to midnight.
  - `_findVolumeChange`: Calculates volume change.
- Events:
  - `OrderUpdated`: Emitted on order update.
  - `BalancesUpdated`: Emitted on balance update.
  - `RegistryUpdateFailed`: Emitted on registry update failure.

## Liquidity Template

Manages AMM pools, fees, and liquidity operations.

### Arrays

- `uint256[] public activeXLiquiditySlots`: Lists active tokenA liquidity slot indices.
- `uint256[] public activeYLiquiditySlots`: Lists active tokenB liquidity slot indices.
- `uint256[] public userIndex`: Maps users to their slot indices.

### Mappings

- `mapping(uint256 => Slot) public xLiquiditySlots`: Maps slot index to tokenA slot details.
- `mapping(uint256 => Slot) public yLiquiditySlots`: Maps slot index to tokenB slot details.
- `mapping(address => uint256[]) public userIndex`: Maps user to their slot indices.

### Structs

- `LiquidityDetails`: Tracks pool balances and fees.
- `Slot`: Stores slot depositor, allocation, volume, timestamp.
- `UpdateType`: Defines AMM update fields.
- `PreparedWithdrawal`: Stores withdrawal amounts and fees.

### Functions

- External:
  - `setRouter`: Sets router address.
  - `setListingId`: Sets listing ID.
  - `setListingAddress`: Sets listing contract address.
  - `setTokens`: Sets tokenA, tokenB addresses.
  - `setAgent`: Sets agent address.
  - `update(address caller, UpdateType[] memory updates)`: Updates pool balances, fees, slots.
  - `globalizeUpdate(address caller, bool isX, uint256 amount, bool isDeposit)`: Syncs liquidity with agent.
  - `changeSlotDepositor`: Updates slot depositor address.
  - `claimFees`: Claims fees based on volume share.
  - `addFees`: Adds fees to pool.
  - `deposit`: Deposits tokens to pool.
  - `transact`: Transfers tokens from pool.
  - `xPrepOut`, `yPrepOut`: Prepare tokenA, tokenB withdrawal amounts.
  - `xExecuteOut`, `yExecuteOut`: Execute tokenA, tokenB withdrawals.
- View:
  - `liquidityAmounts`: Returns pool liquidity amounts.
  - `feeAmounts`: Returns accumulated fees.
  - `liquidityDetailsView`: Returns pool details.
  - `activeXLiquiditySlotsView`, `activeYLiquiditySlotsView`: Return active slot indices.
  - `userIndexView`: Returns user’s slot indices.
  - `getXSlotView`, `getYSlotView`: Return slot details.
  - `getListingId`: Returns listing ID.
  - `validateListing`: Validates listing address.
- Internal:
  - `normalize`, `denormalize`: Adjust decimals.
  - `updateRegistry`: Updates token registry.
  - `removeSlot`: Removes slot from active list.
  - `calculateFeeShare`: Calculates user’s fee share.
- Events:
  - `LiquidityUpdated`: Emitted on pool update.
  - `FeesUpdated`: Emitted on fee update.
  - `FeesClaimed`: Emitted on fee claim.
  - `GlobalLiquidityUpdated`: Emitted on global sync.
  - `SlotDepositorChanged`: Emitted on depositor change.
  - `RegistryUpdateFailed`: Emitted on registry update failure.

## Real-World Applications

- **Hybrid DEX**: Combines limit orders and AMM (e.g., Uniswap with orderbook).
- **Yield Farming**: Earn 0.05% fees via `claimFees` (e.g., DeFi platforms).
- **DeFi Infrastructure**: Price feeds for lending (e.g., collateralized loans).
- **Analytics**: `MFPAgent` view functions for insights (e.g., DeFi dashboards).

