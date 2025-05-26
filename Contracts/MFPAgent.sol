// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.12 (Updated)
// Changes:
// - Added global liquidity and order tracking from OMFAgent.sol (globalLiquidity, totalLiquidityPerPair, userTotalLiquidity, listingLiquidity, historicalLiquidityPerPair, historicalLiquidityPerUser, globalOrders, pairOrders, userOrders, historicalOrderStatus, userTradingSummaries).
// - Added globalizeLiquidity and globalizeOrders functions with caller restrictions.
// - Added view functions: getUserLiquidityAcrossPairs, getTopLiquidityProviders, getUserLiquidityShare, getAllPairsByLiquidity, getPairLiquidityTrend, getUserLiquidityTrend, getOrderActivityByPair, getUserTradingProfile, getTopTradersByVolume, getAllPairsByOrderVolume.
// - Added registryAddress, setRegistry function, and updated IMFPListingTemplate to include setRegistry.
// - Added setAgent to IMFPListingTemplate and IMFPLiquidityTemplate, called in _initializePair.
// - Imported SafeERC20 and added using statement for IERC20.
// - Refactored listToken and listNative to use prepListing and executeListing for modularity.
// - Added _sortDescending helper for view functions.
// - Preserved core functionality of listToken, listNative, queryByAddressView, and allListingsLength.

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface IMFPListingTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
}

interface IMFPLiquidityTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
}

interface IMFPListingLogic {
    function deploy(bytes32 listingSalt) external returns (address listingAddress);
}

interface IMFPLiquidityLogic {
    function deploy(bytes32 liquiditySalt) external returns (address liquidityAddress);
}

interface IMFPListing {
    function liquidityAddress() external view returns (address);
}

