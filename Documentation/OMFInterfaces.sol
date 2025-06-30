/*
SPDX-License-Identifier: BSD-3-Clause
*/

// Specifying Solidity version for compatibility
pragma solidity ^0.8.2;

// Version: 0.0.2

// Interface for OMFListingTemplate
interface IOMFListingTemplate {
    // Structs
    struct VolumeBalance {
        uint256 xBalance; // Token0 balance
        uint256 yBalance; // BaseToken balance
        uint256 xVolume; // Token0 volume
        uint256 yVolume; // BaseToken volume
    }

    struct BuyOrderCore {
        address makerAddress; // Order creator
        address recipientAddress; // Order recipient
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct BuyOrderPricing {
        uint256 maxPrice; // Maximum price
        uint256 minPrice; // Minimum price
    }

    struct BuyOrderAmounts {
        uint256 pending; // Amount of baseToken pending
        uint256 filled; // Amount of baseToken filled
        uint256 amountSent; // Amount of token0 sent during settlement
    }

    struct SellOrderCore {
        address makerAddress; // Order creator
        address recipientAddress; // Order recipient
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct SellOrderPricing {
        uint256 maxPrice; // Maximum price
        uint256 minPrice; // Minimum price
    }

    struct SellOrderAmounts {
        uint256 pending; // Amount of token0 pending
        uint256 filled; // Amount of token0 filled
        uint256 amountSent; // Amount of baseToken sent during settlement
    }

    struct LastDayFee {
        uint256 xFees; // Token0 fees at midnight
        uint256 yFees; // BaseToken fees at midnight
        uint256 timestamp; // Midnight timestamp
    }

    struct HistoricalData {
        uint256 price; // Price at timestamp
        uint256 xBalance; // Token0 balance
        uint256 yBalance; // BaseToken balance
        uint256 xVolume; // Token0 volume
        uint256 yVolume; // BaseToken volume
        uint256 timestamp; // Data timestamp
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId; // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index; // orderId or slot index
        uint256 value; // principal or amount (normalized) or price (for historical)
        address addr; // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
        uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
        uint256 amountSent; // Amount of opposite token sent during settlement
    }

    // External functions
    function setRouters(address[] memory routers) external; // Sets router addresses
    function setListingId(uint256 listingId) external; // Sets listing ID
    function setLiquidityAddress(address liquidityAddress) external; // Sets liquidity contract address
    function setTokens(address token0, address baseToken) external; // Sets token addresses
    function setOracleDetails(address oracle, uint8 oracleDecimals, bytes4 viewFunction) external; // Sets oracle details
    function setAgent(address agent) external; // Sets agent address
    function setRegistry(address registryAddress) external; // Sets registry address
    function nextOrderId() external returns (uint256); // Returns and increments order ID
    function update(address caller, UpdateType[] memory updates) external; // Updates balances or orders
    function transact(address caller, address token, uint256 amount, address recipient) external; // Handles token transfers
    function queryYield(bool isX, uint256 maxIterations) external view returns (uint256); // Queries annualized yield

    // View functions for state variables and mappings
    function routersView(address router) external view returns (bool); // Returns router status
    function routersSetView() external view returns (bool); // Returns routersSet flag
    function token0View() external view returns (address); // Returns token0 address
    function baseTokenView() external view returns (address); // Returns baseToken address
    function decimals0View() external view returns (uint8); // Returns token0 decimals
    function baseTokenDecimalsView() external view returns (uint8); // Returns baseToken decimals
    function listingIdView() external view returns (uint256); // Returns listing ID
    function oracleView() external view returns (address); // Returns oracle address
    function oracleDecimalsView() external view returns (uint8); // Returns oracle decimals
    function oracleViewFunctionView() external view returns (bytes4); // Returns oracle view function selector
    function agentView() external view returns (address); // Returns agent address
    function registryAddressView() external view returns (address); // Returns registry address
    function liquidityAddressView(uint256 listingId) external view returns (address); // Returns liquidity address
    function orderIdHeightView() external view returns (uint256); // Returns next order ID
    function lastDayFeeView() external view returns (uint256 xFees, uint256 yFees, uint256 timestamp); // Returns last day fee data
    function volumeBalanceView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume); // Returns volume balances
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status); // Returns buy order core
    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice); // Returns buy order pricing
    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent); // Returns buy order amounts
    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status); // Returns sell order core
    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice); // Returns sell order pricing
    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent); // Returns sell order amounts
    function isOrderCompleteView(uint256 orderId, bool isBuy) external view returns (bool); // Returns order completion status
    function pendingBuyOrdersView() external view returns (uint256[] memory); // Returns pending buy order IDs
    function pendingSellOrdersView() external view returns (uint256[] memory); // Returns pending sell order IDs
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory); // Returns maker's pending orders
    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory); // Returns historical data by index
    function historicalDataLengthView() external view returns (uint256); // Returns historical data length
    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory); // Returns historical data by timestamp
    function prices(uint256 listingId) external view returns (uint256); // Returns oracle price
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance); // Returns volume balances
    function getPrice() external view returns (uint256); // Returns oracle price
}

