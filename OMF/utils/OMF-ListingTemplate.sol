// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.0.21
// Most Recent Changes:
// - From v0.0.20: Renamed registryAddress function to getRegistryAddress to resolve naming conflict with state variable (line 77).
// - Changed updateRegistry to _updateRegistry with internal visibility to resolve undeclared identifier error in transact (line 564).
// - From v0.0.19: Changed globalizeUpdate visibility to internal to resolve undeclared identifier error (line 369).
// - Removed 'this.' from globalizeUpdate call in update function.
// - From v0.0.18: Corrected _findVolumeChange to calculate volume difference from lastDay (midnight) to present timestamp.
// - Iterates historicalData backwards to find first entry with timestamp >= lastDay, uses earliest entry as fallback.
// - From v0.0.17: Made maxIterations a caller-provided parameter in queryYield.
// - From v0.0.16: Added lastDay to track first volume update per day, optimized queryYield with internal helpers.
// - From v0.0.15: Updated queryYield to check current-day updates.
// - Preserved all existing functionality (order creation, balance updates, transact, view functions).

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
    function queryYield(bool isX, uint256 maxIterations) external view returns (uint256);
    function getRegistryAddress() external view returns (address);
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

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

interface IOMFLiquidityTemplate {
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
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
    address public registryAddress; // TokenRegistry address
    uint256 public lastDay; // Timestamp of first volume update of current day (midnight)

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
    event RegistryUpdateFailed(string reason);

    constructor() {
        orderIdHeight = 0; // Initialize orderIdHeight
        lastDay = 0; // Initialize lastDay
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

    function setRegistry(address _registryAddress) external {
        require(registryAddress == address(0), "Registry already set");
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    function globalizeUpdate() internal {
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

    function _updateRegistry() internal {
        if (registryAddress == address(0)) {
            emit RegistryUpdateFailed("Registry not set");
            return;
        }

        // Randomly select buy or sell orders (0 = buy, 1 = sell)
        bool isBuy = block.timestamp % 2 == 0;
        uint256[] memory orders = isBuy ? pendingBuyOrders : pendingSellOrders;
        address token = isBuy ? baseToken : token0;

        if (orders.length == 0) {
            emit RegistryUpdateFailed("No pending orders");
            return;
        }

        // Collect unique maker addresses
        address[] memory tempMakers = new address[](orders.length);
        uint256 makerCount = 0;
        for (uint256 i = 0; i < orders.length; i++) {
            address maker = isBuy ? buyOrderCores[orders[i]].makerAddress : sellOrderCores[orders[i]].makerAddress;
            if (maker != address(0)) {
                bool exists = false;
                for (uint256 j = 0; j < makerCount; j++) {
                    if (tempMakers[j] == maker) {
                        exists = true;
                        break;
                    }
                }
                if (!exists) {
                    tempMakers[makerCount] = maker;
                    makerCount++;
                }
            }
        }

        // Resize array to unique makers
        address[] memory makers = new address[](makerCount);
        for (uint256 i = 0; i < makerCount; i++) {
            makers[i] = tempMakers[i];
        }

        // Call initializeBalances on TokenRegistry
        try ITokenRegistry(registryAddress).initializeBalances(token, makers) {} catch {
            emit RegistryUpdateFailed("Registry update failed");
        }
    }

    function _isSameDay(uint256 time1, uint256 time2) internal pure returns (bool) {
        uint256 midnight1 = time1 - (time1 % 86400);
        uint256 midnight2 = time2 - (time2 % 86400);
        return midnight1 == midnight2;
    }

    function _floorToMidnight(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 86400);
    }

    function _findVolumeChange(bool isX, uint256 startTime, uint256 maxIterations) internal view returns (uint256) {
        VolumeBalance memory bal = volumeBalance;
        uint256 currentVolume = isX ? bal.xVolume : bal.yVolume;
        uint256 iterationsLeft = maxIterations;
        uint256 volumeChange = 0;

        if (historicalData.length == 0) {
            return 0; // No data
        }

        // Find first entry with timestamp >= startTime (midnight of current day)
        for (uint256 i = historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = historicalData[i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                volumeChange = currentVolume - (isX ? data.xVolume : data.yVolume);
                return volumeChange;
            }
        }

        // Fallback: Use earliest entry if no entry found since startTime
        if (iterationsLeft == 0 || historicalData.length <= maxIterations) {
            HistoricalData memory earliest = historicalData[0];
            volumeChange = currentVolume - (isX ? earliest.xVolume : earliest.yVolume);
            return volumeChange;
        }

        return 0; // No valid entry found
    }

    function queryYield(bool isX, uint256 maxIterations) external view returns (uint256) {
        require(maxIterations > 0, "Invalid maxIterations");

        // Check if lastDay is set and has updates today
        if (lastDay == 0 || historicalData.length == 0 || !_isSameDay(block.timestamp, lastDay)) {
            return 0; // No updates today
        }

        // Find volume change from lastDay (midnight) to now
        uint256 volumeChange = _findVolumeChange(isX, lastDay, maxIterations);
        if (volumeChange == 0) {
            return 0; // No valid historical data
        }

        // Fetch liquidity from OMFLiquidityTemplate
        uint256 liquidity = 0;
        try IOMFLiquidityTemplate(liquidityAddress).liquidityAmounts() returns (uint256 xLiquid, uint256 yLiquid) {
            liquidity = isX ? xLiquid : yLiquid;
        } catch {
            return 0; // Graceful degradation
        }

        // Calculate fees (0.05% rate)
        uint256 dailyFees = (volumeChange * 5) / 10000;
        if (liquidity == 0) return 0;

        // Calculate APY
        uint256 dailyYield = (dailyFees * 1e18) / liquidity;
        uint256 apy = dailyYield * 365;
        return apy;
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

        // Update lastDay for volume changes
        bool volumeUpdated = false;
        for (uint256 i = 0; i < updates.length; i++) {
            ListingUpdateType memory u = updates[i];
            if (u.updateType == 0 && (u.index == 2 || u.index == 3)) {
                volumeUpdated = true;
                break;
            } else if (u.updateType == 1 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
                break;
            } else if (u.updateType == 2 && u.structId == 2 && u.value > 0) {
                volumeUpdated = true;
                break;
            }
        }
        if (volumeUpdated && (lastDay == 0 || block.timestamp >= lastDay + 86400)) {
            lastDay = _floorToMidnight(block.timestamp);
        }

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

        // Update lastDay for volume changes
        if (lastDay == 0 || block.timestamp >= lastDay + 86400) {
            lastDay = _floorToMidnight(block.timestamp);
        }

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

        // Update registry with pending orders
        _updateRegistry();
        globalizeUpdate();
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

    function getRegistryAddress() external view returns (address) {
        return registryAddress;
    }
}