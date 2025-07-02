/* SPDX-License-Identifier: BSD-3-Clause */
pragma solidity ^0.8.2;

// Version: 0.0.3
// Changes:
// - v0.0.3: Replaced proxyRouter with routers array, updated setProxyRouter to addRouter/removeRouter/getRouters, modified _initializeListing and _initializeLiquidity to use routers array, ensuring compatibility with IMFListingTemplate and IMFLiquidityTemplate.
// - v0.0.2: Added liquidityProviders mapping, updated _updateGlobalLiquidity to append users to liquidityProviders on first deposit, updated getTopLiquidityProviders to iterate over liquidityProviders and validate listingId.
// - v0.0.1: Created MFPAgent from SSAgent, removed crossDriver and isolatedDriver, updated _initializeListing and _initializeLiquidity to set only proxyRouter.

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface IMFListingTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
    function getTokens() external view returns (address tokenA, address tokenB);
}

interface IMFLiquidityTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function getListingAddress(uint256) external view returns (address);
}

interface IMFListingLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface IMFLiquidityLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface IMFListing {
    function liquidityAddressView() external view returns (address);
}

contract MFPAgent is Ownable {
    using SafeERC20 for IERC20;

    address[] public routers; // Array of router addresses for operations
    address public listingLogicAddress; // Address of listing logic contract
    address public liquidityLogicAddress; // Address of liquidity logic contract
    address public registryAddress; // Address of registry contract
    uint256 public listingCount; // Total number of listings created

    mapping(address => mapping(address => address)) public getListing; // tokenA => tokenB => listingAddress
    address[] public allListings; // Array of all listing addresses
    address[] public allListedTokens; // Array of all listed tokens
    mapping(address => uint256[]) public queryByAddress; // token => listingId[]
    mapping(uint256 => address[]) public liquidityProviders; // listingId => user[]

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

    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);
    event GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);
    event RouterAdded(address indexed router); // Emitted when a router is added
    event RouterRemoved(address indexed router); // Emitted when a router is removed

    // Checks if a token exists in allListedTokens
    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (allListedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    // Checks if a user exists in liquidityProviders for a listing
    function userExistsInProviders(uint256 listingId, address user) internal view returns (bool) {
        address[] memory providers = liquidityProviders[listingId];
        for (uint256 i = 0; i < providers.length; i++) {
            if (providers[i] == user) {
                return true;
            }
        }
        return false;
    }

    // Checks if a router exists in the routers array
    function routerExists(address router) internal view returns (bool) {
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                return true;
            }
        }
        return false;
    }

    // Deploys listing and liquidity contracts with unique salts
    function _deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingId));
        listingAddress = IMFListingLogic(listingLogicAddress).deploy(listingSalt);
        liquidityAddress = IMFLiquidityLogic(liquidityLogicAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    // Initializes listing contract with router array
    function _initializeListing(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        IMFListingTemplate(listingAddress).setRouters(routers); // Sets router array
        IMFListingTemplate(listingAddress).setListingId(listingId); // Sets listing ID
        IMFListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress); // Links liquidity contract
        IMFListingTemplate(listingAddress).setTokens(tokenA, tokenB); // Sets token pair
        IMFListingTemplate(listingAddress).setAgent(address(this)); // Sets agent as this contract
        IMFListingTemplate(listingAddress).setRegistry(registryAddress); // Sets registry address
    }

    // Initializes liquidity contract with router array
    function _initializeLiquidity(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        IMFLiquidityTemplate(liquidityAddress).setRouters(routers); // Sets router array
        IMFLiquidityTemplate(liquidityAddress).setListingId(listingId); // Sets listing ID
        IMFLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress); // Links listing contract
        IMFLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB); // Sets token pair
        IMFLiquidityTemplate(liquidityAddress).setAgent(address(this)); // Sets agent as this contract
    }

    // Updates state with new listing information
    function _updateState(address tokenA, address tokenB, address listingAddress, uint256 listingId) internal {
        getListing[tokenA][tokenB] = listingAddress; // Maps token pair to listing
        allListings.push(listingAddress); // Adds to all listings array
        if (!tokenExists(tokenA)) allListedTokens.push(tokenA); // Adds tokenA if not listed
        if (!tokenExists(tokenB)) allListedTokens.push(tokenB); // Adds tokenB if not listed
        queryByAddress[tokenA].push(listingId); // Tracks listing ID for tokenA
        queryByAddress[tokenB].push(listingId); // Tracks listing ID for tokenB
    }

    // Adds a router to the routers array
    function addRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(!routerExists(router), "Router already exists");
        routers.push(router); // Appends new router to array
        emit RouterAdded(router);
    }

    // Removes a router from the routers array
    function removeRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                routers[i] = routers[routers.length - 1]; // Move last router to current position
                routers.pop(); // Remove last element
                emit RouterRemoved(router);
                return;
            }
        }
        revert("Router not found");
    }

    // Returns the current list of routers
    function getRouters() external view returns (address[] memory) {
        return routers; // Returns the entire routers array
    }

    // Sets listing logic address
    function setListingLogic(address _listingLogic) external onlyOwner {
        require(_listingLogic != address(0), "Invalid logic address");
        listingLogicAddress = _listingLogic; // Updates listing logic address
    }

    // Sets liquidity logic address
    function setLiquidityLogic(address _liquidityLogic) external onlyOwner {
        require(_liquidityLogic != address(0), "Invalid logic address");
        liquidityLogicAddress = _liquidityLogic; // Updates liquidity logic address
    }

    // Sets registry address
    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress; // Updates registry address
    }

    // Lists a token pair
    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Lists a native-token pair
    function listNative(address token, bool isA) external returns (address listingAddress, address liquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Validates listing and returns details
    function isValidListing(address listingAddress) public view returns (bool isValid, ListingDetails memory details) {
        isValid = false;
        for (uint256 i = 0; i < allListings.length; i++) {
            if (allListings[i] == listingAddress) {
                isValid = true;
                (address tokenA, address tokenB) = IMFListingTemplate(listingAddress).getTokens();
                address liquidityAddress = IMFListing(listingAddress).liquidityAddressView();
                details = ListingDetails({
                    listingAddress: listingAddress,
                    liquidityAddress: liquidityAddress,
                    tokenA: tokenA,
                    tokenB: tokenB,
                    listingId: i
                });
                break;
            }
        }
    }

    // Updates global liquidity for a listing
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

        // Retrieve listing address from liquidity contract
        address listingAddress;
        try IMFLiquidityTemplate(msg.sender).getListingAddress(listingId) returns (address _listingAddress) {
            listingAddress = _listingAddress;
        } catch {
            revert("Failed to retrieve listing address");
        }
        require(listingAddress != address(0), "Invalid listing address");

        // Verify listing validity and details
        (bool isValid, ListingDetails memory details) = isValidListing(listingAddress);
        require(isValid, "Invalid listing");
        require(details.listingId == listingId, "Listing ID mismatch");
        require(details.tokenA == tokenA && details.tokenB == tokenB, "Token mismatch");

        // Ensure caller is the associated liquidity contract
        require(details.liquidityAddress == msg.sender, "Caller is not liquidity contract");

        _updateGlobalLiquidity(listingId, tokenA, tokenB, user, amount, isDeposit);
    }

    // Internal function to update liquidity mappings
    function _updateGlobalLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) internal {
        if (isDeposit) {
            // Only add user to liquidityProviders if they had no prior liquidity
            if (listingLiquidity[listingId][user] == 0 && !userExistsInProviders(listingId, user)) {
                liquidityProviders[listingId].push(user);
            }
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

    // Updates global order data
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
        if (order.maker == address(0) && status != 0) {
            order.orderId = orderId;
            order.isBuy = isBuy;
            order.maker = maker;
            order.recipient = recipient;
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
            pairOrders[tokenA][tokenB].push(orderId);
            userOrders[maker].push(orderId);
        } else {
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

    // Retrieves liquidity trend for a pair
    function getPairLiquidityTrend(
        address tokenA,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || tokenA == address(0)) {
            return (new uint256[](0), new uint256[](0));
        }
        TrendData[] memory temp = new TrendData[](endTime - startTime + 1);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerPair[tokenA][allListedTokens[0]][t];
                if (amount > 0) {
                    temp[count] = TrendData(address(0), t, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length; i++) {
                address tokenB = allListedTokens[i];
                for (uint256 t = startTime; t <= endTime; t++) {
                    uint256 amount = historicalLiquidityPerPair[tokenB][tokenA][t];
                    if (amount > 0) {
                        temp[count] = TrendData(address(0), t, amount);
                        count++;
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

    // Retrieves user liquidity trend
    function getUserLiquidityTrend(
        address user,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts) {
        if (endTime < startTime || user == address(0)) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }
        TrendData[] memory temp = new TrendData[]((endTime - startTime + 1) * allListedTokens.length);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            address pairToken = focusOnTokenA ? allListedTokens[0] : tokenA;
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = historicalLiquidityPerUser[tokenA][pairToken][user][t];
                if (amount > 0) {
                    temp[count] = TrendData(focusOnTokenA ? tokenA : pairToken, t, amount);
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

    // Retrieves user liquidity across pairs
    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
            address tokenA = allListedTokens[i];
            uint256 amount = globalLiquidity[tokenA][allListedTokens[0]][user];
            if (amount > 0) {
                temp[count] = TrendData(tokenA, 0, amount);
                count++;
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            amounts[i] = temp[i].amount;
        }
    }

    // Retrieves top liquidity providers for a listing
    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory users, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        require(listingId < listingCount, "Invalid listing ID");
        uint256 maxLimit = maxIterations < liquidityProviders[listingId].length ? maxIterations : liquidityProviders[listingId].length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;
        for (uint256 i = 0; i < liquidityProviders[listingId].length && count < maxLimit; i++) {
            address user = liquidityProviders[listingId][i];
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

    // Retrieves user liquidity share for a pair
    function getUserLiquidityShare(address user, address tokenA, address tokenB)
        external view returns (uint256 share, uint256 total)
    {
        total = totalLiquidityPerPair[tokenA][tokenB];
        uint256 userAmount = globalLiquidity[tokenA][tokenB][user];
        share = total > 0 ? (userAmount * 1e18) / total : 0;
    }

    // Retrieves all pairs by liquidity
    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[tokenA][allListedTokens[0]];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 amount = totalLiquidityPerPair[tokenA][allListedTokens[0]];
                if (amount >= minLiquidity) {
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
            tokenBs[i] = allListedTokens[0];
            amounts[i] = temp[i].amount;
        }
    }

    // Retrieves order activity for a pair
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

    // Retrieves user trading profile
    function getUserTradingProfile(address user)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        uint256 maxPairs = allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            address tokenA = allListedTokens[i];
            uint256 volume = userTradingSummaries[user][tokenA][allListedTokens[0]];
            if (volume > 0) {
                temp[count] = TrendData(tokenA, 0, volume);
                count++;
            }
        }
        tokenAs = new address[](count);
        tokenBs = new address[](count);
        volumes = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            tokenAs[i] = temp[i].token;
            tokenBs[i] = allListedTokens[0];
            volumes[i] = temp[i].amount;
        }
    }

    // Retrieves top traders by volume
    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory traders, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < allListings.length ? maxIterations : allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit);
        uint256 count = 0;
        for (uint256 i = 0; i < allListings.length && count < maxLimit; i++) {
            address trader = allListings[i];
            address tokenA;
            for (uint256 j = 0; j < allListedTokens.length; j++) {
                if (getListing[allListedTokens[j]][allListedTokens[0]] == trader) {
                    tokenA = allListedTokens[j];
                    break;
                }
            }
            if (tokenA != address(0)) {
                uint256 volume = userTradingSummaries[trader][tokenA][allListedTokens[0]];
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

    // Retrieves all pairs by order volume
    function getAllPairsByOrderVolume(uint256 minVolume, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxPairs = maxIterations < allListedTokens.length ? maxIterations : allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs);
        uint256 count = 0;
        if (focusOnTokenA) {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][allListedTokens[0]];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[tokenA][allListedTokens[0]][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < allListedTokens.length && count < maxPairs; i++) {
                address tokenA = allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = pairOrders[tokenA][allListedTokens[0]];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += globalOrders[tokenA][allListedTokens[0]][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
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
            tokenBs[i] = allListedTokens[0];
            volumes[i] = temp[i].amount;
        }
    }

    // Sorts trend data in descending order
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

    // Queries listing by index
    function queryByIndex(uint256 index) external view returns (address) {
        require(index < allListings.length, "Invalid index");
        return allListings[index];
    }

    // Queries listing indices by token address with pagination
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

    // Returns length of listing indices for a token
    function queryByAddressLength(address target) external view returns (uint256) {
        return queryByAddress[target].length;
    }

    // Returns total number of listings
    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }

    // Returns total number of listed tokens
    function allListedTokensLength() external view returns (uint256) {
        return allListedTokens.length;
    }
}