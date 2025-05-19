// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.0.13
// Most Recent Changes:
// - From v0.0.12: Removed onlyRouter modifier from setAgent, now callable by anyone.
// - Added globalizeUpdate function to sync pending buy/sell orders with OMFAgent via globalizeOrders.
// - Modified update function to call globalizeUpdate instead of direct globalizeOrders calls.
// - Ensured globalizeUpdate is externally callable and fetches all pending orders.
// - Preserved all existing functionality (order creation via update, balance updates, transact, view functions).

import "../imports/SafeERC20.sol";

interface IOMFListing {
    function volumeBalances() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getPrice() external view returns (uint256);
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function isOrderCompleteView(uint256 orderId, bool isBuy) external view returns (bool);
    function update(UpdateType[] memory updates) external;
    function transact(address token, uint256 amount, address recipient) external;
}

interface IOMFAgent {
    function globalizeOrders(
        uint256 listingId,
        address token0,
        address baseToken,
        uint256 orderId,
        bool isBuy,
        address maker,
        address recipient,
        uint256 amount,
        uint8 status
    ) external;
}

interface IERC20 {
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

struct UpdateType {
    uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
    uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts (for updateType 1, 2)
    uint256 index;    // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
    uint256 value;    // principal or amount (normalized) or price (for historical)
    address addr;     // makerAddress
    address recipient;// recipientAddress
    uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
    uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
}

contract OMFListingTemplate {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public token0;    // Token-0 (listed token)
    address public baseToken; // Token-1 (reference token)
    uint256 public listingId;
    address public oracle;
    uint8 public oracleDecimals;
    uint256 public orderIdHeight; // Tracks next available orderId
    address public agent; // OMFAgent address

    struct ListingUpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts (for updateType 1, 2)
        uint256 index;    // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
        uint256 value;    // principal or amount (normalized) or price (for historical)
        address addr;     // makerAddress
        address recipient;// recipientAddress
        uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
        uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
    }

    struct VolumeBalance {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct BuyOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct BuyOrderAmounts {
        uint256 pending;
        uint256 filled;
    }

    struct SellOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct SellOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct SellOrderAmounts {
        uint256 pending;
        uint256 filled;
    }

    struct HistoricalData {
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        uint256 timestamp;
    }

    VolumeBalance public volumeBalance;
    address public liquidityAddress;
    uint256 public price;
    mapping(uint256 => BuyOrderCore) public buyOrderCores;
    mapping(uint256 => BuyOrderPricing) public buyOrderPricings;
    mapping(uint256 => BuyOrderAmounts) public buyOrderAmounts;
    mapping(uint256 => SellOrderCore) public sellOrderCores;
    mapping(uint256 => SellOrderPricing) public sellOrderPricings;
    mapping(uint256 => SellOrderAmounts) public sellOrderAmounts;
    mapping(uint256 => bool) public isBuyOrderComplete;
    mapping(uint256 => bool) public isSellOrderComplete;
    uint256[] public pendingBuyOrders;
    uint256[] public pendingSellOrders;
    mapping(address => uint256[]) public makerPendingOrders;
    HistoricalData[] public historicalData;

    event OrderUpdated(uint256 orderId, bool isBuy, uint8 status);
    event BalancesUpdated(uint256 xBalance, uint256 yBalance);

    constructor() {
        orderIdHeight = 0; // Initialize orderIdHeight
    }

    modifier onlyRouter() {
        require(msg.sender == routerAddress, "Router only");
        _;
    }