// Interface for OMFLiquidityTemplate
interface IOMFLiquidityTemplate {
    // Structs
    struct LiquidityDetails {
        uint256 xLiquid; // Token-A liquidity
        uint256 yLiquid; // Token-B liquidity
        uint256 xFees; // Token-A fees
        uint256 yFees; // Token-B fees
    }

    struct Slot {
        address depositor; // Slot owner
        address recipient; // Not used
        uint256 allocation; // Allocated liquidity
        uint256 dVolume; // Volume at deposit
        uint256 timestamp; // Deposit timestamp
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index; // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value; // Amount or allocation (normalized)
        address addr; // Depositor
        address recipient; // Not used
    }

    struct PreparedWithdrawal {
        uint256 amountA; // Token-A withdrawal amount
        uint256 amountB; // Token-B withdrawal amount
    }

    // External functions
    function setRouters(address[] memory routers) external; // Sets router addresses
    function setListingId(uint256 listingId) external; // Sets listing ID
    function setListingAddress(address listingAddress) external; // Sets listing contract address
    function setTokens(address tokenA, address tokenB) external; // Sets token addresses
    function setAgent(address agent) external; // Sets agent address
    function update(address caller, UpdateType[] memory updates) external; // Updates liquidity or fees
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external; // Changes slot depositor
    function deposit(address caller, address token, uint256 amount) external; // Deposits tokens
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory); // Prepares tokenA withdrawal
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external; // Executes tokenA withdrawal
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory); // Prepares tokenB withdrawal
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external; // Executes tokenB withdrawal
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external; // Claims fees
    function transact(address caller, address token, uint256 amount, address recipient) external; // Handles token transfers
    function addFees(address caller, bool isX, uint256 fee) external; // Adds fees
    function updateLiquidity(address caller, bool isX, uint256 amount) external; // Updates liquidity balances

    // View functions for state variables and mappings
    function routersView(address router) external view returns (bool); // Returns router status
    function routersSetView() external view returns (bool); // Returns routersSet flag
    function listingAddressView() external view returns (address); // Returns listing address
    function tokenAView() external view returns (address); // Returns tokenA address
    function tokenBView() external view returns (address); // Returns tokenB address
    function decimalAView() external view returns (uint8); // Returns tokenA decimals
    function decimalBView() external view returns (uint8); // Returns tokenB decimals
    function listingIdView() external view returns (uint256); // Returns listing ID
    function agentView() external view returns (address); // Returns agent address
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees); // Returns liquidity details
    function activeXLiquiditySlotsView() external view returns (uint256[] memory); // Returns active tokenA slots
    function activeYLiquiditySlotsView() external view returns (uint256[] memory); // Returns active tokenB slots
    function userIndexView(address user) external view returns (uint256[] memory); // Returns user slot indices
    function getXSlotView(uint256 index) external view returns (Slot memory); // Returns tokenA slot
    function getYSlotView(uint256 index) external view returns (Slot memory); // Returns tokenB slot
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount); // Returns liquidity amounts
    function getListingAddress(uint256 listingId) external view returns (address); // Returns listing address
}

