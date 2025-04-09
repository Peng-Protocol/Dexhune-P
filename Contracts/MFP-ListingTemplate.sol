// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.13 (Updated)
// Changes:
// - Added mapping(uint256 => uint256) nextOrderId to track incremental order IDs per listing (new in v0.0.13).
// - Added getNextOrderId view function to return and increment nextOrderId (new in v0.0.13).
// - Incremented nextOrderId in update function for new buy/sell orders (new in v0.0.13).
// - Added ReentrancyGuard import and inheritance; applied nonReentrant to transact and update (new in v0.0.13).
// - Side effects: Order IDs now sequential instead of hashed; interfaces (e.g., IMFPOrderLibrary) must pass orderId explicitly.

import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

contract MFPListingTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public tokenA;
    address public tokenB;
    uint256 public listingId;
    mapping(uint256 => uint256) public nextOrderId; // Tracks next order ID per listing

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
        uint8 status;
    }

    struct HistoricalData {
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        uint256 timestamp;
    }

    mapping(uint256 => VolumeBalance) public volumeBalances;
    mapping(uint256 => address) public liquidityAddresses;
    mapping(uint256 => uint256) public prices;
    mapping(uint256 => BuyOrder) public buyOrders;
    mapping(uint256 => SellOrder) public sellOrders;
    mapping(uint256 => uint256[]) public pendingBuyOrders;
    mapping(uint256 => uint256[]) public pendingSellOrders;
    mapping(address => uint256[]) public makerPendingOrders;
    mapping(uint256 => HistoricalData[]) public historicalData;

    event OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status);
    event BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance);

    // Helper functions
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
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
        require(liquidityAddresses[listingId] == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddresses[listingId] = _liquidityAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // Core functions
    function update(address caller, UpdateType[] memory updates) external nonReentrant {
        require(caller == routerAddress, "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) balances.xBalance = u.value;
                else if (u.index == 1) balances.yBalance = u.value;
                else if (u.index == 2) balances.xVolume += u.value;
                else if (u.index == 3) balances.yVolume += u.value;
            } else if (u.updateType == 1) { // Buy order update
                BuyOrder storage order = buyOrders[u.index];
                if (order.makerAddress == address(0)) { // New order
                    order.makerAddress = u.addr;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.pending = u.value;
                    order.status = 1;
                    pendingBuyOrders[listingId].push(u.index);
                    makerPendingOrders[u.addr].push(u.index);
                    balances.yBalance += u.value;
                    balances.yVolume += u.value;
                    nextOrderId[listingId] = u.index + 1; // Increment for next order
                    emit OrderUpdated(listingId, u.index, true, 1);
                } else if (u.value == 0) { // Cancel order
                    order.status = 0;
                    removePendingOrder(pendingBuyOrders[listingId], u.index);
                    removePendingOrder(makerPendingOrders[u.addr], u.index);
                    emit OrderUpdated(listingId, u.index, true, 0);
                } else if (order.status == 1) { // Fill order
                    require(order.pending >= u.value, "Insufficient pending");
                    order.pending -= u.value;
                    order.filled += u.value;
                    balances.xBalance -= u.value;
                    order.status = order.pending == 0 ? 3 : 2;
                    if (order.pending == 0) {
                        removePendingOrder(pendingBuyOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    emit OrderUpdated(listingId, u.index, true, order.status);
                }
            } else if (u.updateType == 2) { // Sell order update
                SellOrder storage order = sellOrders[u.index];
                if (order.makerAddress == address(0)) { // New order
                    order.makerAddress = u.addr;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.pending = u.value;
                    order.status = 1;
                    pendingSellOrders[listingId].push(u.index);
                    makerPendingOrders[u.addr].push(u.index);
                    balances.xBalance += u.value;
                    balances.xVolume += u.value;
                    nextOrderId[listingId] = u.index + 1; // Increment for next order
                    emit OrderUpdated(listingId, u.index, false, 1);
                } else if (u.value == 0) { // Cancel order
                    order.status = 0;
                    removePendingOrder(pendingSellOrders[listingId], u.index);
                    removePendingOrder(makerPendingOrders[u.addr], u.index);
                    emit OrderUpdated(listingId, u.index, false, 0);
                } else if (order.status == 1) { // Fill order
                    require(order.pending >= u.value, "Insufficient pending");
                    order.pending -= u.value;
                    order.filled += u.value;
                    balances.yBalance -= u.value;
                    order.status = order.pending == 0 ? 3 : 2;
                    if (order.pending == 0) {
                        removePendingOrder(pendingSellOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    emit OrderUpdated(listingId, u.index, false, order.status);
                }
            } else if (u.updateType == 3) { // Historical data
                historicalData[listingId].push(HistoricalData(
                    u.value,
                    u.maxPrice >> 128, u.maxPrice & ((1 << 128) - 1),
                    u.minPrice >> 128, u.minPrice & ((1 << 128) - 1),
                    block.timestamp
                ));
            }
        }

        if (balances.xBalance > 0 && balances.yBalance > 0) {
            prices[listingId] = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(listingId, balances.xBalance, balances.yBalance);
    }

    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(caller == routerAddress, "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (token == tokenA) {
            require(balances.xBalance >= normalizedAmount, "Insufficient xBalance");
            balances.xBalance -= normalizedAmount;
            balances.xVolume += normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else if (token == tokenB) {
            require(balances.yBalance >= normalizedAmount, "Insufficient yBalance");
            balances.yBalance -= normalizedAmount;
            balances.yVolume += normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else {
            revert("Invalid token");
        }
        if (balances.xBalance > 0 && balances.yBalance > 0) {
            prices[listingId] = (balances.xBalance * 1e18) / balances.yBalance;
        }
        emit BalancesUpdated(listingId, balances.xBalance, balances.yBalance);
    }

    // View functions
    function getNextOrderId(uint256 _listingId) external view returns (uint256) {
        return nextOrderId[_listingId];
    }

    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume) {
        VolumeBalance memory bal = volumeBalances[listingId];
        return (bal.xBalance, bal.yBalance, bal.xVolume, bal.yVolume);
    }

    function listingPriceView() external view returns (uint256) {
        return prices[listingId];
    }

    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return pendingBuyOrders[listingId];
    }

    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return pendingSellOrders[listingId];
    }

    function makerPendingOrdersView(address maker) external view returns (uint256[] memory) {
        return makerPendingOrders[maker];
    }

    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory) {
        require(index < historicalData[listingId].length, "Invalid index");
        return historicalData[listingId][index];
    }

    function historicalDataLengthView() external view returns (uint256) {
        return historicalData[listingId].length;
    }

    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory) {
        require(historicalData[listingId].length > 0, "No historical data");
        uint256 minDiff = type(uint256).max;
        uint256 closestIndex = 0;
        for (uint256 i = 0; i < historicalData[listingId].length; i++) {
            uint256 diff;
            if (targetTimestamp >= historicalData[listingId][i].timestamp) {
                diff = targetTimestamp - historicalData[listingId][i].timestamp;
            } else {
                diff = historicalData[listingId][i].timestamp - targetTimestamp;
            }
            if (diff < minDiff) {
                minDiff = diff;
                closestIndex = i;
            }
        }
        return historicalData[listingId][closestIndex];
    }
}