contract MFPAgent is Ownable {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public listingLogicAddress;
    address public liquidityLogicAddress;
    address public registryAddress;
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing;
    address[] public allListings;
    address[] public allListedTokens;
    mapping(address => uint256[]) public queryByAddress;

    mapping(address => mapping(address => mapping(address => uint256))) public globalLiquidity; // tokenA => tokenB => user => amount
    mapping(address => mapping(address => uint256)) public totalLiquidityPerPair; // tokenA => tokenB => amount
    mapping(address => uint256) public userTotalLiquidity; // user => total liquidity
    mapping(uint256 => mapping(address => uint256)) public listingLiquidity; // listingId => user => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public historicalLiquidityPerPair; // tokenA => tokenB => timestamp => amount
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public historicalLiquidityPerUser; // tokenA => tokenB => user => timestamp => amount

    struct GlobalOrder {
        uint256 orderId;
        bool isBuy;
        address maker;
        address recipient;
        uint256 amount;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp;
    }

    mapping(address => mapping(address => mapping(uint256 => GlobalOrder))) public globalOrders; // tokenA => tokenB => orderId => GlobalOrder
    mapping(address => mapping(address => uint256[])) public pairOrders; // tokenA => tokenB => orderId[]
    mapping(address => uint256[]) public userOrders; // user => orderId[]
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))) public historicalOrderStatus; // tokenA => tokenB => orderId => timestamp => status
    mapping(address => mapping(address => mapping(address => uint256))) public userTradingSummaries; // user => tokenA => tokenB => volume

    struct InitData {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }

    struct TrendData {
        address token;
        uint256 timestamp;
        uint256 amount;
    }

    struct OrderData {
        uint256 orderId;
        bool isBuy;
        address maker;
        address recipient;
        uint256 amount;
        uint8 status;
        uint256 timestamp;
    }

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);
    event GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);

    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (allListedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function setRouter(address _routerAddress) external onlyOwner {
        require(_routerAddress != address(0), "Invalid router address");
        routerAddress = _routerAddress;
    }

    function setListingLogic(address _listingLogic) external onlyOwner {
        require(_listingLogic != address(0), "Invalid logic address");
        listingLogicAddress = _listingLogic;
    }

    function setLiquidityLogic(address _liquidityLogic) external onlyOwner {
        require(_liquidityLogic != address(0), "Invalid logic address");
        liquidityLogicAddress = _liquidityLogic;
    }

    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    function _deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingId));
        listingAddress = IMFPListingLogic(listingLogicAddress).deploy(listingSalt);
        liquidityAddress = IMFPLiquidityLogic(liquidityLogicAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    function _initializePair(InitData memory init) internal {
        IMFPListingTemplate(init.listingAddress).setRouter(routerAddress);
        IMFPListingTemplate(init.listingAddress).setListingId(init.listingId);
        IMFPListingTemplate(init.listingAddress).setLiquidityAddress(init.liquidityAddress);
        IMFPListingTemplate(init.listingAddress).setTokens(init.tokenA, init.tokenB);
        IMFPListingTemplate(init.listingAddress).setAgent(address(this));
        IMFPListingTemplate(init.listingAddress).setRegistry(registryAddress);

        IMFPLiquidityTemplate(init.liquidityAddress).setRouter(routerAddress);
        IMFPLiquidityTemplate(init.liquidityAddress).setListingId(init.listingId);
        IMFPLiquidityTemplate(init.liquidityAddress).setListingAddress(init.listingAddress);
        IMFPLiquidityTemplate(init.liquidityAddress).setTokens(init.tokenA, init.tokenB);
        IMFPLiquidityTemplate(init.liquidityAddress).setAgent(address(this));
    }

    function _updateState(address tokenA, address tokenB, address listingAddress, uint256 listingId) internal {
        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);
        if (!tokenExists(tokenA)) {
            allListedTokens.push(tokenA);
        }
        if (!tokenExists(tokenB)) {
            allListedTokens.push(tokenB);
        }
        queryByAddress[tokenA].push(listingId);
        queryByAddress[tokenB].push(listingId);
    }

    function prepListing(address tokenA, address tokenB) internal returns (InitData memory) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routerAddress != address(0), "Router not set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");

        (address listingAddress, address liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        InitData memory init = InitData(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        return init;
    }

    function executeListing(InitData memory init) internal returns (address listingAddress, address liquidityAddress) {
        _initializePair(init);
        _updateState(init.tokenA, init.tokenB, init.listingAddress, init.listingId);
        emit ListingCreated(init.tokenA, init.tokenB, init.listingAddress, init.liquidityAddress, init.listingId);
        listingCount++;
        return (init.listingAddress, init.liquidityAddress);
    }

    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        InitData memory init = prepListing(tokenA, tokenB);
        (listingAddress, liquidityAddress) = executeListing(init);
        return (listingAddress, liquidityAddress);
    }

    function listNative(address token, bool isA) external returns (address listingAddress, address liquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        InitData memory init = prepListing(tokenA, tokenB);
        (listingAddress, liquidityAddress) = executeListing(init);
        return (listingAddress, liquidityAddress);
    }

    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(user != address(0), "Invalid user");
        require(listingId < listingCount, "Invalid listing ID");
        address listingAddress = getListing[tokenA][tokenB];
        require(listingAddress != address(0), "Listing not found");
        require(IMFPListing(listingAddress).liquidityAddress() == msg.sender, "Not liquidity contract");

        _updateGlobalLiquidity(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

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
    ) external {
        require(tokenA != address(0) && tokenB != address(0), "Invalid tokens");
        require(maker != address(0), "Invalid maker");
        require(listingId < listingCount, "Invalid listing ID");
        require(getListing[tokenA][tokenB] == msg.sender, "Not listing contract");

        GlobalOrder storage order = globalOrders[tokenA][tokenB][orderId];
        if (order.maker == address(0) && status != 0) { // New order
            order.orderId = orderId;
            order.isBuy = isBuy;
            order.maker = maker;
            order.recipient = recipient;
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
            pairOrders[tokenA][tokenB].push(orderId);
            userOrders[maker].push(orderId);
        } else { // Update existing order
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
        }

        historicalOrderStatus[tokenA][tokenB][orderId][block.timestamp] = status;
        if (amount > 0) {
            userTradingSummaries[maker][tokenA][tokenB] += amount;
        }

        emit GlobalOrderChanged(listingId, tokenA, tokenB, orderId, isBuy, maker, amount, status);
    }

    function _updateGlobalLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) internal {
        if (isDeposit) {
            globalLiquidity[tokenA][tokenB][user] += amount;
            totalLiquidityPerPair[tokenA][tokenB] += amount;
            userTotalLiquidity[user] += amount;
            listingLiquidity[listingId][user] += amount;
        } else {
            require(globalLiquidity[tokenA][tokenB][user] >= amount, "Insufficient user liquidity");
            require(totalLiquidityPerPair[tokenA][tokenB] >= amount, "Insufficient pair liquidity");
            require(userTotalLiquidity[user] >= amount, "Insufficient total liquidity");
            require(listingLiquidity[listingId][user] >= amount, "Insufficient listing liquidity");
            globalLiquidity[tokenA][tokenB][user] -= amount;
            totalLiquidityPerPair[tokenA][tokenB] -= amount;
            userTotalLiquidity[user] -= amount;
            listingLiquidity[listingId][user] -= amount;
        }

        historicalLiquidityPerPair[tokenA][tokenB][block.timestamp] = totalLiquidityPerPair[tokenA][tokenB];
        historicalLiquidityPerUser[tokenA][tokenB][user][block.timestamp] = globalLiquidity[tokenA][tokenB][user];

        emit GlobalLiquidityChanged(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external
        view
        returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address token = allListedTokens[i];
            for (uint256 j = 0; j < allListedTokens.length && count < maxPairs; j++) {
                address tokenB = allListedTokens[j];
                if (getListing[token][tokenB] != address(0)) {
                    uint256 amount = globalLiquidity[token][tokenB][user];
                    if (amount > 0) {
                        temp[count] = TrendData(token, 0, amount);
                        count++;
                    }
                }
            }
        }

        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = address(0); // Placeholder, updated in loop
            amounts[i] = temp[i].amount;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[temp[i].token][allListedTokens[j]] != address(0)) {
                    tokenBs[i] = allListedTokens[j];
                    break;
                }
            }
        }
    }

    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external
        view
        returns (address[] memory users, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < allListings.length ? maxIterations : allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;

        for (uint256 i = 0; i < allListings.length && count < maxLimit; i++) {
            address user = allListings[i];
            uint256 amount = listingLiquidity[listingId][user];
            if (amount > 0) {
                temp[count] = TrendData(user, 0, amount);
                count++;
            }
        }

        _sortDescending(temp, count);
        users = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = temp[i].token;
            amounts[i] = temp[i].amount;
        }
    }

    function getUserLiquidityShare(address user, address tokenA, address tokenB)
        external
        view
        returns (uint256 share, uint256 total)
    {
        total = totalLiquidityPerPair[tokenA][tokenB];
        uint256 userAmount = globalLiquidity[tokenA][tokenB][user];
        share = total > 0 ? (userAmount * 1e18) / total : 0;
    }

    function getAllPairsByLiquidity(uint256 minLiquidity, uint256 maxIterations)
        external
        view
        returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address tokenA = allListedTokens[i];
            for (uint256 j = 0; j < allListedTokens.length && count < maxPairs; j++) {
                address tokenB = allListedTokens[j];
                uint256 amount = totalLiquidityPerPair[tokenA][tokenB];
                if (amount >= minLiquidity && getListing[tokenA][tokenB] != address(0)) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        }

        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            amounts[i] = temp[i].amount;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[temp[i].token][allListedTokens[j]] != address(0)) {
                    tokenBs[i] = allListedTokens[j];
                    break;
                }
            }
        }
    }

    function getPairLiquidityTrend(
        address tokenA,
        address tokenB,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || tokenA == address(0) || tokenB == address(0)) {
            return (new uint256[](0), new uint256[](0));
        }

        TrendData[] memory temp = new TrendData[](endTime - startTime + 1);
        uint256 count = 0;

        if (getListing[tokenA][tokenB] != address(0)) {
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerPair[tokenA][tokenB][t];
                if (amount > 0) {
                    temp[count] = TrendData(address(0), t, amount);
                    count++;
                }
            }
        }

        timestamps = new uint256[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            timestamps[i] = temp[i].timestamp;
            amounts[i] = temp[i].amount;
        }
    }

    function getUserLiquidityTrend(
        address user,
        address tokenA,
        address tokenB,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || user == address(0)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }

        TrendData[] memory temp = new TrendData[](endTime - startTime + 1);
        uint256 count = 0;

        if (getListing[tokenA][tokenB] != address(0)) {
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerUser[tokenA][tokenB][user][t];
                if (amount > 0) {
                    temp[count] = TrendData(tokenA, t, amount);
                    count++;
                }
            }
        }

        tokens = new address[](count);
        timestamps = new uint256[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = temp[i].token;
            timestamps[i] = temp[i].timestamp;
            amounts[i] = temp[i].amount;
        }
    }

    function getOrderActivityByPair(
        address tokenA,
        address tokenB,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory orderIds, OrderData[] memory orders) {
        if (endTime < startTime || tokenA == address(0) || tokenB == address(0)) {
            return (new uint256[](0), new OrderData[](0));
        }

        uint256[] memory pairOrderIds = pairOrders[tokenA][tokenB];
        OrderData[] memory temp = new OrderData[](pairOrderIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < pairOrderIds.length; i++) {
            GlobalOrder memory order = globalOrders[tokenA][tokenB][pairOrderIds[i]];
            if (order.timestamp >= startTime && order.timestamp <= endTime) {
                temp[count] = OrderData(
                    order.orderId,
                    order.isBuy,
                    order.maker,
                    order.recipient,
                    order.amount,
                    order.status,
                    order.timestamp
                );
                count++;
            }
        }

        orderIds = new uint256[](count);
        orders = new OrderData[](count);
        for (uint256 i = 0; i < count; i++) {
            orderIds[i] = temp[i].orderId;
            orders[i] = temp[i];
        }
    }

    function getUserTradingProfile(address user)
        external
        view
        returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        uint256 maxPairs = allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                address tokenB = allListedTokens[j];
                uint256 volume = userTradingSummaries[user][tokenA][tokenB];
                if (volume > 0 && getListing[tokenA][tokenB] != address(0)) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                    break;
                }
            }
        }

        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            volumes[i] = temp[i].amount;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[temp[i].token][allListedTokens[j]] != address(0)) {
                    tokenBs[i] = allListedTokens[j];
                    break;
                }
            }
        }
    }

    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external
        view
        returns (address[] memory traders, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < allListings.length ? maxIterations : allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;

        for (uint256 i = 0; i < allListings.length && count < maxLimit; i++) {
            address trader = allListings[i];
            address tokenA;
            address tokenB;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                for (uint256 k = 0; k < allListedTokens.length; k++) {
                    if (getListing[allListedTokens[j]][allListedTokens[k]] == trader) {
                        tokenA = allListedTokens[j];
                        tokenB = allListedTokens[k];
                        break;
                    }
                }
                if (tokenA != address(0)) break;
            }
            if (tokenA != address(0)) {
                uint256 volume = userTradingSummaries[trader][tokenA][tokenB];
                if (volume > 0) {
                    temp[count] = TrendData(trader, 0, volume);
                    count++;
                }
            }
        }

        _sortDescending(temp, count);
        traders = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            traders[i] = temp[i].token;
            volumes[i] = temp[i].amount;
        }
    }

    function getAllPairsByOrderVolume(uint256 minVolume, uint256 maxIterations)
        external
        view
        returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address tokenA = allListedTokens[i];
            for (uint256 j = 0; j < allListedTokens.length && count < maxPairs; j++) {
                address tokenB = allListedTokens[j];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][tokenB];
                for (uint256 k = 0; k < orderIds.length; k++) {
                    volume += globalOrders[tokenA][tokenB][orderIds[k]].amount;
                }
                if (volume >= minVolume && getListing[tokenA][tokenB] != address(0)) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        }

        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            volumes[i] = temp[i].amount;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[temp[i].token][allListedTokens[j]] != address(0)) {
                    tokenBs[i] = allListedTokens[j];
                    break;
                }
            }
        }
    }

    function _sortDescending(TrendData[] memory data, uint256 length) internal pure {
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (data[i].amount < data[j].amount) {
                    TrendData memory temp = data[i];
                    data[i] = data[j];
                    data[j] = temp;
                }
            }
        }
    }

    function queryByAddressView(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = queryByAddress[target];
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }
}