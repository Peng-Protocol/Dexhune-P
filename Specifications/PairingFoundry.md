
# MFP Contracts Specification

## Version
- **Version**: 0.0.28 (pre-testing)
- **Changes**:
  - Updated `MFPMainPartial` section to reflect `calculateImpactPrice` change, now accounting only for outgoing tokens (tokenA for buy, tokenB for sell) during settlement.
  - Incremented `MFPMainPartial` version to 0.0.24, preserved `MFPSettlementPartial` version at 0.0.22.
  - Removed `orderLibrary` state variable and `setOrderLibrary` function from `MFPRouter` section to align with prior updates.
  - Updated `Impact Price Usage` in `MFPRouter` section to match revised `calculateImpactPrice` logic and settlement calculations.
  - Preserved prior changes from v0.0.27, including `MFPMainPartial`, `MFPSettlementPartial`, and `MFPRouter` updates.

## Overview
Specification for MFPListingLogic.sol, MFPAgent.sol, MFPLiquidityLogic.sol, MFPRouter.sol, MFPMainPartial.sol, MFPSettlementPartial.sol, MFPOrderPartial.sol, MFPListingTemplate.sol, and MFPLiquidityTemplate.sol contracts, detailing state variables, mappings, arrays, functions, and formulas.

## MFPListingLogic Contract

### State Variables
- None explicitly declared (state managed by deployed MFPListingTemplate instances)

### Mappings
- None

### Arrays
- None

### Functions
- **deploy(bytes32 salt) public returns (address)**
  - Deploys a new MFPListingTemplate contract using create2 for deterministic address generation.
  - Returns the deployed contract address.

## MFPAgent Contract

### State Variables
- **routerAddress: address** (public)
  - Address of the router contract.
- **listingLogicAddress: address** (public)
  - Address of the MFPListingLogic contract.
- **liquidityLogicAddress: address** (public)
  - Address of the MFPLiquidityLogic contract.
- **registryAddress: address** (public)
  - Address of the registry contract.
- **listingCount: uint256** (public)
  - Total number of listings created.

### Mappings
- **getListing: mapping(address => mapping(address => address))** (public)
  - Maps tokenA => tokenB => listing contract address.
- **queryByAddress: mapping(address => uint256[])** (public)
  - Maps token address => array of associated listing IDs.
- **globalLiquidity: mapping(address => mapping(address => mapping(address => uint256)))** (public)
  - Tracks liquidity: tokenA => tokenB => user => amount.
- **totalLiquidityPerPair: mapping(address => mapping(address => uint256))** (public)
  - Tracks total liquidity: tokenA => tokenB => amount.
- **userTotalLiquidity: mapping(address => uint256)** (public)
  - Tracks user’s total liquidity: user => amount.
- **listingLiquidity: mapping(uint256 => mapping(address => uint256))** (public)
  - Tracks liquidity: listingId => user => amount.
- **historicalLiquidityPerPair: mapping(address => mapping(address => mapping(uint256 => uint256)))** (public)
  - Tracks historical liquidity: tokenA => tokenB => timestamp => amount.
- **historicalLiquidityPerUser: mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256))))** (public)
  - Tracks historical user liquidity: tokenA => tokenB => user => timestamp => amount.
- **globalOrders: mapping(address => mapping(address => mapping(uint256 => GlobalOrder)))** (public)
  - Tracks orders: tokenA => tokenB => orderId => GlobalOrder struct.
- **pairOrders: mapping(address => mapping(address => uint256[]))** (public)
  - Tracks order IDs: tokenA => tokenB => orderId array.
- **userOrders: mapping(address => uint256[])** (public)
  - Tracks user order IDs: user => orderId array.
- **historicalOrderStatus: mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8))))** (public)
  - Tracks order status history: tokenA => tokenB => orderId => timestamp => status.
- **userTradingSummaries: mapping(address => mapping(address => mapping(address => uint256)))** (public)
  - Tracks trading volume: user => tokenA => tokenB => volume.

### Arrays
- **allListings: address[]** (public)
  - Addresses of all deployed listing contracts.
- **allListedTokens: address[]** (public)
  - Addresses of all listed tokens.

### Structs
- **GlobalOrder**
  - **orderId: uint256**
  - **isBuy: bool**
  - **maker: address**
  - **recipient: address**
  - **amount: uint256**
  - **status: uint8** (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled)
  - **timestamp: uint256**
- **InitData**
  - **listingAddress: address**
  - **liquidityAddress: address**
  - **tokenA: address**
  - **tokenB: address**
  - **listingId: uint256**
- **TrendData**
  - **token: address**
  - **timestamp: uint256**
  - **amount: uint256**
- **OrderData**
  - **orderId: uint256**
  - **isBuy: bool**
  - **maker: address**
  - **recipient: address**
  - **amount: uint256**
  - **status: uint8**
  - **timestamp: uint256**

### Events
- **ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId)**
- **GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit)**
- **GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status)**

### Functions
- **tokenExists(address token)** (public)
- **setRouter(address _routerAddress) external onlyOwner)**
- **setListingLogic(address _listingLogic) external onlyOwner**
- **setLiquidityLogic(address _liquidityLogic) external onlyOwner**
- **setRegistry(address _registryAddress) external onlyOwner**
- **_deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address[], uint8[] memory listingAddress, address[] memory liquidityAddress)**
  - Deploys listing and liquidity contracts using create2.
