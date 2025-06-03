// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.0.14
// Changes:
// - From v0.0.13: Added validateListing implementation to support OrderPartial.sol compatibility.
// - From v0.0.12: Fixed TypeError in getUserLiquidityAcrossPairs by correcting amounts array type from address[] to uint256[] (line 446).
// - From v0.0.11: Removed caps on query functions (getTopLiquidityProviders, getUserLiquidityAcrossPairs, getAllPairsByLiquidity, getTopTradersByVolume, getAllPairsByOrderVolume), replaced with user-supplied maxIterations parameter.
// - Added setRegistry function (onlyOwner) and public registryAddress state variable, called in _initializeListing to set registry on listing contract.
// - Split _initializePair into _initializeListing and _initializeLiquidity to reduce stack depth, using InitData struct.
// - Updated IOMFListingTemplate interface to include setRegistry.
// - Preserved all liquidity management, listing creation, and existing view functions unchanged.
// - Maintained GlobalOrderChanged event for order updates.

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface IOMFListingTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setOracleDetails(address oracle, uint8 decimals, bytes4 viewFunction) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
}

interface IOMFLiquidityTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
}

interface IOMFListingLogic {
    function deploy(bytes32 listingSalt) external returns (address listingAddress);
}

interface IOMFLiquidityLogic {
    function deploy(bytes32 liquiditySalt) external returns (address liquidityAddress);
}

interface IOMFListing {
    function liquidityAddress() external view returns (address);
}

