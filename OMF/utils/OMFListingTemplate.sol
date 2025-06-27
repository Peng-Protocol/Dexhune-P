/*
SPDX-License-Identifier: BSD-3-Clause
*/

// Specifying Solidity version for compatibility
pragma solidity ^0.8.2;

// Version: 0.0.29
// Changes:
// - v0.0.29: Fixed TypeError in getPrice at line 478 by removing invalid try-catch block for decodePrice, as try-catch is only allowed for external calls or contract creation; decodePrice is now called directly.
// - v0.0.28: Fixed TypeError in getPrice at line 477 by removing 'this.' from decodePrice call, as decodePrice is a private function within the same contract.
// - v0.0.27: Fixed DeclarationError by moving UpdateType struct from contract (line 194) to IOMFListing interface to resolve undefined identifier in update function (line 40).
// - v0.0.26: Fixed ParserError by replacing illegal character '_陰日' with '_lastDayFee.timestamp' in update function (line 521).
// - v0.0.25: Removed balance-based price calculation in update and transact functions. Price now sourced exclusively from getPrice() (oracle). Updated prices function to use getPrice(). Removed _price state variable. Ensured compatibility with OMFLiquidityTemplate.sol by aligning IOMFListing interface and price handling.
// - v0.0.24: Modified getPrice to handle int256 oracle return type, with checks for non-negative values and decoding errors. Updated update function to use new getPrice logic.
// - v0.0.23: Integrated oracle pricing in update function to validate buy/sell order maxPrice and minPrice against getPrice oracle price. Added try-catch for oracle calls in update.
// - v0.0.22: Integrated SSListingTemplate.sol features: added amountSent to BuyOrderAmounts and SellOrderAmounts, replaced lastDay with LastDayFee struct for queryYield, added ReentrancyGuard for update and transact, replaced setRouter with setRouters using routers mapping. Updated IOMFListing interface for SSListing compatibility (prices, volumeBalances). Restricted to ERC-20 tokens only (no ETH support). Excluded payout-related structs and functions. Ensured OMFAgent.sol compatibility.
// - v0.0.21: Renamed registryAddress function to getRegistryAddress to resolve naming conflict.
// - v0.0.20: Changed updateRegistry to _updateRegistry with internal visibility.
// - v0.0.19: Changed globalizeUpdate visibility to internal.
// - v0.0.18: Corrected _findVolumeChange to calculate volume difference from lastDay.
// - v0.0.17: Made maxIterations a caller-provided parameter in queryYield.
// - v0.0.16: Added lastDayFee to track volume updates, optimized queryYield.
// - v0.0.15: Updated queryYield to check current-day updates.

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

// Defining interface for OMFListing
interface IOMFListing {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId; // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index; // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
        uint256 value; // principal or amount (normalized) or price (for historical)
        address addr; // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
        uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
        uint256 amountSent; // Amount of opposite token sent during settlement
    }
    function prices(uint256) external view returns (uint256); // Ignores listingId, returns oracle price
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance); // Ignores listingId
    function liquidityAddressView(uint256) external view returns (address); // Ignores listingId
    function token0() external view returns (address); // Returns token0
    function baseToken() external view returns (address); // Returns baseToken
    function decimals0() external view returns (uint8); // Returns token0 decimals
    function baseTokenDecimals() external view returns (uint8); // Returns baseToken decimals
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function isOrderCompleteView(uint256 orderId, bool isBuy) external view returns (bool);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function queryYield(bool isX, uint256 maxIterations) external view returns (uint256);
    function getRegistryAddress() external view returns (address);
    function getPrice() external view returns (uint256); // Returns oracle price
}

// Defining interface for OMFAgent
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

// Defining interface for TokenRegistry
interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

// Defining interface for OMFLiquidityTemplate
interface IOMFLiquidityTemplate {
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
}