- **_initializePair(InitDataType[] memory init) internal**
  - Initializes listing and liquidity contracts.
- **_updateState(address tokenA, uint8 tokenB, bool listingAddress, uint256[] listingId[], uint8) internal**
  - Updates mappings and arrays for new listings.
- **prepListing(address tokenA, address tokenB) internal returns (bool)**
- **executeListing(InitData[] memory init) internal returns (address[], bool[] memory listingAddress[], uint8[] memory liquidityAddress[])**
- **listToken(address tokenA, address tokenB) external returns (address[] memory listingAddress[], uint256[] memory liquidityAddress[])**
- **listNative(address token, uint8 isA) external returns (uint256 listingAddress, uint256 address liquidityAddress)**
- **globalizeLiquidity(uint256[] listingId[], uint8 tokenA[], address[] memory tokenB[], address[], uint256 amount, bool isDeposit) external**
- **globalizeOrders(uint256[] listingId[], uint256 orderId[], uint8[], bool isBuy[], address maker[], address recipient[], uint[], uint256[] amount[], uint8[] status[]) external**
- **_updateGlobalLiquidity(uint256[] listingId[], address tokenA[], address tokenB[], address[], uint256 amount, bool isDeposit) internal**
- **getUserLiquidityAcrossPairs(address user[], uint256 maxIterations) external view returns (address[] memory tokenAs[], address[] memory tokenBs[], uint256[] memory amounts[])**
- **getTopLiquidityProviders(uint256 listingId[], uint256 maxIterations) external view returns (address[] memory users[], uint256[] memory amounts[])**
- **getUserLiquidityShare(address user[], address tokenA[], address tokenB[]) external view returns (uint256 share, uint256 total)**
- **getAllPairsByLiquidity(uint256 minLiquidity, uint256 maxIterations) external view returns (address[] memory tokenAs[], address[] memory tokenBs[], uint256[] memory amounts[])**
- **getPairLiquidityTrend(address tokenA[], address tokenB[], uint256 startTime, uint256 endTime) external view returns (uint256[] memory timestamps[], uint256[] memory amounts[])**
- **getUserLiquidityTrend(address user[], address tokenA[], address tokenB[], uint256 startTime, uint256 endTime) external view returns (address[] memory tokens[], uint256[] memory timestamps[], uint256[] memory amounts[])**
- **getOrderActivityByPair(address tokenA[], address tokenB[], uint256 startTime, uint256 endTime) external view returns (uint256[] memory orderIds[], OrderData[] memory orders[])**
- **getUserTradingProfile(address user[]) external view returns (address[] memory tokenAs[], address[] memory tokenBs[], uint256[] memory volumes[])**
- **getTopTradersByVolume(uint256 listingId[], uint256 maxIterations) external view returns (address[] memory traders[], uint256[] memory volumes[])**
- **getAllPairsByOrderVolume(uint256 minVolume, uint256 maxIterations) external view returns (address[] memory tokenAs[], address[] memory tokenBs[], uint256[] memory volumes[])**
- **_sortDescending(TrendData[] memory data[], uint256 length) internal pure**
- **queryByAddressView(address target[], uint256 maxIteration, uint256 step) external view returns (uint256[] memory)**
- **allListingsLength() external view returns (uint256)**

### Formulas
- **User Liquidity Share**
  - share = (userAmount * 1e18) / total
  - Returns 0 if total liquidity is 0.

## MFPLiquidityLogic Contract

### State Variables
- None explicitly declared (state managed by deployed MFPLiquidityTemplate instances)

### Mappings
- None

### Arrays
- None

### Functions
- **deploy(bytes32 salt) public returns (address)**
  - Deploys a new MFPLiquidityTemplate contract using create2.
  - Returns the deployed contract address.

## MFPRouter Contract

### Inheritance Chain
- **MFPRouter** inherits from **MFPSettlementPartial**
- **MFPSettlementPartial** inherits from **MFPOrderPartial**
- **MFPOrderPartial** inherits from **MFPMainPartial**
- **MFPMainPartial** inherits from **Ownable** and **ReentrancyGuard**
- This chain allows MFPRouter to access and override functions from MFPSettlementPartial, MFPOrderPartial, and MFPMainPartial, while leveraging ownership (onlyOwner) and reentrancy protection (nonReentrant) from Ownable and ReentrancyGuard.

### State Variables
- **listingAgent: address** (public)
  - Address of the listing agent contract.
- **agent: address** (public)
  - Address of the MFPAgent contract.
- **registryAddress: address** (public)
  - Address of the TokenRegistry contract.

### Mappings
- None

### Arrays
- None

### Structs
- **OrderContext**
  - **tokenA: address**
  - **tokenB: address**
  - **listingId: uint256**
  - **liquidityAddress: address**

### Events
- **OrderSettlementSkipped(uint256 orderId, string reason)**
- **OrderSettlementFailed(uint256 orderId, string reason)**
- **OrderCreated(address indexed listingAddress, address indexed maker, uint256 amount, bool isBuy)** (inherited from MFPOrderPartial)
- **OrderCancelled(address indexed listingAddress, uint256 orderId)** (inherited from MFPOrderPartial)

