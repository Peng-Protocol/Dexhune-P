// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.3.7
// Changes:
// -v0.3.7: Derived "MFP" from "CC".Removed Uniswap functionality.  

interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ICCLiquidityTemplate {
    function liquidityDetail() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc);
}

interface ITokenRegistry {
    function initializeTokens(address user, address[] memory tokens) external;
}

interface ICCGlobalizer {
    function globalizeOrders(address maker, address token) external;
}

interface ICCAgent {
    function getLister(address listingAddress) external view returns (address lister);
    function getRouters() external view returns (address[] memory routers);
}

contract MFPListingTemplate {
    mapping(address router => bool isRouter) public routers;
    address[] private routerAddresses;
    bool private _routersSet;
    address public tokenA; // Returns address token
    address public tokenB; // Returns address token
    uint8 public decimalsA; // Returns uint8 decimals
    uint8 public decimalsB; // Returns uint8 decimals
    uint256 public listingId; // Returns uint256 listingId
    address public agentView; // Returns address agent
    address public registryAddress; // Returns address registry
    address public liquidityAddressView; // Returns address liquidityAddress
    address public globalizerAddress;
    bool private _globalizerSet;
    uint256 private nextOrderId; // Returns uint256 nextOrderId

    struct DayStartFee {
        uint256 dayStartXFeesAcc; // Tracks xFeesAcc at midnight
        uint256 dayStartYFeesAcc; // Tracks yFeesAcc at midnight
        uint256 timestamp; // Midnight timestamp
    }
    DayStartFee public dayStartFee; // Returns DayStartFee memory fee

    uint256[] private _pendingBuyOrders; // Returns uint256[] memory orderIds
    uint256[] private _pendingSellOrders; // Returns uint256[] memory orderIds
    mapping(address maker => uint256[] orderIds) public makerPendingOrders; // Returns uint256[] memory orderIds

    struct HistoricalData {
        uint256 price;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        uint256 timestamp;
    }
    HistoricalData[] private _historicalData;

    // Maps midnight timestamps to historical data indices
    mapping(uint256 timestamp => uint256 index) private _dayStartIndices;

    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
    }
    struct BuyOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct BuyOrderAmounts {
        uint256 pending;    // Amount of tokenB pending
        uint256 filled;     // Amount of tokenB filled
        uint256 amountSent; // Amount of tokenA sent during settlement
    }
    struct SellOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }
    struct SellOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct SellOrderAmounts {
        uint256 pending;    // Amount of tokenA pending
        uint256 filled;     // Amount of tokenA filled
        uint256 amountSent; // Amount of tokenB sent during settlement
    }
    
    struct UpdateType {
        uint8 updateType; // 0: balance, 1: buy order, 2: sell order, 3: historical
        uint8 structId;   // 0: Core, 1: Pricing, 2: Amounts
        uint256 index;    // orderId or slot index
        uint256 value;    // principal or amount (normalized) or price
        address addr;     // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct
        uint256 minPrice; // for Pricing struct
        uint256 amountSent; // Amount of opposite token sent during settlement
    }
    struct OrderStatus {
        bool hasCore;    // Tracks if Core struct is set
        bool hasPricing; // Tracks if Pricing struct is set
        bool hasAmounts; // Tracks if Amounts struct is set
    }

    mapping(uint256 orderId => BuyOrderCore) public buyOrderCore; // Returns (address makerAddress, address recipientAddress, uint8 status)
    mapping(uint256 orderId => BuyOrderPricing) public buyOrderPricing; // Returns (uint256 maxPrice, uint256 minPrice)
    mapping(uint256 orderId => BuyOrderAmounts) public buyOrderAmounts; // Returns (uint256 pending, uint256 filled, uint256 amountSent)
    mapping(uint256 orderId => SellOrderCore) public sellOrderCore; // Returns (address makerAddress, address recipientAddress, uint8 status)
    mapping(uint256 orderId => SellOrderPricing) public sellOrderPricing; // Returns (uint256 maxPrice, uint256 minPrice)
    mapping(uint256 orderId => SellOrderAmounts) public sellOrderAmounts; // Returns (uint256 pending, uint256 filled, uint256 amountSent)
    mapping(uint256 orderId => OrderStatus) private orderStatus; // Tracks completeness of order structs

    event OrderUpdated(uint256 indexed listingId, uint256 orderId, bool isBuy, uint8 status);
    event BalancesUpdated(uint256 indexed listingId, uint256 xBalance, uint256 yBalance);
    event GlobalizerAddressSet(address indexed globalizer);
    event GlobalUpdateFailed(uint256 indexed listingId, string reason);
    event RegistryUpdateFailed(address indexed user, address[] indexed tokens, string reason);
    event ExternalCallFailed(address indexed target, string functionName, string reason);
    event TransactionFailed(address indexed recipient, string reason);
    event UpdateFailed(uint256 indexed listingId, string reason);
    event OrderUpdateIncomplete(uint256 indexed listingId, uint256 orderId, string reason);
    event OrderUpdatesComplete(uint256 indexed listingId, uint256 orderId, bool isBuy);

    // Normalizes amount to 1e18 precision
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256 normalized) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    // Denormalizes amount from 1e18 to token decimals
    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256 denormalized) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    // Checks if two timestamps are on the same day
    function _isSameDay(uint256 time1, uint256 time2) internal pure returns (bool sameDay) {
        return (time1 / 86400) == (time2 / 86400);
    }

    // Rounds timestamp to midnight
    function _floorToMidnight(uint256 timestamp) internal pure returns (uint256 midnight) {
        return (timestamp / 86400) * 86400;
    }

    // Calculates volume change since startTime using historical data
    function _findVolumeChange(bool isA, uint256 startTime, uint256 maxIterations) internal view returns (uint256 volumeChange) {
        uint256 iterationsLeft = maxIterations;
        if (_historicalData.length == 0) return 0;
        for (uint256 i = _historicalData.length; i > 0 && iterationsLeft > 0; i--) {
            HistoricalData memory data = _historicalData[i - 1];
            iterationsLeft--;
            if (data.timestamp >= startTime) {
                return isA ? data.xVolume : data.yVolume;
            }
        }
        if (iterationsLeft == 0 || _historicalData.length <= maxIterations) {
            HistoricalData memory earliest = _historicalData[0];
            return isA ? earliest.xVolume : earliest.yVolume;
        }
        return 0;
    }

    // Updates token registry with balances for both tokens for a single user
    function _updateRegistry(address maker) internal {
        if (registryAddress == address(0) || maker == address(0)) {
            address[] memory emptyTokens = new address[](0);
            emit RegistryUpdateFailed(maker, emptyTokens, "Invalid registry or maker address");
            return;
        }
        uint256 tokenCount = (tokenA != address(0) ? 1 : 0) + (tokenB != address(0) ? 1 : 0);
        address[] memory tokens = new address[](tokenCount);
        uint256 index = 0;
        if (tokenA != address(0)) tokens[index++] = tokenA;
        if (tokenB != address(0)) tokens[index] = tokenB;
        try ITokenRegistry(registryAddress).initializeTokens(maker, tokens) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit RegistryUpdateFailed(maker, tokens, decodedReason);
            emit ExternalCallFailed(registryAddress, "initializeTokens", decodedReason);
        }
    }

    // Removes order ID from array
    function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i] == orderId) {
                orders[i] = orders[orders.length - 1];
                orders.pop();
                break;
            }
        }
    }

    // Calls globalizeOrders with latest order details
    function globalizeUpdate() internal {
        if (globalizerAddress == address(0)) {
            emit GlobalUpdateFailed(listingId, "Invalid globalizer address");
            return;
        }
        uint256 orderId = nextOrderId > 0 ? nextOrderId - 1 : 0; // Use latest order ID or 0 if none
        address maker;
        address token;
        // Check if it's a buy order
        BuyOrderCore memory buyCore = buyOrderCore[orderId];
        if (buyCore.makerAddress != address(0)) {
            maker = buyCore.makerAddress;
            token = tokenB != address(0) ? tokenB : tokenA; // Use tokenB for buy
        } else {
            // Check if it's a sell order
            SellOrderCore memory sellCore = sellOrderCore[orderId];
            if (sellCore.makerAddress != address(0)) {
                maker = sellCore.makerAddress;
                token = tokenA != address(0) ? tokenA : tokenB; // Use tokenA for sell
            } else {
                // No valid order, skip for balance updates
                return;
            }
        }
        try ICCGlobalizer(globalizerAddress).globalizeOrders(maker, token) {
        } catch (bytes memory reason) {
            string memory decodedReason = string(reason);
            emit ExternalCallFailed(globalizerAddress, "globalizeOrders", decodedReason);
            emit GlobalUpdateFailed(listingId, decodedReason);
        }
    }

    // Returns pending buy order IDs
    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return _pendingBuyOrders;
    }

    // Returns pending sell order IDs
    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return _pendingSellOrders;
    }

    // Transfers ERC20 tokens to recipient
    function transactToken(address token, uint256 amount, address recipient) external {
        require(routers[msg.sender], "Caller not router");
        require(token == tokenA || token == tokenB, "Invalid token");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        uint256 preBalance = IERC20(token).balanceOf(recipient);
        try IERC20(token).transfer(recipient, amount) returns (bool success) {
            if (!success) {
                emit TransactionFailed(recipient, "Transfer returned false");
                return;
            }
        } catch (bytes memory reason) {
            emit TransactionFailed(recipient, string(reason));
            return;
        }
        uint256 postBalance = IERC20(token).balanceOf(recipient);
        if (postBalance <= preBalance) {
            emit TransactionFailed(recipient, "No tokens received");
        }
    }

    // Transfers native ETH to recipient
    function transactNative(uint256 amount, address recipient) external payable {
        require(routers[msg.sender], "Caller not router");
        require(tokenA == address(0) || tokenB == address(0), "Native not supported");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(msg.value == amount, "Incorrect ETH amount");
        uint256 preBalance = recipient.balance;
        (bool success, bytes memory reason) = recipient.call{value: amount}("");
        if (!success) {
            emit TransactionFailed(recipient, string(reason));
            return;
        }
        uint256 postBalance = recipient.balance;
        if (postBalance <= preBalance) {
            emit TransactionFailed(recipient, "No ETH received");
        }
    }

    // Processes buy order updates
    function _processBuyOrderUpdate(
        uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount
    ) internal returns (uint256) {
        // Handles buy order updates with direct assignments from router
        uint256 orderId = value; // value is used as orderId
        if (structId == 0) {
            BuyOrderCore memory core;
            (core.makerAddress, core.recipientAddress, core.status) = abi.decode(
                bytes(uint2str(value)), (address, address, uint8)
            );
            buyOrderCore[orderId] = core;
            orderStatus[orderId].hasCore = true;
            if (core.status == 1) {
                _pendingBuyOrders.push(orderId);
                makerPendingOrders[core.makerAddress].push(orderId);
            } else if (core.status == 0 || core.status == 3) {
                removePendingOrder(_pendingBuyOrders, orderId);
                removePendingOrder(makerPendingOrders[core.makerAddress], orderId);
            }
            emit OrderUpdated(listingId, orderId, true, core.status);
        } else if (structId == 1) {
            BuyOrderPricing memory pricing;
            (pricing.maxPrice, pricing.minPrice) = abi.decode(
                bytes(uint2str(value)), (uint256, uint256)
            );
            buyOrderPricing[orderId] = pricing;
            orderStatus[orderId].hasPricing = true;
        } else if (structId == 2) {
            BuyOrderAmounts memory amounts;
            (amounts.pending, amounts.filled, amounts.amountSent) = abi.decode(
                bytes(uint2str(value)), (uint256, uint256, uint256)
            );
            buyOrderAmounts[orderId] = amounts;
            if (amounts.pending > 0 || amounts.filled > 0) {
                _historicalData[_historicalData.length - 1].yVolume += amounts.filled;
            }
            orderStatus[orderId].hasAmounts = true;
        } else {
            emit UpdateFailed(listingId, "Invalid buy order structId");
            return updatedCount;
        }
        if (updatedCount < updatedOrders.length && updatedOrders[updatedCount] != orderId) {
            updatedOrders[updatedCount] = orderId;
            updatedCount++;
        }
        return updatedCount;
    }

    // Processes sell order updates
    function _processSellOrderUpdate(
        uint8 structId, uint256 value, uint256[] memory updatedOrders, uint256 updatedCount
    ) internal returns (uint256) {
        // Handles sell order updates with direct assignments from router
        uint256 orderId = value; // value is used as orderId
        if (structId == 0) {
            SellOrderCore memory core;
            (core.makerAddress, core.recipientAddress, core.status) = abi.decode(
                bytes(uint2str(value)), (address, address, uint8)
            );
            sellOrderCore[orderId] = core;
            orderStatus[orderId].hasCore = true;
            if (core.status == 1) {
                _pendingSellOrders.push(orderId);
                makerPendingOrders[core.makerAddress].push(orderId);
            } else if (core.status == 0 || core.status == 3) {
                removePendingOrder(_pendingSellOrders, orderId);
                removePendingOrder(makerPendingOrders[core.makerAddress], orderId);
            }
            emit OrderUpdated(listingId, orderId, false, core.status);
        } else if (structId == 1) {
            SellOrderPricing memory pricing;
            (pricing.maxPrice, pricing.minPrice) = abi.decode(
                bytes(uint2str(value)), (uint256, uint256)
            );
            sellOrderPricing[orderId] = pricing;
            orderStatus[orderId].hasPricing = true;
        } else if (structId == 2) {
            SellOrderAmounts memory amounts;
            (amounts.pending, amounts.filled, amounts.amountSent) = abi.decode(
                bytes(uint2str(value)), (uint256, uint256, uint256)
            );
            sellOrderAmounts[orderId] = amounts;
            if (amounts.pending > 0 || amounts.filled > 0) {
                _historicalData[_historicalData.length - 1].xVolume += amounts.filled;
            }
            orderStatus[orderId].hasAmounts = true;
        } else {
            emit UpdateFailed(listingId, "Invalid sell order structId");
            return updatedCount;
        }
        if (updatedCount < updatedOrders.length && updatedOrders[updatedCount] != orderId) {
            updatedOrders[updatedCount] = orderId;
            updatedCount++;
        }
        return updatedCount;
    }

    // Processes historical data updates
    function _processHistoricalUpdate(uint8 structId, uint256 value) internal returns (bool historicalUpdated) {
    // Handles historical data updates
    if (structId != 0) {
        emit UpdateFailed(listingId, "Invalid historical structId");
        return false;
    }
    uint256 balanceA = tokenA == address(0) ? address(this).balance : normalize(IERC20(tokenA).balanceOf(address(this)), decimalsA);
    uint256 balanceB = tokenB == address(0) ? address(this).balance : normalize(IERC20(tokenB).balanceOf(address(this)), decimalsB);
    _historicalData.push(HistoricalData({
        price: value,
        xBalance: balanceA,
        yBalance: balanceB,
        xVolume: 0,
        yVolume: 0,
        timestamp: value > 0 ? block.timestamp : _floorToMidnight(block.timestamp)
    }));
    uint256 midnight = _floorToMidnight(block.timestamp);
    if (_dayStartIndices[midnight] == 0) {
        _dayStartIndices[midnight] = _historicalData.length - 1;
    }
    return true;
}

    // Modified ccUpdate function with three parameters
    function ccUpdate(
    uint8[] calldata updateType,
    uint8[] calldata updateSort,
    uint256[] calldata updateData
) external {
    // Updates orders and historical data, only callable by routers
    require(routers[msg.sender], "Caller not router");
    require(updateType.length == updateSort.length && updateType.length == updateData.length,
            "Array length mismatch");
    uint256 currentMidnight = (block.timestamp / 86400) * 86400;
    uint256[] memory updatedOrders = new uint256[](updateType.length);
    uint256 updatedCount = 0;

    for (uint256 i = 0; i < updateType.length; i++) {
        if (updateType[i] == 0) { // Balance update retained for compatibility
            continue; // No manual balance updates, handled by volumeBalances
        } else if (updateType[i] == 1) { // Buy order
            updatedCount = _processBuyOrderUpdate(
                updateSort[i], updateData[i], updatedOrders, updatedCount
            );
        } else if (updateType[i] == 2) { // Sell order
            updatedCount = _processSellOrderUpdate(
                updateSort[i], updateData[i], updatedOrders, updatedCount
            );
        } else if (updateType[i] == 3) { // Historical
            _processHistoricalUpdate(updateSort[i], updateData[i]);
        } else {
            emit UpdateFailed(listingId, "Invalid update type");
            continue;
        }
    }

    if (_historicalData.length > 0 && !_isSameDay(dayStartFee.timestamp, currentMidnight)) {
        dayStartFee = DayStartFee({
            dayStartXFeesAcc: 0,
            dayStartYFeesAcc: 0,
            timestamp: currentMidnight
        });
        try ICCLiquidityTemplate(liquidityAddressView).liquidityDetail() returns (
            uint256 /* xLiq */, uint256 /* yLiq */, uint256, uint256, uint256 xFees, uint256 yFees
        ) {
            dayStartFee.dayStartXFeesAcc = xFees;
            dayStartFee.dayStartYFeesAcc = yFees;
        } catch {
            emit UpdateFailed(listingId, "Failed to fetch liquidity details");
        }
    }

    for (uint256 i = 0; i < updatedCount; i++) {
        uint256 orderId = updatedOrders[i];
        OrderStatus storage status = orderStatus[orderId];
        bool isBuy = buyOrderCore[orderId].makerAddress != address(0);
        if (status.hasCore && status.hasPricing && status.hasAmounts) {
            emit OrderUpdatesComplete(listingId, orderId, isBuy);
        } else {
            string memory reason = !status.hasCore ? "Missing Core struct" :
                                  !status.hasPricing ? "Missing Pricing struct" : "Missing Amounts struct";
            emit OrderUpdateIncomplete(listingId, orderId, reason);
        }
    }

    // Removed Uniswap balance checks, price derived from internal balances
    globalizeUpdate();
}

    // Sets globalizer contract address, callable once
    function setGlobalizerAddress(address globalizerAddress_) external {
        require(!_globalizerSet, "Globalizer already set");
        require(globalizerAddress_ != address(0), "Invalid globalizer address");
        globalizerAddress = globalizerAddress_;
        _globalizerSet = true;
        emit GlobalizerAddressSet(globalizerAddress_);
    }

    function setRouters(address[] memory routers_) external {
        // Sets router addresses, callable once
        require(!_routersSet, "Routers already set");
        require(routers_.length > 0, "No routers provided");
        for (uint256 i = 0; i < routers_.length; i++) {
            require(routers_[i] != address(0), "Invalid router address");
            routers[routers_[i]] = true;
            routerAddresses.push(routers_[i]);
        }
        _routersSet = true;
    }

    // Sets listing ID, callable once
    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    // Sets liquidity address, callable once
    function setLiquidityAddress(address _liquidityAddress) external {
        require(liquidityAddressView == address(0), "Liquidity already set");
        require(_liquidityAddress != address(0), "Invalid liquidity address");
        liquidityAddressView = _liquidityAddress;
    }

    // Sets token addresses, initializes historical data and dayStartFee
    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
        decimalsA = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        decimalsB = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
        uint256 midnight = _floorToMidnight(block.timestamp);
        _historicalData.push(HistoricalData({
            price: 0,
            xBalance: 0,
            yBalance: 0,
            xVolume: 0,
            yVolume: 0,
            timestamp: midnight
        }));
        _dayStartIndices[midnight] = 0;
        dayStartFee = DayStartFee({
            dayStartXFeesAcc: 0,
            dayStartYFeesAcc: 0,
            timestamp: midnight
        });
    }

    // Sets agent address, callable once
    function setAgent(address _agent) external {
        require(agentView == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agentView = _agent;
    }

    // Sets registry address, callable once
    function setRegistry(address registryAddress_) external {
        require(registryAddress == address(0), "Registry already set");
        require(registryAddress_ != address(0), "Invalid registry address");
        registryAddress = registryAddress_;
    }
    
    // Resets routers array to agent's latest routers, restricted to lister
function resetRouters() external {
    // Fetch lister from agent for the current listing
    address lister = ICCAgent(agentView).getLister(address(this));
    require(msg.sender == lister, "Only lister can reset routers");
    
    // Fetch latest routers from agent
    address[] memory newRouters = ICCAgent(agentView).getRouters();
    require(newRouters.length > 0, "No routers available in agent");

    // Clear existing routers mapping and array
    for (uint256 i = 0; i < routerAddresses.length; i++) {
        routers[routerAddresses[i]] = false;
    }
    delete routerAddresses;

    // Update with new routers
    for (uint256 i = 0; i < newRouters.length; i++) {
        require(newRouters[i] != address(0), "Invalid router address");
        routers[newRouters[i]] = true;
        routerAddresses.push(newRouters[i]);
    }
    _routersSet = true;
}

    // Returns token pair
    function getTokens() external view returns (address tokenA_, address tokenB_) {
        require(tokenA != address(0) || tokenB != address(0), "Tokens not set");
        return (tokenA, tokenB);
    }

    // Returns next order ID
    function getNextOrderId() external view returns (uint256 orderId_) {
        return nextOrderId;
    }
    
    function routerAddressesView() external view returns (address[] memory addresses) {
        // Returns router addresses
        return routerAddresses;
    }
    
    // Computes current price from balances
    function prices(uint256 _listingId) external view returns (uint256 price) {
    uint256 balanceA = tokenA == address(0) ? address(this).balance : normalize(IERC20(tokenA).balanceOf(address(this)), decimalsA);
    uint256 balanceB = tokenB == address(0) ? address(this).balance : normalize(IERC20(tokenB).balanceOf(address(this)), decimalsB);
    return balanceA == 0 ? 0 : (balanceB * 1e18) / balanceA;
}

// Rounds a timestamp to the start of its day (midnight UTC)
function floorToMidnightView(uint256 inputTimestamp) external pure returns (uint256 midnight) {
    midnight = (inputTimestamp / 86400) * 86400;
}

// Checks if two timestamps are in the same calendar day (UTC)
function isSameDayView(uint256 firstTimestamp, uint256 secondTimestamp) external pure returns (bool sameDay) {
    sameDay = (firstTimestamp / 86400) == (secondTimestamp / 86400);
}

// Returns the historical data index for a given midnight timestamp
function getDayStartIndex(uint256 midnightTimestamp) external view returns (uint256 index) {
    index = _dayStartIndices[midnightTimestamp];
}

    // Returns real-time token balances
    function volumeBalances(uint256 _listingId) external view returns (uint256 xBalance, uint256 yBalance) {
    xBalance = tokenA == address(0) ? address(this).balance : normalize(IERC20(tokenA).balanceOf(address(this)), decimalsA);
    yBalance = tokenB == address(0) ? address(this).balance : normalize(IERC20(tokenB).balanceOf(address(this)), decimalsB);
}

    // Returns up to maxIterations pending buy order IDs for a maker, starting from step
    function makerPendingBuyOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrders[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (buyOrderCore[allOrders[i]].makerAddress == maker && buyOrderCore[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (buyOrderCore[allOrders[i]].makerAddress == maker && buyOrderCore[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns up to maxIterations pending sell order IDs for a maker, starting from step
    function makerPendingSellOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrders[maker];
        uint256 count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (sellOrderCore[allOrders[i]].makerAddress == maker && sellOrderCore[allOrders[i]].status == 1) {
                count++;
            }
        }
        orderIds = new uint256[](count);
        count = 0;
        for (uint256 i = step; i < allOrders.length && count < maxIterations; i++) {
            if (sellOrderCore[allOrders[i]].makerAddress == maker && sellOrderCore[allOrders[i]].status == 1) {
                orderIds[count++] = allOrders[i];
            }
        }
    }

    // Returns buy order core details
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        BuyOrderCore memory core = buyOrderCore[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns buy order pricing details
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        BuyOrderPricing memory pricing = buyOrderPricing[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns buy order amounts
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        BuyOrderAmounts memory amounts = buyOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }

    // Returns sell order core details
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status) {
        SellOrderCore memory core = sellOrderCore[orderId];
        return (core.makerAddress, core.recipientAddress, core.status);
    }

    // Returns sell order pricing details
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice) {
        SellOrderPricing memory pricing = sellOrderPricing[orderId];
        return (pricing.maxPrice, pricing.minPrice);
    }

    // Returns sell order amounts
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent) {
        SellOrderAmounts memory amounts = sellOrderAmounts[orderId];
        return (amounts.pending, amounts.filled, amounts.amountSent);
    }
    
    // Returns up to maxIterations order IDs for a maker, starting from step
    function makerOrdersView(address maker, uint256 step, uint256 maxIterations) external view returns (uint256[] memory orderIds) {
        uint256[] memory allOrders = makerPendingOrders[maker];
        uint256 length = allOrders.length;
        if (step >= length) return new uint256[](0);
        uint256 limit = maxIterations < (length - step) ? maxIterations : (length - step);
        orderIds = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            orderIds[i] = allOrders[step + i];
        }
    }

    // Returns pending orders for a maker
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory orderIds) {
        return makerPendingOrders[maker];
    }

    // Returns historical data at index
    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory data) {
        require(index < _historicalData.length, "Invalid index");
        return _historicalData[index];
    }

    // Returns historical data length
    function historicalDataLengthView() external view returns (uint256 length) {
        return _historicalData.length;
    }

    // Utility function to convert uint to string for error messages
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}