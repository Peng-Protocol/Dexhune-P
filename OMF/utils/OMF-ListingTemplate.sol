// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.9 (Updated)
// Changes:
// - From v0.0.8: Removed listingId as function parameter, made implicit via stored state (all functions and events).
// - Updated mappings to remove listingId key: volumeBalances, liquidityAddresses, prices, pendingBuyOrders, pendingSellOrders, historicalData.
// - Updated IOMFListing interface: volumeBalances() no longer takes listingId.
// - Updated events: Removed listingId from OrderUpdated and BalancesUpdated.
// - Retained original 'this.' usage for internal calls as per request.
// - Aligned with prior changes (v0.0.8): Renamed tokenA to token0, tokenB to baseToken, xLiquid to xBalances, added volume tracking, orderIdHeight, etc.

import "./imports/SafeERC20.sol";

interface IOMFListing {
    function volumeBalances() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getPrice() external view returns (uint256);
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

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;    // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
        uint256 value;    // principal or amount (normalized) or price (for historical)
        address addr;     // makerAddress
        address recipient;// recipientAddress
        uint256 maxPrice; // for buy orders or packed xBalance/yBalance (historical)
        uint256 minPrice; // for sell orders or packed xVolume/yVolume (historical)
    }

    struct VolumeBalance {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    struct BuyOrder {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct SellOrder {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
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
    mapping(uint256 => BuyOrder) public buyOrders;
    mapping(uint256 => SellOrder) public sellOrders;
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

    // One-time setup functions
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

    function getPrice() external view returns (uint256) {
        (bool success, bytes memory returnData) = oracle.staticcall(abi.encodeWithSignature("latestPrice()"));
        require(success, "Price fetch failed");
        uint256 price = abi.decode(returnData, (uint256));
        return oracleDecimals == 8 ? price * 1e10 : price; // Scale to 18 decimals
    }

    function nextOrderId() external onlyRouter returns (uint256) {
        return orderIdHeight++; // Return current and increment
    }

    function update(address caller, UpdateType[] memory updates) external onlyRouter {
        VolumeBalance storage balances = volumeBalance;

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) balances.xBalance = u.value;       // Set xBalance
                else if (u.index == 1) balances.yBalance = u.value;  // Set yBalance
                else if (u.index == 2) balances.xVolume += u.value;  // Increase xVolume
                else if (u.index == 3) balances.yVolume += u.value;  // Increase yVolume
            } else if (u.updateType == 1) { // Buy order update
                BuyOrder storage order = buyOrders[u.index];
                if (order.makerAddress == address(0)) { // New order
                    u.index = orderIdHeight++; // Assign and increment orderId
                    order.makerAddress = u.addr;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.pending = u.value;
                    order.status = 1;
                    pendingBuyOrders.push(u.index);
                    makerPendingOrders[u.addr].push(u.index);
                    balances.yBalance += u.value; // Deposit increases yBalance
                    balances.yVolume += u.value;  // Track order volume
                    emit OrderUpdated(u.index, true, 1);
                } else if (u.value == 0) { // Cancel order
                    order.status = 0;
                    removePendingOrder(pendingBuyOrders, u.index);
                    removePendingOrder(makerPendingOrders[u.addr], u.index);
                    emit OrderUpdated(u.index, true, 0);
                } else if (order.status == 1) { // Fill order
                    require(order.pending >= u.value, "Insufficient pending");
                    order.pending -= u.value;
                    order.filled += u.value;
                    balances.xBalance -= u.value; // Reduce xBalance on fill
                    order.status = order.pending == 0 ? 3 : 2;
                    if (order.pending == 0) {
                        removePendingOrder(pendingBuyOrders, u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    emit OrderUpdated(u.index, true, order.status);
                }
            } else if (u.updateType == 2) { // Sell order update
                SellOrder storage order = sellOrders[u.index];
                if (order.makerAddress == address(0)) { // New order
                    u.index = orderIdHeight++; // Assign and increment orderId
                    order.makerAddress = u.addr;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.pending = u.value;
                    order.status = 1;
                    pendingSellOrders.push(u.index);
                    makerPendingOrders[u.addr].push(u.index);
                    balances.xBalance += u.value; // Deposit increases xBalance
                    balances.xVolume += u.value;  // Track order volume
                    emit OrderUpdated(u.index, false, 1);
                } else if (u.value == 0) { // Cancel order
                    order.status = 0;
                    removePendingOrder(pendingSellOrders, u.index);
                    removePendingOrder(makerPendingOrders[u.addr], u.index);
                    emit OrderUpdated(u.index, false, 0);
                } else if (order.status == 1) { // Fill order
                    require(order.pending >= u.value, "Insufficient pending");
                    order.pending -= u.value;
                    order.filled += u.value;
                    balances.yBalance -= u.value; // Reduce yBalance on fill
                    order.status = order.pending == 0 ? 3 : 2;
                    if (order.pending == 0) {
                        removePendingOrder(pendingSellOrders, u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    emit OrderUpdated(u.index, false, order.status);
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
    }

    function transact(address caller, address token, uint256 amount, address recipient) external onlyRouter {
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
}