### Functions
- **setListingAgent(address _listingAgent) external onlyOwner**
  - Sets listingAgent, requires non-zero address.
- **setAgent(address _agent) external onlyOwner**
  - Sets agent, requires non-zero address.
- **setRegistry(address _registryAddress) external onlyOwner**
  - Sets registryAddress, requires non-zero address.
- **normalize(uint256 amount, uint8 decimals) internal pure override**
  - Overrides MFPMainPartial’s normalize to standardize amounts to 18 decimals.
- **_transferToken(address token, address from, address to, uint256 amount) internal override**
  - Overrides MFPMainPartial’s _transferToken for ETH or ERC20 transfers, using SafeERC20.
- **validateListing(address listingAddress) internal view returns (OrderContext memory)**
  - Validates listing via IMFPAgent.getListing, returns OrderContext.
- **transferOrderToken(address token, uint256 amount, address sender) internal returns (uint256)**
  - Transfers tokens using _transferToken (inherited), normalizes amount.
- **prepareOrderUpdates(uint256 listingId, uint256 orderId, address maker, address recipient, uint256 normalizedAmount, uint256 maxPrice, uint256 minPrice, bool isBuy) internal view returns (IMFPListing.ListingUpdateType[] memory)**
  - Combines updates from inherited prepBuyOrderCore, prepBuyOrderPricing, prepBuyOrderAmounts (or sell equivalents) from MFPOrderPartial.