// Interface for OMFAgent
interface IOMFAgent {
    // Structs
    struct GlobalOrder {
        uint256 orderId; // Unique order identifier
        bool isBuy; // True if buy order
        address maker; // Order creator
        address recipient; // Order recipient
        uint256 amount; // Order amount
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp; // Order creation/update time
    }

    struct PrepData {
        bytes32 listingSalt; // Salt for listing deployment
        bytes32 liquiditySalt; // Salt for liquidity deployment
        address tokenA; // Token-0
        address oracleAddress; // Oracle contract address
        uint8 oracleDecimals; // Oracle price decimals
        bytes4 oracleViewFunction; // Oracle view function selector
    }

    struct InitData {
        address listingAddress; // Deployed listing address
        address liquidityAddress; // Deployed liquidity address
        address tokenA; // Token-0
        address tokenB; // BaseToken
        uint256 listingId; // Listing identifier
        address oracleAddress; // Oracle contract address
        uint8 oracleDecimals; // Oracle price decimals
        bytes4 oracleViewFunction; // Oracle view function selector
    }

    struct TrendData {
        address token; // Token address
        uint256 timestamp; // Timestamp of data point
        uint256 amount; // Amount (liquidity or volume)
    }

    struct OrderData {
        uint256 orderId; // Order identifier
        bool isBuy; // True if buy order
        address maker; // Order creator
        address recipient; // Order recipient
        uint256 amount; // Order amount.FL
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp; // Order creation/update time
    }

    // External functions
    function setProxyRouter(address proxyRouter) external; // Sets proxy router address
    function setListingLogic(address listingLogic) external; // Sets listing logic address
    function setLiquidityLogic(address liquidityLogic) external; // Sets liquidity logic address
    function setBaseToken(address baseToken) external; // Sets base token address
    function setRegistry(address registryAddress) external; // Sets registry address
    function listToken(
        address tokenA,
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) external returns (address listingAddress, address liquidityAddress); // Lists a token pair
    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) external; // Updates global liquidity
    function globalizeOrders(
        uint256 listingId,
        address tokenA,
        address tokenB,
        uint256 orderId,
        bool isBuy,
        address maker,
        address recipient,
        uint256 amount,
        uint8 status
    ) external; // Updates global orders

    // View functions for state variables and mappings
    function proxyRouterView() external view returns (address); // Returns proxy router address
    function listingLogicAddressView() external view returns (address); // Returns listing logic address
    function liquidityLogicAddressView() external view returns (address); // Returns liquidity logic address
    function baseTokenView() external view returns (address); // Returns base token address
    function registryAddressView() external view returns (address); // Returns registry address
    function listingCountView() external view returns (uint256); // Returns total listing count
    function getListingView(address tokenA, address tokenB) external view returns (address); // Returns listing address
    function allListingsLengthView() external view returns (uint256); // Returns all listings length
    function allListedTokensLengthView() external view returns (uint256); // Returns all listed tokens length
    function validateListing(address listingAddress) external view returns (bool, address, address, address); // Validates listing
    function getPairLiquidityTrend(
        address tokenA,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts); // Returns pair liquidity trend
    function getUserLiquidityTrend(
        address user,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts); // Returns user liquidity trend
    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts); // Returns user liquidity across pairs
    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory users, uint256[] memory amounts); // Returns top liquidity providers
    function getUserLiquidityShare(address user, address tokenA, address tokenB)
        external view returns (uint256 share, uint256 total); // Returns user liquidity share
    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts); // Returns pairs by liquidity
    function getOrderActivityByPair(
        address tokenA,
        address tokenB,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory orderIds, OrderData[] memory orders); // Returns order activity
    function getUserTradingProfile(address user)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes); // Returns user trading profile
    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory traders, uint256[] memory volumes); // Returns top traders by volume
    function getAllPairsByOrderVolume(uint256 minVolume, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes); // Returns pairs by order volume
    function queryByIndex(uint256 index) external view returns (address); // Returns listing by index
    function queryByAddressView(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory); // Returns listing indices by token
    function queryByAddressLength(address target) external view returns (uint256); // Returns number of listings for token
}