contract OMFListingTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables (hidden, accessed via view functions)
    mapping(address => bool) private _routers; // Maps router addresses
    bool private _routersSet; // Flag for router initialization
    address private _token0; // Token-0 (listed token)
    address private _baseToken; // Token-1 (reference token)
    uint8 private _decimal0; // Token-0 decimals
    uint8 private _baseTokenDecimals; // BaseToken decimals
    uint256 private _listingId; // Listing identifier
    address private _oracle; // Oracle contract address
    uint8 private _oracleDecimals; // Oracle price decimals
    address private _agent; // OMFAgent address
    address private _registryAddress; // TokenRegistry address
    address private _liquidityAddress; // Liquidity contract address
    uint256 private _orderIdHeight; // Tracks next available orderId
    struct LastDayFee {
        uint256 xFees; // Token0 fees at midnight
        uint256 yFees; // BaseToken fees at midnight
        uint256 timestamp; // Midnight timestamp
    }
    LastDayFee private _lastDayFee; // Tracks daily fees
    VolumeBalance private _volumeBalance; // Tracks balances and volumes

    // Mappings and arrays for orders
    mapping(uint256 => BuyOrderCore) private _buyOrderCores; // Buy order core data
    mapping(uint256 => BuyOrderPricing) private _buyOrderPricings; // Buy order pricing
    mapping(uint256 => BuyOrderAmounts) private _buyOrderAmounts; // Buy order amounts
    mapping(uint256 => SellOrderCore) private _sellOrderCores; // Sell order core data
    mapping(uint256 => SellOrderPricing) private _sellOrderPricings; // Sell order pricing
    mapping(uint256 => SellOrderAmounts) private _sellOrderAmounts; // Sell order amounts
    mapping(uint256 => bool) private _isBuyOrderComplete; // Tracks buy order completeness
    mapping(uint256 => bool) private _isSellOrderComplete; // Tracks sell order completeness
    uint256[] private _pendingBuyOrders; // Array of pending buy order IDs
    uint256[] private _pendingSellOrders; // Array of pending sell order IDs
    mapping(address => uint256[]) private _makerPendingOrders; // Maker address to order IDs
    HistoricalData[] private _historicalData; // Historical price and balance data

    // Structs for data management
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

    struct HistoricalData {
        uint256 price; // Price at timestamp
        uint256 xBalance; // Token0 balance
        uint256 yBalance; // BaseToken balance
        uint256 xVolume; // Token0 volume
        uint256 yVolume; // BaseToken volume
        uint256 timestamp; // Data timestamp
    }

    // Events for tracking actions
    event OrderUpdated(uint256 orderId, bool isBuy, uint8 status);
    event BalancesUpdated(uint256 xBalance, uint256 yBalance);
    event RegistryUpdateFailed(string reason);

    // Constructor (empty, initialized via setters)
    constructor() {}

    // Modifier for router-only access
    modifier onlyRouter() {
        require(_routers[msg.sender], "Router only");
        _;
    }

    // View function for routers mapping
    function routersView(address router) external view returns (bool) {
        return _routers[router];
    }

    // View function for routersSet
    function routersSetView() external view returns (bool) {
        return _routersSet;
    }

    // View function for token0
    function token0View() external view returns (address) {
        return _token0;
    }

    // View function for baseToken
    function baseTokenView() external view returns (address) {
        return _baseToken;
    }

    // View function for token0 decimals
    function decimals0View() external view returns (uint8) {
        return _decimal0;
    }

    // View function for baseToken decimals
    function baseTokenDecimalsView() external view returns (uint8) {
        return _baseTokenDecimals;
    }

    // View function for listingId
    function listingIdView() external view returns (uint256) {
        return _listingId;
    }

    // View function for oracle
    function oracleView() external view returns (address) {
        return _oracle;
    }

    // View function for oracleDecimals
    function oracleDecimalsView() external view returns (uint8) {
        return _oracleDecimals;
    }

    // View function for agent
    function agentView() external view returns (address) {
        return _agent;
    }

    // View function for registryAddress
    function registryAddressView() external view returns (address) {
        return _registryAddress;
    }

    // View function for liquidityAddress
    function liquidityAddressView(uint256) external view returns (address) {
        return _liquidityAddress;
    }

    // View function for orderIdHeight
    function orderIdHeightView() external view returns (uint256) {
        return _orderIdHeight;
    }

    // View function for lastDayFee
    function lastDayFeeView() external view returns (uint256 xFees, uint256 yFees, uint256 timestamp) {
        LastDayFee memory fee = _lastDayFee;
        return (fee.xFees, fee.yFees, fee.timestamp);
    }

    // View function for volumeBalance
    function volumeBalanceView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        VolumeBalance memory bal = _volumeBalance;
        return (bal.xBalance, bal.yBalance, bal.xVolume, bal.yVolume);
    }

    // Sets router addresses
    function setRouters(address[] memory routers) external {
        require(!_routersSet, "Routers already set");
        require(routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < routers.length; i++) {
            require(routers[i] != address(0), "Invalid router address");
            _routers[routers[i]] = true;
        }
        _routersSet = true;
    }

    // Sets listing ID
    function setListingId(uint256 listingId) external {
        require(_listingId == 0, "Listing ID already set");
        _listingId = listingId;
    }

    // Sets liquidity address
    function setLiquidityAddress(address liquidityAddress) external {
        require(_liquidityAddress == address(0), "Liquidity already set");
        require(liquidityAddress != address(0), "Invalid liquidity address");
        _liquidityAddress = liquidityAddress;
    }

    // Sets token addresses and decimals
    function setTokens(address token0, address baseToken) external {
        require(_token0 == address(0) && _baseToken == address(0), "Tokens already set");
        require(token0 != address(0) && baseToken != address(0), "Tokens must be ERC-20");
        require(token0 != baseToken, "Tokens must be different");
        _token0 = token0;
        _baseToken = baseToken;
        _decimal0 = IERC20(token0).decimals();
        _baseTokenDecimals = IERC20(baseToken).decimals();
    }

    // Sets oracle details
    function setOracle(address oracle, uint8 oracleDecimals) external {
        require(_oracle == address(0), "Oracle already set");
        require(oracle != address(0), "Invalid oracle");
        _oracle = oracle;
        _oracleDecimals = oracleDecimals;
    }

    // Sets agent address
    function setAgent(address agent) external {
        require(_agent == address(0), "Agent already set");
        require(agent != address(0), "Invalid agent address");
        _agent = agent;
    }

    // Sets registry address
    function setRegistry(address registryAddress) external {
        require(_registryAddress == address(0), "Registry already set");
        require(registryAddress != address(0), "Invalid registry address");
        _registryAddress = registryAddress;
    }

    // Normalizes amount to 18 decimals
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    // Denormalizes amount from 18 decimals to token decimals
    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    // Checks if two timestamps are on the same day
    function _isSameDay(uint256 time1, uint256 time2) internal pure returns (bool) {
        uint256 midnight1 = time1 - (time1 % 86400);
        uint256 midnight2 = time2 - (time2 % 86400);
        return midnight1 == midnight2;
    }

    // Floors timestamp to midnight
    function _floorToMidnight(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 86400);
    }

    // Finds volume change for token0 or baseToken
    function _findVolumeChange(bool isX, uint256 startTime, uint256 maxIterations) internal view returns (uint256) {
        VolumeBalance memory bal = _volumeBalance;
        uint256 currentVolume = isX ? bal.xVolume : bal.yVolume;
        uint256 iterationsLeft = maxIterations;
        if (_historicalData.length == 0) return 0;
        for (uint256 i = _historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = _historicalData[i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                return currentVolume - (isX ? data.xVolume : data.yVolume);
            }
        }
        if (iterationsLeft == 0 || _historicalData.length <= maxIterations) {
            HistoricalData memory earliest = _historicalData[0];
            return currentVolume - (isX ? earliest.xVolume : earliest.yVolume);
        }
        return 0;
    }

    // Updates token registry with maker addresses
    function _updateRegistry() internal {
        if (_registryAddress == address(0)) {
            emit RegistryUpdateFailed("Registry not set");
            return;
        }
        bool isBuy = block.timestamp % 2 == 0;
        uint256[] memory orders = isBuy ? _pendingBuyOrders : _pendingSellOrders;
        address token = isBuy ? _baseToken : _token0;
        if (orders.length == 0) {
            emit RegistryUpdateFailed("No pending orders");
            return;
        }
        address[] memory tempMakers = new address[](orders.length);
        uint256 makerCount = 0;
        for (uint256 i = 0; i < orders.length; i++) {
            address maker = isBuy ? _buyOrderCores[orders[i]].makerAddress : _sellOrderCores[orders[i]].makerAddress;
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
        address[] memory makers = new address[](makerCount);
        for (uint256 i = 0; i < makerCount; i++) {
            makers[i] = tempMakers[i];
        }
        try ITokenRegistry(_registryAddress).initializeBalances(token, makers) {} catch {
            emit RegistryUpdateFailed("Registry update failed");
        }
    }

    // Syncs pending orders with agent
    function globalizeUpdate() internal {
        if (_agent == address(0)) return;
        for (uint256 i = 0; i < _pendingBuyOrders.length; i++) {
            uint256 orderId = _pendingBuyOrders[i];
            BuyOrderCore memory core = _buyOrderCores[orderId];
            BuyOrderAmounts memory amounts = _buyOrderAmounts[orderId];
            if (core.status == 1 || core.status == 2) {
                try IOMFAgent(_agent).globalizeOrders(
                    _listingId,
                    _token0,
                    _baseToken,
                    orderId,
                    true,
                    core.makerAddress,
                    core.recipientAddress,
                    amounts.pending,
                    core.status
                ) {} catch {}
            }
        }
        for (uint256 i = 0; i < _pendingSellOrders.length; i++) {
            uint256 orderId = _pendingSellOrders[i];
            SellOrderCore memory core = _sellOrderCores[orderId];
            SellOrderAmounts memory amounts = _sellOrderAmounts[orderId];
            if (core.status == 1 || core.status == 2) {
                try IOMFAgent(_agent).globalizeOrders(
                    _listingId,
                    _token0,
                    _baseToken,
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

    // Queries annualized yield for token0 or baseToken
    function queryYield(bool isX, uint256 maxIterations) external view returns (uint256) {
        require(maxIterations > 0, "Invalid maxIterations");
        LastDayFee memory fee = _lastDayFee;
        if (fee.timestamp == 0 || _historicalData.length == 0 || !_isSameDay(block.timestamp, fee.timestamp)) {
            return 0; // No updates today
        }
        uint256 feeDifference = isX ? _volumeBalance.xVolume - fee.xFees : _volumeBalance.yVolume - fee.yFees;
        if (feeDifference == 0) return 0;
        uint256 liquidity = 0;
        try IOMFLiquidityTemplate(_liquidityAddress).liquidityAmounts() returns (uint256 xLiquid, uint256 yLiquid) {
            liquidity = isX ? xLiquid : yLiquid;
        } catch {
            return 0; // Graceful degradation
        }
        if (liquidity == 0) return 0;
        uint256 dailyFees = (feeDifference * 5) / 10000; // 0.05% fee
        uint256 dailyYield = (dailyFees * 1e18) / liquidity;
        return dailyYield * 365; // Annualized yield
    }

    // Retrieves price from oracle
    function getPrice() public view returns (uint256) {
        (bool success, bytes memory returnData) = _oracle.staticcall(abi.encodeWithSignature("latestPrice()"));
        require(success, "Price fetch failed");
        int256 priceValue = decodePrice(returnData); // Direct call to decodePrice
        require(priceValue >= 0, "Negative price not allowed");
        uint256 normalizedPrice = uint256(priceValue);
        return _oracleDecimals == 8 ? normalizedPrice * 1e10 : normalizedPrice; // Scale to 18 decimals
    }

    // Helper function to decode oracle price as int256
    function decodePrice(bytes memory data) private pure returns (int256) {
        return abi.decode(data, (int256));
    }

    // Returns next order ID and increments
    function nextOrderId() external onlyRouter returns (uint256) {
        return _orderIdHeight++;
    }

    // Updates balances, orders, or historical data
    function update(address caller, IOMFListing.UpdateType[] memory updates) external nonReentrant onlyRouter {
        VolumeBalance storage balances = _volumeBalance;
        bool volumeUpdated = false;
        // Fetch oracle price for order validation
        uint256 oraclePrice;
        try this.getPrice() returns (uint256 price) {
            oraclePrice = price;
        } catch {
            revert("Oracle price fetch failed");
        }

        for (uint256 i = 0; i < updates.length; i++) {
            IOMFListing.UpdateType memory u = updates[i];
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
        if (volumeUpdated && (_lastDayFee.timestamp == 0 || block.timestamp >= _lastDayFee.timestamp + 86400)) {
            _lastDayFee.xFees = balances.xVolume;
            _lastDayFee.yFees = balances.yVolume;
            _lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }
        for (uint256 i = 0; i < updates.length; i++) {
            IOMFListing.UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) balances.xBalance = u.value;
                else if (u.index == 1) balances.yBalance = u.value;
                else if (u.index == 2) balances.xVolume += u.value;
                else if (u.index == 3) balances.yVolume += u.value;
            } else if (u.updateType == 1) { // Buy order update
                if (u.structId == 0) { // Core
                    BuyOrderCore storage core = _buyOrderCores[u.index];
                    if (core.makerAddress == address(0)) { // New order
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        _pendingBuyOrders.push(u.index);
                        _makerPendingOrders[u.addr].push(u.index);
                        _orderIdHeight = u.index + 1;
                        emit OrderUpdated(u.index, true, 1);
                    } else if (u.value == 0) { // Cancel order
                        core.status = 0;
                        removePendingOrder(_pendingBuyOrders, u.index);
                        removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                        _isBuyOrderComplete[u.index] = false;
                        emit OrderUpdated(u.index, true, 0);
                    }
                } else if (u.structId == 1) { // Pricing
                    require(u.minPrice <= oraclePrice && oraclePrice <= u.maxPrice, "Buy order price out of oracle range");
                    BuyOrderPricing storage pricing = _buyOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) { // Amounts
                    BuyOrderAmounts storage amounts = _buyOrderAmounts[u.index];
                    BuyOrderCore storage core = _buyOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) { // New amounts
                        amounts.pending = u.value;
                        amounts.amountSent = u.amountSent; // Set initial amountSent (token0)
                        balances.yBalance += u.value;
                        balances.yVolume += u.value;
                    } else if (core.status == 1) { // Fill order
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent; // Add to amountSent (token0)
                        balances.xBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(_pendingBuyOrders, u.index);
                            removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                            _isBuyOrderComplete[u.index] = false;
                        }
                        emit OrderUpdated(u.index, true, core.status);
                    }
                }
                // Check completeness
                if (_buyOrderCores[u.index].makerAddress != address(0) &&
                    _buyOrderPricings[u.index].maxPrice != 0 &&
                    _buyOrderAmounts[u.index].pending != 0) {
                    _isBuyOrderComplete[u.index] = true;
                }
            } else if (u.updateType == 2) { // Sell order update
                if (u.structId == 0) { // Core
                    SellOrderCore storage core = _sellOrderCores[u.index];
                    if (core.makerAddress == address(0)) { // New order
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        _pendingSellOrders.push(u.index);
                        _makerPendingOrders[u.addr].push(u.index);
                        _orderIdHeight = u.index + 1;
                        emit OrderUpdated(u.index, false, 1);
                    } else if (u.value == 0) { // Cancel order
                        core.status = 0;
                        removePendingOrder(_pendingSellOrders, u.index);
                        removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                        _isSellOrderComplete[u.index] = false;
                        emit OrderUpdated(u.index, false, 0);
                    }
                } else if (u.structId == 1) { // Pricing
                    require(u.minPrice <= oraclePrice && oraclePrice <= u.maxPrice, "Sell order price out of oracle range");
                    SellOrderPricing storage pricing = _sellOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) { // Amounts
                    SellOrderAmounts storage amounts = _sellOrderAmounts[u.index];
                    SellOrderCore storage core = _sellOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) { // New amounts
                        amounts.pending = u.value;
                        amounts.amountSent = u.amountSent; // Set initial amountSent (baseToken)
                        balances.xBalance += u.value;
                        balances.xVolume += u.value;
                    } else if (core.status == 1) { // Fill order
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        amounts.amountSent += u.amountSent; // Add to amountSent (baseToken)
                        balances.yBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(_pendingSellOrders, u.index);
                            removePendingOrder(_makerPendingOrders[core.makerAddress], u.index);
                            _isSellOrderComplete[u.index] = false;
                        }
                        emit OrderUpdated(u.index, false, core.status);
                    }
                }
                // Check completeness
                if (_sellOrderCores[u.index].makerAddress != address(0) &&
                    _sellOrderPricings[u.index].maxPrice != 0 &&
                    _sellOrderAmounts[u.index].pending != 0) {
                    _isSellOrderComplete[u.index] = true;
                }
            } else if (u.updateType == 3) { // Historical data
                try this.getPrice() returns (uint256 currentPrice) {
                    _historicalData.push(HistoricalData(
                        currentPrice, // Use oracle price
                        u.maxPrice >> 128, u.maxPrice & ((1 << 128) - 1), // xBalance, yBalance
                        u.minPrice >> 128, u.minPrice & ((1 << 128) - 1), // xVolume, yVolume
                        block.timestamp
                    ));
                } catch {
                    revert("Oracle price fetch failed for historical data");
                }
            }
        }
        emit BalancesUpdated(balances.xBalance, balances.yBalance);
        globalizeUpdate();
    }

    // Handles token transfers
    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant onlyRouter {
        VolumeBalance storage balances = _volumeBalance;
        uint8 decimals = IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        if (_lastDayFee.timestamp == 0 || block.timestamp >= _lastDayFee.timestamp + 86400) {
            _lastDayFee.xFees = balances.xVolume;
            _lastDayFee.yFees = balances.yVolume;
            _lastDayFee.timestamp = _floorToMidnight(block.timestamp);
        }
        if (token == _token0) {
            require(balances.xBalance >= normalizedAmount, "Insufficient xBalance");
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
            IERC20(token).safeTransfer(recipient, amount);
        } else if (token == _baseToken) {
            require(balances.yBalance >= normalizedAmount, "Insufficient yBalance");
            balances.yBalance -= normalizedAmount;
            balances.yVolume += normalizedAmount;
            IERC20(token).safeTransfer(recipient, amount);
        } else {
            revert("Invalid token");
        }
        emit BalancesUpdated(balances.xBalance, balances.yBalance);
        _updateRegistry();
        globalizeUpdate();
    }

    // Removes order from pending array
    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    // Returns current price from oracle (ignores listingId)
    function prices(uint256) external view returns (uint256) {
        return getPrice();
    }

    // Returns volume balances (ignores listingId)
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance) {
        VolumeBalance memory bal = _volumeBalance;
        return (bal.xBalance, bal.yBalance);
    }

    // Returns token0 address
    function token0() external view returns (address) {
        return _token0;
    }

    // Returns baseToken address
    function baseToken() external view returns (address) {
        return _baseToken;
    }

    // Returns token0 decimals
    function decimals0() external view returns (uint8) {
        return _decimal0;
    }

    // Returns baseToken decimals
    function baseTokenDecimals() external view returns (uint8) {
        return _baseTokenDecimals;
    }

    // View functions for order details
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = _buyOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = _buyOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        BuyOrderAmounts memory amounts = _buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = _sellOrderCores[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = _sellOrderPricings[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        SellOrderAmounts memory amounts = _sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    function isOrderCompleteView(uint256 orderId, bool isBuy) external view returns (bool) {
        return isBuy ? _isBuyOrderComplete[orderId] : _isSellOrderComplete[orderId];
    }

    function getRegistryAddress() external view returns (address) {
        return _registryAddress;
    }

    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return _pendingBuyOrders;
    }

    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return _pendingSellOrders;
    }

    function makerPendingOrdersView(address maker) external view returns (uint256[] memory) {
        return _makerPendingOrders[maker];
    }

    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory) {
        require(index < _historicalData.length, "Invalid index");
        return _historicalData[index];
    }

    function historicalDataLengthView() external view returns (uint256) {
        return _historicalData.length;
    }

    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory) {
        require(_historicalData.length > 0, "No historical data");
        uint256 minDiff = type(uint256).max;
        uint256 closestIndex = 0;
        for (uint256 i = 0; i < _historicalData.length; i++) {
            uint256 diff;
            if (targetTimestamp >= _historicalData[i].timestamp) {
                diff = targetTimestamp - _historicalData[i].timestamp;
            } else {
                diff = _historicalData[i].timestamp - targetTimestamp;
            }
            if (diff < minDiff) {
                minDiff = diff;
                closestIndex = i;
            }
        }
        return _historicalData[closestIndex];
    }
}