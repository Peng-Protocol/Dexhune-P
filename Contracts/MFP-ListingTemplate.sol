// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

// Version: 0.0.3

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

contract MFPListingTemplate is Ownable {
    using SafeERC20 for IERC20;

    // State Variables
    address public routerAddress;
    address public tokenA; // Token-0 address (ETH if address(0))
    address public tokenB; // Token-1 address (ETH if address(0))
    uint8 public tokenADecimals; // Decimals for tokenA (18 for ETH)
    uint8 public tokenBDecimals; // Decimals for tokenB (18 for ETH)
    mapping(uint256 => address) public liquidityAddresses; // listingId -> MFPLiquidity address
    mapping(uint256 => VolumeBalance) public volumeBalances; // Balances and cumulative volumes (18 decimals)
    mapping(uint256 => uint256) public prices; // Current price (tokenA/tokenB, 18 decimals)
    mapping(uint256 => HistoricalPrice[]) public historicalPrice; // Price history
    mapping(uint256 => HistoricalVolume[]) public historicalBuyVolume; // Buy volume history
    mapping(uint256 => HistoricalVolume[]) public historicalSellVolume; // Sell volume history
    mapping(uint256 => HistoryCount) public historyCount; // Counts of historical entries
    mapping(uint256 => DayStart) public dayStart; // 24-hour start indices
    mapping(uint256 => BuyOrder) public buyOrders; // Buy order storage
    mapping(uint256 => SellOrder) public sellOrders; // Sell order storage
    mapping(uint256 => uint256[]) public pendingBuyOrders; // Pending buy order IDs
    mapping(uint256 => uint256[]) public pendingSellOrders; // Pending sell order IDs
    mapping(address => uint256[]) public makerOrders; // All order IDs per maker
    mapping(address => uint256[]) public makerPendingOrders; // Pending order IDs per maker

    // Structs
    struct VolumeBalance {
        uint256 xBalance; // Token-0 balance (18 decimals)
        uint256 yBalance; // Token-1 balance (18 decimals)
        uint256 xVolume; // Cumulative Token-0 volume (18 decimals)
        uint256 yVolume; // Cumulative Token-1 volume (18 decimals)
    }
    struct HistoricalPrice {
        uint256 price; // 18 decimals
        uint256 timestamp;
    }
    struct HistoricalVolume {
        uint256 volume; // 18 decimals
        uint256 timestamp;
    }
    struct HistoryCount {
        uint256 buyVolumeCount;
        uint256 sellVolumeCount;
    }
    struct DayStart {
        uint256 buyVolumeIndex;
        uint256 sellVolumeIndex;
    }
    struct BuyOrder {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice; // Max price (18 decimals)
        uint256 minPrice; // Min price (18 decimals)
        uint256 principal; // Token-0 amount post-fee (18 decimals)
        uint256 pending; // Remaining Token-0 to settle (18 decimals)
        uint256 filled; // Token-1 filled (18 decimals)
        uint256 orderId;
        uint8 status; // 1 = pending, 2 = filled, 3 = cancelled
    }
    struct SellOrder {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice; // Max price to sell at (18 decimals)
        uint256 minPrice; // Min price to sell at (18 decimals)
        uint256 principal; // Token-1 amount post-fee (18 decimals)
        uint256 pending; // Remaining Token-1 to settle (18 decimals)
        uint256 filled; // Token-0 filled (18 decimals)
        uint256 orderId;
        uint8 status; // 1 = pending, 2 = filled, 3 = cancelled
    }
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value; // 18 decimals
        address addr;
        address recipient;
        uint256 maxPrice; // 18 decimals
        uint256 minPrice; // 18 decimals
    }

    // Events
    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderSettled(uint256 orderId, uint256 amountFilled);
    event BalanceUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance);
    event PriceUpdated(uint256 listingId, uint256 price);

    constructor() {
        _transferOwnership(msg.sender); // Owner = MFP-Agent
    }

    function setRouter(address _router) external {
        routerAddress = _router; // Set by MFP-Agent post-deployment
    }

    function setLiquidityAddress(uint256 listingId, address _liquidity) external {
        liquidityAddresses[listingId] = _liquidity; // Set by MFP-Agent
    }

    function setTokens(address _tokenA, address _tokenB) external onlyOwner {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        tokenA = _tokenA;
        tokenB = _tokenB;
        tokenADecimals = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        tokenBDecimals = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
    }

    function update(uint256 listingId, UpdateType[] memory updates) external {
        require(msg.sender == routerAddress, "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];
        HistoryCount storage counts = historyCount[listingId];

        for (uint256 i = 0; i < updates.length && i < 100; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Update balances
                if (u.index == 0) {
                    balances.xBalance = u.value;
                } else if (u.index == 1) {
                    balances.yBalance = u.value;
                }
                emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
            } else if (u.updateType == 1) { // Update buy order
                BuyOrder storage order = buyOrders[u.index];
                if (order.status == 0) { // New order
                    order.makerAddress = u.addr;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.principal = u.value;
                    order.pending = u.value;
                    order.orderId = u.index;
                    order.status = 1;
                    pendingBuyOrders[listingId].push(u.index);
                    makerPendingOrders[u.addr].push(u.index);
                    balances.xBalance += u.value; // Update xBalance on order creation
                    emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
                } else if (order.status == 1) { // Existing order settlement or cancellation
                    require(order.pending >= u.value, "Insufficient pending amount");
                    order.pending -= u.value;
                    order.filled += u.value;
                    if (order.pending == 0) {
                        order.status = 2; // Filled
                        removePendingOrder(pendingBuyOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    } else if (u.value == 0 && order.pending > 0) { // Cancelled
                        order.status = 3;
                        balances.xBalance -= order.pending; // Refund remaining xBalance
                        removePendingOrder(pendingBuyOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    if (u.value > 0) { // Settlement
                        balances.yVolume += u.value;
                        balances.yBalance -= u.value; // Reduce yBalance on settlement
                        historicalBuyVolume[listingId].push(HistoricalVolume(u.value, block.timestamp));
                        counts.buyVolumeCount++;
                        emit OrderSettled(u.index, u.value);
                        emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
                    }
                }
            } else if (u.updateType == 2) { // Update sell order
                SellOrder storage order = sellOrders[u.index];
                if (order.status == 0) { // New order
                    order.makerAddress = u.addr;
                    order.recipientAddress = u.recipient;
                    order.maxPrice = u.maxPrice;
                    order.minPrice = u.minPrice;
                    order.principal = u.value;
                    order.pending = u.value;
                    order.orderId = u.index;
                    order.status = 1;
                    pendingSellOrders[listingId].push(u.index);
                    makerPendingOrders[u.addr].push(u.index);
                    balances.yBalance += u.value; // Update yBalance on order creation
                    emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
                } else if (order.status == 1) { // Existing order settlement or cancellation
                    require(order.pending >= u.value, "Insufficient pending amount");
                    order.pending -= u.value;
                    order.filled += u.value;
                    if (order.pending == 0) {
                        order.status = 2; // Filled
                        removePendingOrder(pendingSellOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    } else if (u.value == 0 && order.pending > 0) { // Cancelled
                        order.status = 3;
                        balances.yBalance -= order.pending; // Refund remaining yBalance
                        removePendingOrder(pendingSellOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[order.makerAddress], u.index);
                    }
                    if (u.value > 0) { // Settlement
                        balances.xVolume += u.value;
                        balances.xBalance -= u.value; // Reduce xBalance on settlement
                        historicalSellVolume[listingId].push(HistoricalVolume(u.value, block.timestamp));
                        counts.sellVolumeCount++;
                        emit OrderSettled(u.index, u.value);
                        emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
                    }
                }
            } else if (u.updateType == 3) { // Manual price update (optional)
                prices[listingId] = u.value;
                historicalPrice[listingId].push(HistoricalPrice(u.value, block.timestamp));
                emit PriceUpdated(listingId, u.value);
            } else if (u.updateType == 4) { // Update dayStart
                if (u.index == 0) dayStart[listingId].buyVolumeIndex = u.value;
                else if (u.index == 1) dayStart[listingId].sellVolumeIndex = u.value;
            }
        }

        // Update price after processing updates
        if (balances.xBalance > 0 && balances.yBalance > 0) {
            prices[listingId] = (balances.xBalance * 1e18) / balances.yBalance;
        } else if (prices[listingId] == 0) {
            prices[listingId] = 1e-18; // Default to lowest unit if no prior price
        }
        historicalPrice[listingId].push(HistoricalPrice(prices[listingId], block.timestamp));
        emit PriceUpdated(listingId, prices[listingId]);
    }

    function transact(uint256 listingId, address token, uint256 amount, address recipient) external payable {
        require(msg.sender == routerAddress, "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];
        uint256 nativeAmount = denormalize(amount, token == tokenA ? tokenADecimals : tokenBDecimals);

        if (token == tokenA) {
            require(balances.xBalance >= amount, "Insufficient xBalance");
            balances.xBalance -= amount;
            if (tokenA == address(0)) {
                (bool success, ) = recipient.call{value: nativeAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(recipient, nativeAmount);
            }
            emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
        } else if (token == tokenB) {
            require(balances.yBalance >= amount, "Insufficient yBalance");
            balances.yBalance -= amount;
            if (tokenB == address(0)) {
                (bool success, ) = recipient.call{value: nativeAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(recipient, nativeAmount);
            }
            emit BalanceUpdated(listingId, balances.xBalance, balances.yBalance);
        } else {
            revert("Invalid token");
        }

        // Update price after transfer
        if (balances.xBalance > 0 && balances.yBalance > 0) {
            prices[listingId] = (balances.xBalance * 1e18) / balances.yBalance;
        } else if (prices[listingId] == 0) {
            prices[listingId] = 1e-18; // Default to lowest unit
        }
        historicalPrice[listingId].push(HistoricalPrice(prices[listingId], block.timestamp));
        emit PriceUpdated(listingId, prices[listingId]);
    }

    function queryYield(uint256 listingId, bool isX) external view returns (uint256) {
        HistoryCount memory count = historyCount[listingId];
        DayStart memory start = dayStart[listingId];
        HistoricalVolume[] storage volumes = isX ? historicalBuyVolume[listingId] : historicalSellVolume[listingId];
        uint256 totalVolume = 0;
        uint256 timeWindow = block.timestamp - 24 hours;

        uint256 startIndex = isX ? start.buyVolumeIndex : start.sellVolumeIndex;
        uint256 endIndex = isX ? count.buyVolumeCount : count.sellVolumeCount;

        for (uint256 i = startIndex; i < endIndex; i++) {
            if (volumes[i].timestamp >= timeWindow) {
                totalVolume += volumes[i].volume;
            }
        }

        uint256 feeYield = (totalVolume * 5) / 10000; // 0.05% fee
        uint256 liquidity = isX ? volumeBalances[listingId].xBalance : volumeBalances[listingId].yBalance;
        if (liquidity == 0) return 0;
        return (feeYield * 365 * 10000) / liquidity; // Annualized yield, scaled by 10000
    }

    // Internal helper to remove order from pending arrays
    function removePendingOrder(uint256[] storage orderIds, uint256 orderId) internal {
        for (uint256 i = 0; i < orderIds.length; i++) {
            if (orderIds[i] == orderId) {
                orderIds[i] = orderIds[orderIds.length - 1];
                orderIds.pop();
                break;
            }
        }
    }

    // Decimal normalization helpers
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / (10 ** (18 - decimals));
        return amount * (10 ** (decimals - 18));
    }
}