    function setRouter(address _routerAddress) external {
        require(routerAddress == address(0), "Router already set");
        require(_routerAddress != address(0), "Invalid router address");
        routerAddress = _routerAddress;
    }

    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setLiquidityAddress(address _liquidityAddress) external {
        require(liquidityAddress == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddress = _liquidityAddress;
    }

    function setTokens(address _token0, address _baseToken) external {
        require(token0 == address(0) && baseToken == address(0), "Tokens already set");
        require(_token0 != address(0) && _baseToken != address(0), "Tokens cannot be NATIVE");
        require(_token0 != _baseToken, "Tokens must be different");
        token0 = _token0;
        baseToken = _baseToken;
    }

    function setOracle(address _oracle, uint8 _oracleDecimals) external {
        require(oracle == address(0), "Oracle already set");
        require(_oracle != address(0), "Invalid oracle");
        oracle = _oracle;
        oracleDecimals = _oracleDecimals;
    }

    function setAgent(address _agent) external {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function globalizeUpdate() external {
        if (agent == address(0)) return;

        // Sync pending buy orders
        for (uint256 i = 0; i < pendingBuyOrders.length; i++) {
            uint256 orderId = pendingBuyOrders[i];
            BuyOrderCore memory core = buyOrderCores[orderId];
            BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
            if (core.status == 1 || core.status == 2) { // Pending or partially filled
                try IOMFAgent(agent).globalizeOrders(
                    listingId,
                    token0,
                    baseToken,
                    orderId,
                    true,
                    core.makerAddress,
                    core.recipientAddress,
                    amounts.pending,
                    core.status
                ) {} catch {}
            }
        }

        // Sync pending sell orders
        for (uint256 i = 0; i < pendingSellOrders.length; i++) {
            uint256 orderId = pendingSellOrders[i];
            SellOrderCore memory core = sellOrderCores[orderId];
            SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
            if (core.status == 1 || core.status == 2) { // Pending or partially filled
                try IOMFAgent(agent).globalizeOrders(
                    listingId,
                    token0,
                    baseToken,
                    orderId,
                    false,
                    core.makerAddress,
                    core.recipientAddress,
                    amounts.pending,
                    core.status
                ) {} catch {}
            }
        }
    }

    function getPrice() external view returns (uint256) {
        (bool success, bytes memory returnData) = oracle.staticcall(abi.encodeWithSignature("latestPrice()"));
        require(success, "Price fetch failed");
        uint256 priceValue = abi.decode(returnData, (uint256));
        return oracleDecimals == 8 ? priceValue * 1e10 : priceValue; // Scale to 18 decimals
    }

    function nextOrderId() external onlyRouter returns (uint256) {
        return orderIdHeight++; // Return current and increment
    }

    function update(ListingUpdateType[] memory updates) external onlyRouter {
        VolumeBalance storage balances = volumeBalance;

        for (uint256 i = 0; i < updates.length; i++) {
            ListingUpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) balances.xBalance = u.value;       // Set xBalance
                else if (u.index == 1) balances.yBalance = u.value;  // Set yBalance
                else if (u.index == 2) balances.xVolume += u.value;  // Increase xVolume
                else if (u.index == 3) balances.yVolume += u.value;  // Increase yVolume
            } else if (u.updateType == 1) { // Buy order update
                if (u.structId == 0) { // Core
                    BuyOrderCore storage core = buyOrderCores[u.index];
                    if (core.makerAddress == address(0)) { // New order
                        u.index = orderIdHeight++; // Assign and increment orderId
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingBuyOrders.push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                        emit OrderUpdated(u.index, true, 1);
                    } else if (u.value == 0) { // Cancel order
                        core.status = 0;
                        removePendingOrder(pendingBuyOrders, u.index);
                        removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        isBuyOrderComplete[u.index] = false;
                        emit OrderUpdated(u.index, true, 0);
                    }
                } else if (u.structId == 1) { // Pricing
                    BuyOrderPricing storage pricing = buyOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) { // Amounts
                    BuyOrderAmounts storage amounts = buyOrderAmounts[u.index];
                    BuyOrderCore storage core = buyOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) { // New amounts
                        amounts.pending = u.value;
                        balances.yBalance += u.value; // Deposit increases yBalance
                        balances.yVolume += u.value;  // Track order volume
                    } else if (core.status == 1) { // Fill order
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        balances.xBalance -= u.value; // Reduce xBalance on fill
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(pendingBuyOrders, u.index);
                            removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                            isBuyOrderComplete[u.index] = false;
                        }
                        emit OrderUpdated(u.index, true, core.status);
                    }
                }
                // Check completeness
                if (buyOrderCores[u.index].makerAddress != address(0) &&
                    buyOrderPricings[u.index].maxPrice != 0 &&
                    buyOrderAmounts[u.index].pending != 0) {
                    isBuyOrderComplete[u.index] = true;
                }
            } else if (u.updateType == 2) { // Sell order update
                if (u.structId == 0) { // Core
                    SellOrderCore storage core = sellOrderCores[u.index];
                    if (core.makerAddress == address(0)) { // New order
                        u.index = orderIdHeight++; // Assign and increment orderId
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingSellOrders.push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                        emit OrderUpdated(u.index, false, 1);
                    } else if (u.value == 0) { // Cancel order
                        core.status = 0;
                        removePendingOrder(pendingSellOrders, u.index);
                        removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        isSellOrderComplete[u.index] = false;
                        emit OrderUpdated(u.index, false, 0);
                    }
                } else if (u.structId == 1) { // Pricing
                    SellOrderPricing storage pricing = sellOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) { // Amounts
                    SellOrderAmounts storage amounts = sellOrderAmounts[u.index];
                    SellOrderCore storage core = sellOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) { // New amounts
                        amounts.pending = u.value;
                        balances.xBalance += u.value; // Deposit increases xBalance
                        balances.xVolume += u.value;  // Track order volume
                    } else if (core.status == 1) { // Fill order
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        balances.yBalance -= u.value; // Reduce yBalance on fill
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(pendingSellOrders, u.index);
                            removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                            isSellOrderComplete[u.index] = false;
                        }
                        emit OrderUpdated(u.index, false, core.status);
                    }
                }
                // Check completeness
                if (sellOrderCores[u.index].makerAddress != address(0) &&
                    sellOrderPricings[u.index].maxPrice != 0 &&
                    sellOrderAmounts[u.index].pending != 0) {
                    isSellOrderComplete[u.index] = true;
                }
            } else if (u.updateType == 3) { // Historical data
                historicalData.push(HistoricalData(
                    u.value, // price
                    u.maxPrice >> 128, u.maxPrice & ((1 << 128) - 1), // xBalance, yBalance
                    u.minPrice >> 128, u.minPrice & ((1 << 128) - 1), // xVolume, yVolume
                    block.timestamp
                ));
            }
        }

        if (balances.xBalance > 0 && balances.yBalance > 0) {
            price = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(balances.xBalance, balances.yBalance);

        // Sync all pending orders with agent
        globalizeUpdate();
    }

    function transact(address token, uint256 amount, address recipient) external onlyRouter {
        VolumeBalance storage balances = volumeBalance;
        uint8 decimals = IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (token == token0) {
            require(balances.xBalance >= normalizedAmount, "Insufficient xBalance");
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
            IERC20(token).safeTransfer(recipient, amount);
        } else if (token == baseToken) {
            require(balances.yBalance >= normalizedAmount, "Insufficient yBalance");
            balances.yBalance -= normalizedAmount;
            balances.yVolume += normalizedAmount;
            IERC20(token).safeTransfer(recipient, amount);
        } else {
            revert("Invalid token");
        }

        if (balances.xBalance > 0 && balances.yBalance > 0) {
            price = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(balances.xBalance, balances.yBalance);
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10**(18 - decimals);
        else return amount / 10**(decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - decimals);
        else return amount * 10**(decimals - 18);
    }

    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    // View functions
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        VolumeBalance memory bal = volumeBalance;
        return (bal.xBalance, bal.yBalance, bal.xVolume, bal.yVolume);
    }

    function listingPriceView() external view returns (uint256) {
        return price;
    }

    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return pendingBuyOrders;
    }

    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return pendingSellOrders;
    }

    function makerPendingOrdersView(address maker) external view returns (uint256[] memory) {
        return makerPendingOrders[maker];
    }

    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory) {
        require(index < historicalData.length, "Invalid index");
        return historicalData[index];
    }

    function historicalDataLengthView() external view returns (uint256) {
        return historicalData.length;
    }

    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = buyOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = buyOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled) {
        BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled);
    }

    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = sellOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = sellOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled) {
        SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled);
    }

    function isOrderCompleteView(uint256 orderId, bool isBuy) external view returns (bool) {
        return isBuy ? isBuyOrderComplete[orderId] : isSellOrderComplete[orderId];
    }
}