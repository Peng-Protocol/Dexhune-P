// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.16
// Changes:
// - Replaced liquidityAddresses mapping with single liquidityAddress variable to enforce one liquidity address per listing.
// - Updated setLiquidityAddress to set liquidityAddress directly, using internal listingId for validation.
// - Preserved all prior changes from v0.0.15.

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface IMFPAgent {
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
    ) external;
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

interface IMFPLiquidityTemplate {
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
}

contract MFPListingTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public tokenA;
    address public tokenB;
    uint256 public listingId;
    uint256 public orderIdHeight; // Tracks next available order ID
    address public agent; // MFPAgent address
    address public registryAddress; // TokenRegistry address
    uint256 public lastDay; // Timestamp of first volume update of current day (midnight)
    address public liquidityAddress; // Single liquidity address for this listing

    // Struct to handle updates, separate from internal structs to mitigate stack depth issues
    // Using a dedicated struct reduces variable scope and stack usage in update function
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

    mapping(uint256 => VolumeBalance) public volumeBalances;
    mapping(uint256 => uint256) public prices;
    mapping(uint256 => BuyOrderCore) public buyOrderCores;
    mapping(uint256 => BuyOrderPricing) public buyOrderPricings;
    mapping(uint256 => BuyOrderAmounts) public buyOrderAmounts;
    mapping(uint256 => SellOrderCore) public sellOrderCores;
    mapping(uint256 => SellOrderPricing) public sellOrderPricings;
    mapping(uint256 => SellOrderAmounts) public sellOrderAmounts;
    mapping(uint256 => bool) public isBuyOrderComplete;
    mapping(uint256 => bool) public isSellOrderComplete;
    mapping(uint256 => uint256[]) public pendingBuyOrders;
    mapping(uint256 => uint256[]) public pendingSellOrders;
    mapping(address => uint256[]) public makerPendingOrders;
    mapping(uint256 => HistoricalData[]) public historicalData;

    event OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status);
    event BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance);
    event RegistryUpdateFailed(string reason);

    constructor() {
        orderIdHeight = 0;
        lastDay = 0;
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
        require(listingId != 0, "Listing ID not set");
        liquidityAddress = _liquidityAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
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

    function globalizeUpdate() internal {
        if (agent == address(0)) return;
        for (uint256 i = 0; i < pendingBuyOrders[listingId].length; i++) {
            uint256 orderId = pendingBuyOrders[listingId][i];
            BuyOrderCore memory core = buyOrderCores[orderId];
            BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
            if (core.status == 1 || core.status == 2) {
                try IMFPAgent(agent).globalizeOrders(
                    listingId,
                    tokenA,
                    tokenB,
                    orderId,
                    true,
                    core.makerAddress,
                    core.recipientAddress,
                    amounts.pending,
                    core.status
                ) {} catch {}
            }
        }
        for (uint256 i = 0; i < pendingSellOrders[listingId].length; i++) {
            uint256 orderId = pendingSellOrders[listingId][i];
            SellOrderCore memory core = sellOrderCores[orderId];
            SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
            if (core.status == 1 || core.status == 2) {
                try IMFPAgent(agent).globalizeOrders(
                    listingId,
                    tokenA,
                    tokenB,
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
        bool isBuy = block.timestamp % 2 == 0;
        uint256[] memory orders = isBuy ? pendingBuyOrders[listingId] : pendingSellOrders[listingId];
        address token = isBuy ? tokenB : tokenA;
        if (orders.length == 0) {
            emit RegistryUpdateFailed("No pending orders");
            return;
        }
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
        address[] memory makers = new address[](makerCount);
        for (uint256 i = 0; i < makerCount; i++) {
            makers[i] = tempMakers[i];
        }
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
        VolumeBalance memory bal = volumeBalances[listingId];
        uint256 currentVolume = isX ? bal.xVolume : bal.yVolume;
        uint256 iterationsLeft = maxIterations;
        uint256 volumeChange = 0;

        if (historicalData[listingId].length == 0) {
            return 0;
        }

        for (uint256 i = historicalData[listingId].length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = historicalData[listingId][i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                volumeChange = currentVolume - (isX ? data.xVolume : data.yVolume);
                return volumeChange;
            }
        }

        if (iterationsLeft == 0 || historicalData[listingId].length <= maxIterations) {
            HistoricalData memory earliest = historicalData[listingId][0];
            volumeChange = currentVolume - (isX ? earliest.xVolume : earliest.yVolume);
            return volumeChange;
        }

        return 0;
    }

    // Warning: High gas consumption possible for large maxIterations or historical data
    function queryYield(bool isX, uint256 maxIterations) external view returns (uint256) {
        require(maxIterations > 0, "Invalid maxIterations");
        if (lastDay == 0 || historicalData[listingId].length == 0 || !_isSameDay(block.timestamp, lastDay)) {
            return 0;
        }
        uint256 volumeChange = _findVolumeChange(isX, lastDay, maxIterations);
        if (volumeChange == 0) {
            return 0;
        }
        uint256 liquidity = 0;
        try IMFPLiquidityTemplate(liquidityAddress).liquidityAmounts() returns (uint256 xLiquid, uint256 yLiquid) {
            liquidity = isX ? xLiquid : yLiquid;
        } catch {
            return 0;
        }
        uint256 dailyFees = (volumeChange * 5) / 10000;
        if (liquidity == 0) return 0;
        uint256 dailyYield = (dailyFees * 1e18) / liquidity;
        uint256 apy = dailyYield * 365;
        return apy;
    }

    function update(address caller, ListingUpdateType[] memory updates) external nonReentrant {
        require(caller == routerAddress, "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];

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
            if (u.updateType == 0) {
                if (u.index == 0) balances.xBalance = u.value;
                else if (u.index == 1) balances.yBalance = u.value;
                else if (u.index == 2) balances.xVolume += u.value;
                else if (u.index == 3) balances.yVolume += u.value;
            } else if (u.updateType == 1) {
                if (u.structId == 0) {
                    BuyOrderCore storage core = buyOrderCores[u.index];
                    if (core.makerAddress == address(0)) {
                        u.index = orderIdHeight++;
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingBuyOrders[listingId].push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                        emit OrderUpdated(listingId, u.index, true, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(pendingBuyOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        isBuyOrderComplete[u.index] = false;
                        emit OrderUpdated(listingId, u.index, true, 0);
                    }
                } else if (u.structId == 1) {
                    BuyOrderPricing storage pricing = buyOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    BuyOrderAmounts storage amounts = buyOrderAmounts[u.index];
                    BuyOrderCore storage core = buyOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value;
                        balances.yBalance += u.value;
                        balances.yVolume += u.value;
                    } else if (core.status == 1) {
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        balances.xBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(pendingBuyOrders[listingId], u.index);
                            removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                            isBuyOrderComplete[u.index] = false;
                        }
                        emit OrderUpdated(listingId, u.index, true, core.status);
                    }
                }
                if (buyOrderCores[u.index].makerAddress != address(0) &&
                    buyOrderPricings[u.index].maxPrice != 0 &&
                    buyOrderAmounts[u.index].pending != 0) {
                    isBuyOrderComplete[u.index] = true;
                }
            } else if (u.updateType == 2) {
                if (u.structId == 0) {
                    SellOrderCore storage core = sellOrderCores[u.index];
                    if (core.makerAddress == address(0)) {
                        u.index = orderIdHeight++;
                        core.makerAddress = u.addr;
                        core.recipientAddress = u.recipient;
                        core.status = 1;
                        pendingSellOrders[listingId].push(u.index);
                        makerPendingOrders[u.addr].push(u.index);
                        emit OrderUpdated(listingId, u.index, false, 1);
                    } else if (u.value == 0) {
                        core.status = 0;
                        removePendingOrder(pendingSellOrders[listingId], u.index);
                        removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                        isSellOrderComplete[u.index] = false;
                        emit OrderUpdated(listingId, u.index, false, 0);
                    }
                } else if (u.structId == 1) {
                    SellOrderPricing storage pricing = sellOrderPricings[u.index];
                    pricing.maxPrice = u.maxPrice;
                    pricing.minPrice = u.minPrice;
                } else if (u.structId == 2) {
                    SellOrderAmounts storage amounts = sellOrderAmounts[u.index];
                    SellOrderCore storage core = sellOrderCores[u.index];
                    if (amounts.pending == 0 && core.makerAddress != address(0)) {
                        amounts.pending = u.value;
                        balances.xBalance += u.value;
                        balances.xVolume += u.value;
                    } else if (core.status == 1) {
                        require(amounts.pending >= u.value, "Insufficient pending");
                        amounts.pending -= u.value;
                        amounts.filled += u.value;
                        balances.yBalance -= u.value;
                        core.status = amounts.pending == 0 ? 3 : 2;
                        if (amounts.pending == 0) {
                            removePendingOrder(pendingSellOrders[listingId], u.index);
                            removePendingOrder(makerPendingOrders[core.makerAddress], u.index);
                            isSellOrderComplete[u.index] = false;
                        }
                        emit OrderUpdated(listingId, u.index, false, core.status);
                    }
                }
                if (sellOrderCores[u.index].makerAddress != address(0) &&
                    sellOrderPricings[u.index].maxPrice != 0 &&
                    sellOrderAmounts[u.index].pending != 0) {
                    isSellOrderComplete[u.index] = true;
                }
            } else if (u.updateType == 3) {
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
        globalizeUpdate();
    }

    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(caller == routerAddress, "Router only");
        VolumeBalance storage balances = volumeBalances[listingId];
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (lastDay == 0 || block.timestamp >= lastDay + 86400) {
            lastDay = _floorToMidnight(block.timestamp);
        }

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
        _updateRegistry();
        globalizeUpdate();
    }

    function getListingId() external view returns (uint256) {
        return listingId;
    }

    function nextOrderId() external returns (uint256) {
        return orderIdHeight++;
    }

    // Returns volume balances for the current listing
    // Separate function aligns with interface expectations and improves query modularity
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