- **validateLiquidSettlement(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal view returns (OrderContext memory)**
  - Validates liquid settlement inputs, calls validateListing.
- **processOrderSettlement(address listingAddress, uint256 orderId, uint256 amount, bool isBuy, IMFPListing.ListingUpdateType[] memory tempUpdates, uint256 index) internal returns (uint256 newIndex, uint256 amountSettled)**
  - Processes settlements using executeBuyOrder or executeSellOrder (inherited from MFPSettlementPartial), emits OrderSettlementSkipped or OrderSettlementFailed.
- **finalizeSettlement(address listingAddress, IMFPListing.ListingUpdateType[] memory tempUpdates, uint256 index) internal returns (IMFPListing.ListingUpdateType[] memory)**
  - Finalizes updates, applies non-empty updates via IMFPListing.update.
- **createBuyOrder(address listingAddress, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external payable nonReentrant returns (IMFPListing.ListingUpdateType[] memory)**
  - Validates listing, transfers tokenB using transferOrderToken, prepares updates with prepareOrderUpdates, applies updates, emits OrderCreated (inherited).
- **createSellOrder(address listingAddress, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external payable nonReentrant returns (IMFPListing.ListingUpdateType[] memory)**
  - Similar to createBuyOrder, but for tokenA, emits OrderCreated.
- **settleBuyOrders(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory)**
  - Validates listing, processes settlements via processOrderSettlement, finalizes with finalizeSettlement, leverages executeBuyOrder (inherited).
- **settleSellOrders(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory)**
  - Similar to settleBuyOrders, uses executeSellOrder (inherited).
- **settleBuyLiquid(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory)**
  - Validates via validateLiquidSettlement, processes settlements, calls executeBuyLiquid (inherited), adds fees via IMFPLiquidityTemplate.addFees.
- **settleSellLiquid(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory)**
  - Similar to settleBuyLiquid, uses executeSellLiquid (inherited).
- **deposit(address listingAddress, bool isX, uint256 amount) external payable nonReentrant**
  - Validates listing, transfers tokens using _transferToken (inherited), calls IMFPLiquidityTemplate.deposit.
- **withdraw(address listingAddress, bool isX, uint256 amount, uint256 index) external nonReentrant**
  - Validates listing, calls IMFPLiquidityTemplate.xPrepOut or yPrepOut, executes withdrawal via xExecuteOut or yExecuteOut.
- **claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external nonReentrant**
  - Validates listing, calls IMFPLiquidityTemplate.claimFees.
- **clearSingleOrder(address listingAddress, uint256 orderId) public nonReentrant override**
  - Overrides MFPOrderPartial’s clearSingleOrder, validates listing, emits OrderCancelled (inherited).
- **clearOrders(address listingAddress) public nonReentrant override**
  - Overrides MFPOrderPartial’s clearOrders, validates listing, emits OrderCancelled.
- **viewLiquidity(address listingAddress) external view returns (uint256 xAmount, uint256 yAmount)**
  - Validates listing, queries IMFPLiquidityTemplate.liquidityAmounts.

### Impact Price Usage
- Defined in MFPMainPartial’s **calculateImpactPrice(uint256 amount, uint256 xBalance, uint256 yBalance, bool isBuy) internal pure returns (uint256)**:
  - Computes price as `currentPrice = (xBalance * 1e18) / yBalance`.
  - For buy orders: `amountOut = (amount * currentPrice) / 1e18`, `newXBalance = xBalance - amountOut`, `newYBalance = yBalance` (only tokenA moves out).
  - For sell orders: `amountOut = (amount * 1e18) / currentPrice`, `newXBalance = xBalance`, `newYBalance = yBalance - amountOut` (only tokenB moves out).
  - Returns `impactPrice = (newXBalance * 1e18) / newYBalance`.
  - Used in MFPSettlementPartial’s **executeBuyOrder** and **executeSellOrder** to validate order execution:
    - For buy orders: Compares impactPrice against buyOrderPricingView’s maxPrice/minPrice. Uses `amountOut = (amount * impactPrice) / 1e18` for tokenA received. Returns empty updates if impactPrice is out of range.
    - For sell orders: Compares impactPrice against sellOrderPricingView’s maxPrice/minPrice. Uses `amountOut = (amount * 1e18) / impactPrice` for tokenB received. Returns empty updates if impactPrice is out of range.
  - Ensures orders execute within acceptable price ranges, accounting for market impact based on updated balances.
- **Price Usage in Settlement Calculations**:
  - Price is defined as `price = (xBalance * 1e18) / yBalance`, representing tokenA per tokenB (normalized to 18 decimals).
  - For buy orders (tokenB to tokenA): Settlement uses `amount * impactPrice / 1e18` to calculate tokenA received.
    - Example: If `xBalance = 100`, `yBalance = 200`, `price = 0.5e18`. For `amount = 20e18` tokenB, `amountOut = 20e18 * 0.5e18 / 1e18 = 10e18` tokenA.
  - For sell orders (tokenA to tokenB): Settlement uses `amount * 1e18 / impactPrice` to calculate tokenB received.
    - Example: Same pool, for `amount = 10e18` tokenA, `amountOut = 10e18 * 1e18 / 0.5e18 = 20e18` tokenB.
  - These calculations ensure accurate token swaps based on the pool’s price and impact price.

## MFPMainPartial Contract

### State Variables
- None

### Mappings
- None

### Arrays
- None

### Structs
- **VolumeBalance**, **BuyOrderCore**, **BuyOrderPricing**, **BuyOrderAmounts**, **SellOrderCore**, **SellOrderPricing**, **SellOrderAmounts**, **HistoricalData**, **LiquidityDetails**, **Slot**, **UpdateType**, **OrderPrep**, **BuyOrderDetails**, **SellOrderDetails**, **PreparedUpdate**, **SettlementData**

### Functions
- **normalize(uint256 amount, uint8 decimals) internal pure virtual**
  - Standardizes amounts to 18 decimals.
- **denormalize(uint256 amount, uint8 decimals) internal pure**
  - Converts amounts back to token-specific decimals.
- **calculateImpactPrice(uint256 amount, uint256 xBalance, uint256 yBalance, bool isBuy) internal pure**
  - Computes impact price based on outgoing token balances after a buy or sell order.
  - Reverts if yBalance or newYBalance is zero, or if xBalance/yBalance is insufficient.
- **_transferToken(address token, address from, address to, uint256 amount) internal virtual**
  - Handles ETH or ERC20 transfers using SafeERC20.
- **_normalizeAndFee(address token, uint256 amount, bool isBuy) internal view returns (uint256 normalized, uint256 fee)**
  - Normalizes amount and calculates 0.05% fee.
- **_createOrderUpdate(uint256 listingId, uint256 orderId, uint256 amount, address maker, address recipient, uint256 maxPrice, uint256 minPrice, bool isBuy) internal pure**
  - Prepares ListingUpdateType array for order creation.

### Formulas
- **Impact Price**
  - `currentPrice = (xBalance * 1e18) / yBalance`
  - Buy: `amountOut = (amount * currentPrice) / 1e18`, `newXBalance = xBalance - amountOut`, `newYBalance = yBalance`
  - Sell: `amountOut = (amount * 1e18) / currentPrice`, `newXBalance = xBalance`, `newYBalance = yBalance - amountOut`
  - `impactPrice = (newXBalance * 1e18) / newYBalance`
- **Fee Calculation**
  - `fee = (normalized * 5) / 10000` (0.05% fee)

## MFPSettlementPartial Contract

### State Variables
- None

### Mappings
- None

### Arrays
- None

### Functions
- **prepBuyLiquid(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal**
  - Prepares updates for buy liquid settlements using executeBuyOrder.
- **prepSellLiquid(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal**
  - Prepares updates for sell liquid settlements using executeSellOrder.
- **executeBuyLiquid(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal**
  - Executes buy liquid settlements, applies updates.
- **executeSellLiquid(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal**
  - Executes sell liquid settlements, applies updates.
- **executeBuyOrders(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal**
  - Processes multiple buy orders, applies valid updates.
- **executeSellOrders(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts) internal**
  - Processes multiple sell orders, applies valid updates.
- **executeBuyOrder(address listingAddress, uint256 orderId, uint256 amount) public override**
  - Validates impact price, uses `amount * impactPrice / 1e18` for tokenA received, returns updates.
- **executeSellOrder(address listingAddress, uint256 orderId, uint256 amount) public override**
  - Validates impact price, uses `amount * 1e18 / impactPrice` for tokenB received, returns updates.
- **processOrder(address listingAddress, uint256 orderId, uint256 amount, bool isBuy) internal**
  - Routes to executeBuyOrder or executeSellOrder based on isBuy.


# MFPOrderPartial Contract Specification

## Version
- **Version**: 0.0.20 (pre-testing)
- **Changes**:
  - Preserved all prior changes from v0.0.20.
  - No changes required for override or visibility issues as `clearSingleOrder` and `clearOrders` are already `public virtual`.

## Overview
The `MFPOrderPartial` contract is a partial implementation in MFP, inheriting from `MFPMainPartial`. It provides core functionality for preparing and executing buy and sell orders, as well as clearing orders, for a decentralized exchange. It defines structs, events, and functions to manage order creation, pricing, amounts, and cancellation, ensuring proper interaction with the `MFPListingTemplate` contract via the `IMFPListing` interface. All functions adhere to the specified Solidity style guide, using explicit declarations, avoiding reserved keywords, and ensuring proper visibility and virtual/override usage.

## Inheritance
- Inherits from `MFPMainPartial`, which provides base functionality like `normalize`, `denormalize`, `calculateImpactPrice`, and `_transferToken`.
- `MFPOrderPartial` is designed to be inherited by other contracts (e.g., `MFPSettlementPartial`, `MFPRouter`) to extend order-related functionality.

## State Variables
- None declared. State is managed by `MFPListingTemplate` instances or other contracts in the inheritance chain.

## Mappings
- None declared. Order data is stored in `MFPListingTemplate` mappings (`buyOrderCores`, `sellOrderCores`, etc.).

## Arrays
- None declared. Arrays like `pendingBuyOrders` and `pendingSellOrders` are managed by `MFPListingTemplate`.

## Structs
- Uses `IMFPListing.ListingUpdateType` (defined in `MFPListingTemplate`):
  - **updateType: uint8** (0 = balance, 1 = buy order, 2 = sell order, 3 = historical)
  - **structId: uint8** (0 = Core, 1 = Pricing, 2 = Amounts for updateType 1 or 2)
  - **index: uint256** (orderId or slot index)
  - **value: uint256** (amount or price, normalized)
  - **addr: address** (maker address)
  - **recipient: address** (recipient address)
  - **maxPrice: uint256** (maximum price for pricing updates)
  - **minPrice: uint256** (minimum price for pricing updates)
- This struct is used to prepare and execute updates to `MFPListingTemplate` state, ensuring modularity and stack depth management.

## Events
- **OrderCreated(address indexed listingAddress, address indexed maker, uint256 amount, bool isBuy)**
  - Emitted when a new buy or sell order is created.
  - Parameters:
    - `listingAddress`: Address of the listing contract.
    - `maker`: Address of the order creator.
    - `amount`: Normalized amount of the order.
    - `isBuy`: True for buy orders, false for sell orders.
- **OrderCancelled(address indexed listingAddress, uint256 orderId)**
  - Emitted when an order is cancelled.
  - Parameters:
    - `listingAddress`: Address of the listing contract.
    - `orderId`: ID of the cancelled order.

## Functions

### prepBuyOrderCore
- **Signature**: `prepBuyOrderCore(uint256 listingId, uint256 orderId, address maker, address recipient) internal pure returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares a `ListingUpdateType` array to initialize the core details of a buy order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `maker`: Address of the order creator.
  - `recipient`: Address to receive the output tokens.
- **Returns**: Array with one `ListingUpdateType`:
  - `updateType = 1` (buy order), `structId = 0` (core), `index = orderId`, `addr = maker`, `recipient = recipient`.
- **Explanation**: Creates a single update to set the `BuyOrderCore` struct in `MFPListingTemplate`, storing maker and recipient addresses and initializing the order status. Pure function, no state changes.

### prepBuyOrderPricing
- **Signature**: `prepBuyOrderPricing(uint256 listingId, uint256 orderId, uint256 maxPrice, uint256 minPrice) internal pure returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares a `ListingUpdateType` array to set the pricing constraints for a buy order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `maxPrice`: Maximum acceptable price (normalized to 18 decimals).
  - `minPrice`: Minimum acceptable price (normalized to 18 decimals).
- **Returns**: Array with one `ListingUpdateType`:
  - `updateType = 1` (buy order), `structId = 1` (pricing), `index = orderId`, `maxPrice = maxPrice`, `minPrice = minPrice`.
- **Explanation**: Sets the `BuyOrderPricing` struct in `MFPListingTemplate`, defining the price range for order execution. Pure function, no state changes.

### prepBuyOrderAmounts
- **Signature**: `prepBuyOrderAmounts(uint256 listingId, uint256 orderId, uint256 amount) internal pure returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares a `ListingUpdateType` array to set the amount details for a buy order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `amount`: Amount of tokenB to spend (normalized to 18 decimals).
- **Returns**: Array with one `ListingUpdateType`:
  - `updateType = 1` (buy order), `structId = 2` (amounts), `index = orderId`, `value = amount`.
- **Explanation**: Updates the `BuyOrderAmounts` struct in `MFPListingTemplate`, setting the pending amount for the order. Pure function, no state changes.

### prepSellOrderCore
- **Signature**: `prepSellOrderCore(uint256 listingId, uint256 orderId, address maker, address recipient) internal pure returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares a `ListingUpdateType` array to initialize the core details of a sell order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `maker`: Address of the order creator.
  - `recipient`: Address to receive the output tokens.
- **Returns**: Array with one `ListingUpdateType`:
  - `updateType = 2` (sell order), `structId = 0` (core), `index = orderId`, `addr = maker`, `recipient = recipient`.
- **Explanation**: Sets the `SellOrderCore` struct in `MFPListingTemplate`, storing maker and recipient addresses and initializing the order status. Pure function, no state changes.

### prepSellOrderPricing
- **Signature**: `prepSellOrderPricing(uint256 listingId, uint256 orderId, uint256 maxPrice, uint256 minPrice) internal pure returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares a `ListingUpdateType` array to set the pricing constraints for a sell order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `maxPrice`: Maximum acceptable price (normalized to 18 decimals).
  - `minPrice`: Minimum acceptable price (normalized to 18 decimals).
- **Returns**: Array with one `ListingUpdateType`:
  - `updateType = 2` (sell order), `structId = 1` (pricing), `index = orderId`, `maxPrice = maxPrice`, `minPrice = minPrice`.
- **Explanation**: Sets the `SellOrderPricing` struct in `MFPListingTemplate`, defining the price range for order execution. Pure function, no state changes.

### prepSellOrderAmounts
- **Signature**: `prepSellOrderAmounts(uint256 listingId, uint256 orderId, uint256 amount) internal pure returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares a `ListingUpdateType` array to set the amount details for a sell order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `amount`: Amount of tokenA to sell (normalized to 18 decimals).
- **Returns**: Array with one `ListingUpdateType`:
  - `updateType = 2` (sell order), `structId = 2` (amounts), `index = orderId`, `value = amount`.
- **Explanation**: Updates the `SellOrderAmounts` struct in `MFPListingTemplate`, setting the pending amount for the order. Pure function, no state changes.

### executeBuyOrderCore
- **Signature**: `executeBuyOrderCore(uint256 listingId, uint256 orderId) internal view returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Retrieves and prepares core details for executing a buy order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
- **Returns**: Array with one `ListingUpdateType` containing the buy order’s core data.
- **Explanation**: Queries `buyOrderCoreView` from `MFPListingTemplate` to get maker, recipient, and status, then constructs a `ListingUpdateType` for core updates. View function, no state changes.

### executeBuyOrderPricing
- **Signature**: `executeBuyOrderPricing(uint256 listingId, uint256 orderId) internal view returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Retrieves and prepares pricing details for executing a buy order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
- **Returns**: Array with one `ListingUpdateType` containing the buy order’s pricing data.
- **Explanation**: Queries `buyOrderPricingView` from `MFPListingTemplate` to get maxPrice and minPrice, then constructs a `ListingUpdateType` for pricing updates. View function, no state changes.

### executeBuyOrderAmounts
- **Signature**: `executeBuyOrderAmounts(uint256 listingId, uint256 orderId, uint256 amount) internal view returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares amount details for executing a buy order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `amount`: Amount to execute (normalized to 18 decimals).
- **Returns**: Array with one `ListingUpdateType` for the amount update.
- **Explanation**: Constructs a `ListingUpdateType` to update the `BuyOrderAmounts` struct with the specified amount. View function, no state changes.

### executeSellOrderCore
- **Signature**: `executeSellOrderCore(uint256 listingId, uint256 orderId) internal view returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Retrieves and prepares core details for executing a sell order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
- **Returns**: Array with one `ListingUpdateType` containing the sell order’s core data.
- **Explanation**: Queries `sellOrderCoreView` from `MFPListingTemplate` to get maker, recipient, and status, then constructs a `ListingUpdateType` for core updates. View function, no state changes.

### executeSellOrderPricing
- **Signature**: `executeSellOrderPricing(uint256 listingId, uint256 orderId) internal view returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Retrieves and prepares pricing details for executing a sell order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
- **Returns**: Array with one `ListingUpdateType` containing the sell order’s pricing data.
- **Explanation**: Queries `sellOrderPricingView` from `MFPListingTemplate` to get maxPrice and minPrice, then constructs a `ListingUpdateType` for pricing updates. View function, no state changes.

### executeSellOrderAmounts
- **Signature**: `executeSellOrderAmounts(uint256 listingId, uint256 orderId, uint256 amount) internal view returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Prepares amount details for executing a sell order.
- **Parameters**:
  - `listingId`: ID of the listing.
  - `orderId`: ID of the order.
  - `amount`: Amount to execute (normalized to 18 decimals).
- **Returns**: Array with one `ListingUpdateType` for the amount update.
- **Explanation**: Constructs a `ListingUpdateType` to update the `SellOrderAmounts` struct with the specified amount. View function, no state changes.

### executeBuyOrder
- **Signature**: `executeBuyOrder(address listingAddress, uint256 orderId, uint256 amount) public virtual returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Combines core, pricing, and amount updates to execute a buy order.
- **Parameters**:
  - `listingAddress`: Address of the listing contract.
  - `orderId`: ID of the order.
  - `amount`: Amount to execute (normalized to 18 decimals).
- **Returns**: Array of `ListingUpdateType` combining core, pricing, and amount updates.
- **Explanation**:
  - Queries `getListingId` from `IMFPListing` to get the listing ID.
  - Calls `executeBuyOrderCore`, `executeBuyOrderPricing`, and `executeBuyOrderAmounts` to prepare updates.
  - Combines updates into a single array, ensuring stack depth is managed (three updates total).
  - Virtual function, allowing overrides in inheriting contracts (e.g., `MFPSettlementPartial`).
  - Does not apply updates; caller (e.g., `MFPRouter`) must pass the returned array to `IMFPListing.update`.

### executeSellOrder
- **Signature**: `executeSellOrder(address listingAddress, uint256 orderId, uint256 amount) public virtual returns (IMFPListing.ListingUpdateType[] memory)`
- **Description**: Combines core, pricing, and amount updates to execute a sell order.
- **Parameters**:
  - `listingAddress`: Address of the listing contract.
  - `orderId`: ID of the order.
  - `amount`: Amount to execute (normalized to 18 decimals).
- **Returns**: Array of `ListingUpdateType` combining core, pricing, and amount updates.
- **Explanation**:
  - Queries `getListingId` from `IMFPListing` to get the listing ID.
  - Calls `executeSellOrderCore`, `executeSellOrderPricing`, and `executeSellOrderAmounts` to prepare updates.
  - Combines updates into a single array, ensuring stack depth is managed (three updates total).
  - Virtual function, allowing overrides in inheriting contracts (e.g., `MFPSettlementPartial`).
  - Does not apply updates; caller must pass the returned array to `IMFPListing.update`.

### clearSingleOrder
- **Signature**: `clearSingleOrder(address listingAddress, uint256 orderId) public virtual`
- **Description**: Cancels a single order by preparing and applying a cancellation update.
- **Parameters**:
  - `listingAddress`: Address of the listing contract.
  - `orderId`: ID of the order to cancel.
- **Explanation**:
  - Queries `getListingId` from `IMFPListing`.
  - Creates a `ListingUpdateType` with `updateType = 0` (balance, used for cancellation), `index = orderId`, and `value = 0` to mark the order as cancelled.
  - Calls `IMFPListing.update` to apply the cancellation.
  - Emits `OrderCancelled` event with the listing address and order ID.
  - Virtual function, allowing overrides in inheriting contracts (e.g., `MFPRouter`).
  - In `MFPListingTemplate`, this sets the order status to 0 and removes it from `pendingBuyOrders` or `pendingSellOrders`.

### clearOrders
- **Signature**: `clearOrders(address listingAddress) public virtual`
- **Description**: Cancels all orders for a listing by preparing and applying a cancellation update.
- **Parameters**:
  - `listingAddress`: Address of the listing contract.
- **Explanation**:
  - Queries `getListingId` from `IMFPListing`.
  - Creates a `ListingUpdateType` with `updateType = 0`, `index = 0`, and `value = 0` to signal cancellation of all orders.
  - Calls `IMFPListing.update` to apply the cancellation.
  - Emits `OrderCancelled` event with `orderId = 0` to indicate bulk cancellation.
  - Virtual function, allowing overrides in inheriting contracts.
  - Implementation in `MFPListingTemplate` would clear all pending orders, but the exact behavior depends on the listing’s update logic.

## Formulas
- None explicitly defined in `MFPOrderPartial`. Related calculations:
  - **Normalization**: Uses `MFPMainPartial.normalize` to convert amounts to 18 decimals.
  - **Price Impact**: Handled by `MFPMainPartial.calculateImpactPrice`, used in inheriting contracts like `MFPSettlementPartial` for order validation.
  - **Fee Calculation**: Not applied here; handled in `MFPLiquidityTemplate` or `MFPMainPartial`.


# MFPListingTemplate and MFPLiquidityTemplate Contracts Specification

## Version
- **MFPListingTemplate**: 0.0.16 (pre-testing)
  - Replaced `liquidityAddresses` mapping with single `liquidityAddress` variable.
  - Updated `setLiquidityAddress` to set `liquidityAddress` directly, validated by `listingId`.
- **MFPLiquidityTemplate**: 0.0.20 (pre-testing)
  - Removed emoji typos, fixed `yPrepOut` and `yExecuteOut` typos.
  - Refactored `claimFees` with `ClaimData` struct to resolve stack depth.
  - Added `payable` to `addFees`, updated `xPrepOut`/`yPrepOut` for `IMFPListing.PreparedWithdrawal`.
  - Replaced `LiquidityDetails` mapping with single `LiquidityDetails` variable.
  - Added `updateRegistry`, `globalizeUpdate`, `changeSlotDepositor`, `removeSlot`.
  - Removed redundant `transferLiquidity`, `updateLiquidity`.

## Overview
`MFPListingTemplate` manages trading pairs, orders, and balances for a decentralized exchange. `MFPLiquidityTemplate` handles liquidity provision, fee accrual, and withdrawals. Both use create2 deployment, support ETH/ERC20, and integrate with `MFPAgent` and `TokenRegistry`.

## MFPListingTemplate

### State Variables
- `routerAddress: address` - Router contract address.
- `tokenA: address` - First token in pair.
- `tokenB: address` - Second token in pair.
- `listingId: uint256` - Unique listing identifier.
- `orderIdHeight: uint256` - Next available order ID.
- `agent: address` - MFPAgent contract address.
- `registryAddress: address` - TokenRegistry address.
- `lastDay: uint256` - Midnight timestamp of current day.
- `liquidityAddress: address` - Single liquidity contract address.

### Mappings
- `volumeBalances: mapping(uint256 => VolumeBalance)` - Balances and volumes per listing.
- `prices: mapping(uint256 => uint256)` - Current price per listing.
- `buyOrderCores/Pricings/Amounts: mapping(uint256 => BuyOrderCore/Pricing/Amounts)` - Buy order details.
- `sellOrderCores/Pricings/Amounts: mapping(uint256 => SellOrderCore/Pricing/Amounts)` - Sell order details.
- `isBuy/SellOrderComplete: mapping(uint256 => bool)` - Order completion status.
- `pendingBuy/SellOrders: mapping(uint256 => uint256[])` - Pending order IDs per listing.
- `makerPendingOrders: mapping(address => uint256[])` - Pending orders per maker.
- `historicalData: mapping(uint256 => HistoricalData[])` - Historical price/volume data.

### Arrays
- None.

### Structs
- `ListingUpdateType` - Update struct for orders/balances.
- `VolumeBalance` - x/y balances and volumes.
- `Buy/SellOrderCore` - Maker, recipient, status.
- `Buy/SellOrderPricing` - Max/min prices.
- `Buy/SellOrderAmounts` - Pending/filled amounts.
- `HistoricalData` - Price, balances, volumes, timestamp.

### Events
- `OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status)`
- `BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance)`
- `RegistryUpdateFailed(string reason)`

### Functions
- **setRouter/SetListingId/SetLiquidityAddress/SetTokens/SetAgent/SetRegistry**: Initialize state, require unset values.
- **normalize/denormalize**: Convert amounts to/from 18 decimals.
- **removePendingOrder**: Remove order ID from array.
- **globalizeUpdate**: Sync pending orders with `IMFPAgent.globalizeOrders`.
- **_updateRegistry**: Update `TokenRegistry` with maker balances.
- **_isSameDay/_floorToMidnight**: Handle daily timestamps.
- **_findVolumeChange**: Calculate volume change since `startTime`.
- **queryYield**: Compute APY based on daily fees and liquidity.
- **update**: Apply `ListingUpdateType` array to update orders/balances, emit events.
- **transact**: Transfer tokens, update balances/volumes, call `_updateRegistry`.
- **getListingId/nextOrderId/listingVolumeBalancesView/listingPriceView/pendingBuyOrdersView/pendingSellOrdersView/makerPendingOrdersView/getHistoricalDataView/historicalDataLengthView/getHistoricalDataByNearestTimestamp/buyOrderCoreView/buyOrderPricingView/buyOrderAmountsView/sellOrderCoreView/sellOrderPricingView/sellOrderAmountsView/isOrderCompleteView/getRegistryAddress**: View functions for state queries.

### Formulas
- **Price**: `(xBalance * 1e18) / yBalance`
- **Yield**: `(dailyFees * 1e18) / liquidity * 365`, where `dailyFees = (volumeChange * 0.0005)`.

## MFPLiquidityTemplate

### State Variables
- `routerAddress: address` - Router contract address.
- `listingAddress: address` - Listing contract address.
- `tokenA: address` - First token in pair.
- `tokenB: address` - Second token in pair.
- `listingId: uint256` - Unique listing identifier.
- `agent: address` - MFPAgent contract address.
- `liquidityDetails: LiquidityDetails` - x/y liquidity and fees.

### Mappings
- `x/yLiquiditySlots: mapping(uint256 => Slot)` - Liquidity slots per token.
- `userIndex: mapping(address => uint256[])` - Slot indices per user.

### Arrays
- `activeX/YLiquiditySlots: uint256[]` - Active slot indices.

### Structs
- `LiquidityDetails` - x/y liquidity and fees.
- `Slot` - Depositor, recipient, allocation, volume, timestamp.
- `UpdateType` - Update struct for balances/fees/slots.
- `ClaimData` - Fee claim parameters.

### Events
- `LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid)`
- `FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees)`
- `FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees)`
- `GlobalLiquidityUpdated(bool isX, uint256 amount, bool isDeposit, address caller)`
- `SlotDepositorChanged(bool isX, uint256 slotIndex, address oldDepositor, address newDepositor)`
- `RegistryUpdateFailed(string reason)`

### Functions
- **setRouter/SetListingId/SetListingAddress/SetTokens/SetAgent**: Initialize state.
- **normalize/denormalize**: Convert amounts to/from 18 decimals.
- **updateRegistry**: Sync depositor balances with `TokenRegistry`.
- **globalizeUpdate**: Sync liquidity with `IMFPAgent.globalizeLiquidity`.
- **removeSlot**: Clear slot data from mappings/arrays.
- **update**: Apply `UpdateType` array to update liquidity slots, emit events.
- **changeSlotDepositor**: Transfer slot ownership, emit event.
- **calculateFeeShare**: Compute fee share based on volume and allocation.
- **_fetchClaimData/_processFeeClaim**: Helpers for fee claims, manage stack depth.
- **claimFees**: Calculate and transfer fees, update state.
- **addFees**: Add fees, update `x/yFees`, support ETH.
- **deposit**: Deposit tokens, update slots, call `globalizeUpdate`, `updateRegistry`.
- **transact(address)**: Execute token transfers, update liquidity.
- **x/yPrepOut**: Prepare withdrawal amounts, check liquidity and price.
- **x/yExecuteOut**: Execute withdrawals, update slots, call `globalizeUpdate`, `updateRegistry`.
- **liquidityAmounts/feeAmounts/liquidityDetailsView/activeX/YLiquiditySlotsView/userIndexView/getX/YSlotView/getListingId/validateListing**: View functions for state queries.

### Formulas
- **Fee Share**: `(feesAccrued * (allocation * 1e18) / liquid) / 1e18`, where `feesAccrued = ((volume - dVolume) * 0.0005)`.