contract OMFAgent is Ownable {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public listingLogicAddress;
    address public liquidityLogicAddress;
    address public baseToken; // Token-1 (reference token)
    address public registryAddress; // TokenRegistry address
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing; // tokenA (Token-0) to baseToken (Token-1)
    address[] public allListings;
    address[] public allListedTokens;

    mapping(address => mapping(address => mapping(address => uint256))) public globalLiquidity; // token0 => baseToken => user => amount
    mapping(address => mapping(address => uint256)) public totalLiquidityPerPair; // token0 => baseToken => amount
    mapping(address => uint256) public userTotalLiquidity; // user => total liquidity
    mapping(uint256 => mapping(address => uint256)) public listingLiquidity; // listingId => user => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public historicalLiquidityPerPair; // token0 => baseToken => timestamp => amount
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public historicalLiquidityPerUser; // token0 => baseToken => user => timestamp => amount

    struct GlobalOrder {
        uint256 orderId;
        bool isBuy;
        address maker;
        address recipient;
        uint256 amount;
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp;
    }

    mapping(address => mapping(address => mapping(uint256 => GlobalOrder))) public globalOrders; // token0 => baseToken => orderId => GlobalOrder
    mapping(address => mapping(address => uint256[])) public pairOrders; // token0 => baseToken => orderId[]
    mapping(address => uint256[]) public userOrders; // user => orderId[]
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))) public historicalOrderStatus; // token0 => baseToken => orderId => timestamp => status
    mapping(address => mapping(address => mapping(address => uint256))) public userTradingSummaries; // user => token0 => baseToken => volume

    struct PrepData {
        bytes32 listingSalt;
        bytes32 liquiditySalt;
        address tokenA; // Token-0
        address oracleAddress;
        uint8 oracleDecimals;
        bytes4 oracleViewFunction;
    }

    struct InitData {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
        address oracleAddress;
        uint8 oracleDecimals;
        bytes4 oracleViewFunction;
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
    event GlobalLiquidityChanged(uint256 listingId, address token0, address baseToken, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address token0, address baseToken, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);

    constructor() {}

    function validateListing(address listingAddress) external view returns (bool, address, address, address) {
        if (listingAddress == address(0)) {
            return (false, address(0), address(0), address(0));
        }
        address token0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (getListing[allListedTokens[i]][baseToken] == listingAddress) {
                token0 = allListedTokens[i];
                break;
            }
        }
        if (token0 == address(0) || baseToken == address(0)) {
            return (false, address(0), address(0), address(0));
        }
        return (true, listingAddress, token0, baseToken);
    }

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

    function setBaseToken(address _baseToken) external onlyOwner {
        require(_baseToken != address(0), "Base token cannot be NATIVE");
        baseToken = _baseToken; // Token-1
    }

    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    function checkCallerBalance(address tokenA, uint256 totalSupply) internal view returns (bool) {
        uint256 decimals = IERC20(tokenA).decimals();
        uint256 requiredBalance = totalSupply / 100; // 1% of total supply
        if (decimals != 18) {
            requiredBalance = (totalSupply * 1e18) / (100 * 10 ** decimals);
        }
        return IERC20(tokenA).balanceOf(msg.sender) >= requiredBalance;
    }

    function _initializeListing(InitData memory init) internal {
        IOMFListingTemplate(init.listingAddress).setRouter(routerAddress);
        IOMFListingTemplate(init.listingAddress).setListingId(init.listingId);
        IOMFListingTemplate(init.listingAddress).setLiquidityAddress(init.liquidityAddress);
        IOMFListingTemplate(init.listingAddress).setTokens(init.tokenA, init.tokenB);
        IOMFListingTemplate(init.listingAddress).setOracleDetails(init.oracleAddress, init.oracleDecimals, init.oracleViewFunction);
        IOMFListingTemplate(init.listingAddress).setAgent(address(this));
        IOMFListingTemplate(init.listingAddress).setRegistry(registryAddress);
    }

    function _initializeLiquidity(InitData memory init) internal {
        IOMFLiquidityTemplate(init.liquidityAddress).setRouter(routerAddress);
        IOMFLiquidityTemplate(init.liquidityAddress).setListingId(init.listingId);
        IOMFLiquidityTemplate(init.liquidityAddress).setListingAddress(init.listingAddress);
        IOMFLiquidityTemplate(init.liquidityAddress).setTokens(init.tokenA, init.tokenB);
        IOMFLiquidityTemplate(init.liquidityAddress).setAgent(address(this));
    }

    function prepListing(
        address tokenA, // Token-0
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) internal returns (address) {
        require(baseToken != address(0), "Base token not set");
        require(tokenA != baseToken, "Identical tokens");
        require(tokenA != address(0), "TokenA cannot be NATIVE");
        require(getListing[tokenA][baseToken] == address(0), "Pair already listed");
        require(routerAddress != address(0), "Router not set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(oracleAddress != address(0), "Invalid oracle address");

        uint256 supply = IERC20(tokenA).totalSupply();
        require(checkCallerBalance(tokenA, supply), "Must own at least 1% of token supply");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, baseToken, listingCount));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(baseToken, tokenA, listingCount));

        PrepData memory prep = PrepData(listingSalt, liquiditySalt, tokenA, oracleAddress, oracleDecimals, oracleViewFunction);
        return executeListing(prep);
    }

    function executeListing(PrepData memory prep) internal returns (address) {
        address listingAddress = IOMFListingLogic(listingLogicAddress).deploy(prep.listingSalt);
        address liquidityAddress = IOMFLiquidityLogic(liquidityLogicAddress).deploy(prep.liquiditySalt);

        InitData memory init = InitData(
            listingAddress,
            liquidityAddress,
            prep.tokenA,
            baseToken,
            listingCount,
            prep.oracleAddress,
            prep.oracleDecimals,
            prep.oracleViewFunction
        );

        _initializeListing(init);
        _initializeLiquidity(init);

        getListing[prep.tokenA][baseToken] = listingAddress;
        allListings.push(listingAddress);

        if (!tokenExists(prep.tokenA)) {
            allListedTokens.push(prep.tokenA);
        }

        emit ListingCreated(prep.tokenA, baseToken, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return listingAddress;
    }

    function listToken(
        address tokenA, // Token-0
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) external returns (address listingAddress, address liquidityAddress) {
        address deployedListing = prepListing(tokenA, oracleAddress, oracleDecimals, oracleViewFunction);
        listingAddress = deployedListing;
        liquidityAddress = IOMFListing(deployedListing).liquidityAddress();
        return (listingAddress, liquidityAddress);
    }

    function globalizeLiquidity(
        uint256 listingId,
        address token0,
        address baseToken,
        address user,
        uint256 amount,
        bool isDeposit
    ) external {
        require(token0 != address(0) && baseToken != address(0), "Invalid tokens");
        require(user != address(0), "Invalid user");
        require(listingId < listingCount, "Invalid listing ID");
        address listingAddress = getListing[token0][baseToken];
        require(listingAddress != address(0), "Listing not found");
        require(IOMFListing(listingAddress).liquidityAddress() == msg.sender, "Not liquidity contract");

        _updateGlobalLiquidity(listingId, token0, baseToken, user, amount, isDeposit);
    }

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
    ) external {
        require(token0 != address(0) && baseToken != address(0), "Invalid tokens");
        require(maker != address(0), "Invalid maker");
        require(listingId < listingCount, "Invalid listing ID");
        require(getListing[token0][baseToken] == msg.sender, "Not listing contract");

        GlobalOrder storage order = globalOrders[token0][baseToken][orderId];
        if (order.maker == address(0) && status != 0) { // New order
            order.orderId = orderId;
            order.isBuy = isBuy;
            order.maker = maker;
            order.recipient = recipient;
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
            pairOrders[token0][baseToken].push(orderId);
            userOrders[maker].push(orderId);
        } else { // Update existing order
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
        }

        historicalOrderStatus[token0][baseToken][orderId][block.timestamp] = status;
        if (amount > 0) {
            userTradingSummaries[maker][token0][baseToken] += amount;
        }

        emit GlobalOrderChanged(listingId, token0, baseToken, orderId, isBuy, maker, amount, status);
    }

    function _updateGlobalLiquidity(
        uint256 listingId,
        address token0,
        address baseToken,
        address user,
        uint256 amount,
        bool isDeposit
    ) internal {
        if (isDeposit) {
            globalLiquidity[token0][baseToken][user] += amount;
            totalLiquidityPerPair[token0][baseToken] += amount;
            userTotalLiquidity[user] += amount;
            listingLiquidity[listingId][user] += amount;
        } else {
            require(globalLiquidity[token0][baseToken][user] >= amount, "Insufficient user liquidity");
            require(totalLiquidityPerPair[token0][baseToken] >= amount, "Insufficient pair liquidity");
            require(userTotalLiquidity[user] >= amount, "Insufficient total liquidity");
            require(listingLiquidity[listingId][user] >= amount, "Insufficient listing liquidity");
            globalLiquidity[token0][baseToken][user] -= amount;
            totalLiquidityPerPair[token0][baseToken] -= amount;
            userTotalLiquidity[user] -= amount;
            listingLiquidity[listingId][user] -= amount;
        }

        historicalLiquidityPerPair[token0][baseToken][block.timestamp] = totalLiquidityPerPair[token0][baseToken];
        historicalLiquidityPerUser[token0][baseToken][user][block.timestamp] = globalLiquidity[token0][baseToken][user];

        emit GlobalLiquidityChanged(listingId, token0, baseToken, user, amount, isDeposit);
    }

    // Warning: getPairLiquidityTrend and getUserLiquidityTrend may consume high gas for large time ranges or many tokens.
    function getPairLiquidityTrend(
        address token0,
        bool focusOnToken0,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || token0 == address(0)) {
            return (new uint256[](0), new uint256[](0));
        }

        TrendData[] memory temp = new TrendData[](endTime - startTime + 1);
        uint256 count = 0;

        if (focusOnToken0) {
            if (getListing[token0][baseToken] != address(0)) {
                for (uint256 t = startTime; t <= endTime; t++) {
                    uint256 amount = historicalLiquidityPerPair[token0][baseToken][t];
                    if (amount > 0) {
                        temp[count] = TrendData(address(0), t, amount);
                        count++;
                    }
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length; i++) {
                address listedToken = allListedTokens[i];
                if (getListing[listedToken][token0] != address(0)) {
                    for (uint256 t = startTime; t <= endTime; t++) {
                        uint256 amount = historicalLiquidityPerPair[listedToken][token0][t];
                        if (amount > 0) {
                            temp[count] = TrendData(address(0), t, amount);
                            count++;
                        }
                    }
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

    // Warning: getPairLiquidityTrend and getUserLiquidityTrend may consume high gas for large time ranges or many tokens.
    function getUserLiquidityTrend(
        address user,
        bool focusOnToken0,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || user == address(0)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }

        TrendData[] memory temp = new TrendData[]((endTime - startTime + 1) * allListedTokens.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address token0 = allListedTokens[i];
            address pairToken = focusOnToken0 ? baseToken : baseToken;
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerUser[token0][pairToken][user][t];
                if (amount > 0) {
                    temp[count] = TrendData(focusOnToken0 ? token0 : pairToken, t, amount);
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

    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external
        view
        returns (address[] memory token0s, address[] memory baseTokens, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address token0 = allListedTokens[i];
            uint256 amount = globalLiquidity[token0][baseToken][user];
            if (amount > 0) {
                temp[count] = TrendData(token0, 0, amount);
                count++;
            }
        }

        token0s = new address[](count);
        baseTokens = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            token0s[i] = temp[i].token;
            baseTokens[i] = baseToken;
            amounts[i] = temp[i].amount;
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

    function getUserLiquidityShare(address user, address token0, address baseToken)
        external
        view
        returns (uint256 share, uint256 total)
    {
        total = totalLiquidityPerPair[token0][baseToken];
        uint256 userAmount = globalLiquidity[token0][baseToken][user];
        share = total > 0 ? (userAmount * 1e18) / total : 0;
    }

    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnToken0, uint256 maxIterations)
        external
        view
        returns (address[] memory token0s, address[] memory baseTokens, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        if (focusOnToken0) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address token0 = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[token0][baseToken];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(token0, 0, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address token0 = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[token0][baseToken];
                if (amount >= minLiquidity && baseToken == baseToken) {
                    temp[count] = TrendData(token0, 0, amount);
                    count++;
                }
            }
        }

        token0s = new address[](count);
        baseTokens = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            token0s[i] = temp[i].token;
            baseTokens[i] = baseToken;
            amounts[i] = temp[i].amount;
        }
    }

    function getOrderActivityByPair(
        address token0,
        address baseToken,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory orderIds, OrderData[] memory orders) {
        if (endTime < startTime || token0 == address(0) || baseToken == address(0)) {
            return (new uint256[](0), new OrderData[](0));
        }

        uint256[] memory pairOrderIds = pairOrders[token0][baseToken];
        OrderData[] memory temp = new OrderData[](pairOrderIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < pairOrderIds.length; i++) {
            GlobalOrder memory order = globalOrders[token0][baseToken][pairOrderIds[i]];
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
        returns (address[] memory token0s, address[] memory baseTokens, uint256[] memory volumes)
    {
        uint256 maxPairs = allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address token0 = allListedTokens[i];
            uint256 volume = userTradingSummaries[user][token0][baseToken];
            if (volume > 0) {
                temp[count] = TrendData(token0, 0, volume);
                count++;
            }
        }

        token0s = new address[](count);
        baseTokens = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            token0s[i] = temp[i].token;
            baseTokens[i] = baseToken;
            volumes[i] = temp[i].amount;
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
            address token0;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[allListedTokens[j]][baseToken] == trader) {
                    token0 = allListedTokens[j];
                    break;
                }
            }
            if (token0 != address(0)) {
                uint256 volume = userTradingSummaries[trader][token0][baseToken];
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

    function getAllPairsByOrderVolume(uint256 minVolume, bool focusOnToken0, uint256 maxIterations)
        external
        view
        returns (address[] memory token0s, address[] memory baseTokens, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;

        if (focusOnToken0) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address token0 = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[token0][baseToken];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[token0][baseToken][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(token0, 0, volume);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address token0 = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[token0][baseToken];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[token0][baseToken][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(token0, 0, volume);
                    count++;
                }
            }
        }

        token0s = new address[](count);
        baseTokens = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            token0s[i] = temp[i].token;
            baseTokens[i] = baseToken;
            volumes[i] = temp[i].amount;
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

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }
}