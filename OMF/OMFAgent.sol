/*
SPDX-License-Identifier: BSD-3-Clause
*/

// Specifying Solidity version for compatibility
pragma solidity ^0.8.2;

// Version: 0.0.7
// Changes:
// - v0.0.7: Replaced _proxyRouter with routers array, updated setProxyRouter to addRouter/removeRouter/getRouters, modified _initializeListing and _initializeLiquidity to use routers array, ensuring compatibility with IOMFListingTemplate and IOMFLiquidityTemplate.
// - v0.0.6: Updated IOMFListing and IOMFLiquidityTemplate interfaces to align with OMFInterfaces.sol (v0.0.2) and OMFLiquidityTemplate.sol (v0.0.13). Replaced IOMFListing with full interface including volumeBalances, volumeBalanceView, getPrice, and getRegistryAddress. Updated IOMFLiquidityTemplate to include all external and view functions from OMFInterfaces.sol.
// - v0.0.5: Fixed DeclarationError in setLiquidityLogic function at line 264 by replacing incorrect 'listingLogic' with 'liquidityLogic' in require statement.
// - v0.0.4: Fixed getTopLiquidityProviders function to correctly iterate over _listingLiquidity mapping for a given listingId to retrieve users and their liquidity amounts, replacing incorrect use of _allListings as user addresses.
// - v0.0.3: Fixed ParserError at line 369 in globalizeLiquidity function by replacing invalid 'address Missinfg(61: Invalid user address)address(0)' with 'address(0)' for proper user address validation.
// - v0.0.2: Integrated MFPAgent functionality with OMFAgent's oracle features. Added baseToken, oracle parameters, and 1% supply check. Replaced listNative with ERC-20-only listings. Adopted validateListing from OMFAgent. Preserved MFPAgent's query functions with baseToken adjustments.
// - v0.0.1: Initial creation based on MFPAgent, adapted from SSAgent.

// Importing required contracts
import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

// Defining interface for listing template with multiple routers and oracle details
interface IOMFListingTemplate {
    function setRouters(address[] memory _routers) external; // Sets array of routers
    function setListingId(uint256 _listingId) external; // Sets listing ID
    function setLiquidityAddress(address _liquidityAddress) external; // Links liquidity contract
    function setTokens(address _tokenA, address _tokenB) external; // Sets token pair
    function setOracleDetails(address oracle, uint8 decimals, bytes4 viewFunction) external; // Sets oracle parameters
    function setAgent(address _agent) external; // Sets agent address
    function setRegistry(address _registryAddress) external; // Sets registry address
    function getTokens() external view returns (address tokenA, address tokenB); // Retrieves token pair
}

// Defining interface for liquidity template
interface IOMFLiquidityTemplate {
    // Structs
    struct LiquidityDetails {
        uint256 xLiquid; // Token-A liquidity
        uint256 yLiquid; // Token-B liquidity
        uint256 xFees; // Token-A fees
        uint256 yFees; // Token-B fees
    }

    struct Slot {
        address depositor; // Slot owner
        address recipient; // Not used
        uint256 allocation; // Allocated liquidity
        uint256 dVolume; // Volume at deposit
        uint256 timestamp; // Deposit timestamp
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index; // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value; // Amount or allocation (normalized)
        address addr; // Depositor
        address recipient; // Not used
    }

    struct PreparedWithdrawal {
        uint256 amountA; // Token-A withdrawal amount
        uint256 amountB; // Token-B withdrawal amount
    }

    // External functions
    function setRouters(address[] memory routers) external; // Sets router addresses
    function setListingId(uint256 listingId) external; // Sets listing ID
    function setListingAddress(address listingAddress) external; // Sets listing contract address
    function setTokens(address tokenA, address tokenB) external; // Sets token addresses
    function setAgent(address agent) external; // Sets agent address
    function update(address caller, UpdateType[] memory updates) external; // Updates liquidity or fees
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external; // Changes slot depositor
    function deposit(address caller, address token, uint256 amount) external; // Deposits tokens
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory); // Prepares tokenA withdrawal
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external; // Executes tokenA withdrawal
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory); // Prepares tokenB withdrawal
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external; // Executes tokenB withdrawal
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external; // Claims fees
    function transact(address caller, address token, uint256 amount, address recipient) external; // Handles token transfers
    function addFees(address caller, bool isX, uint256 fee) external; // Adds fees
    function updateLiquidity(address caller, bool isX, uint256 amount) external; // Updates liquidity balances

    // View functions for state variables and mappings
    function routersView(address router) external view returns (bool); // Returns router status
    function routersSetView() external view returns (bool); // Returns routersSet flag
    function listingAddressView() external view returns (address); // Returns listing address
    function tokenAView() external view returns (address); // Returns tokenA address
    function tokenBView() external view returns (address); // Returns tokenB address
    function decimalAView() external view returns (uint8); // Returns tokenA decimals
    function decimalBView() external view returns (uint8); // Returns tokenB decimals
    function listingIdView() external view returns (uint256); // Returns listing ID
    function agentView() external view returns (address); // Returns agent address
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees); // Returns liquidity details
    function activeXLiquiditySlotsView() external view returns (uint256[] memory); // Returns active tokenA slots
    function activeYLiquiditySlotsView() external view returns (uint256[] memory); // Returns active tokenB slots
    function userIndexView(address user) external view returns (uint256[] memory); // Returns user slot indices
    function getXSlotView(uint256 index) external view returns (Slot memory); // Returns tokenA slot
    function getYSlotView(uint256 index) external view returns (Slot memory); // Returns tokenB slot
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount); // Returns liquidity amounts
    function getListingAddress(uint256 listingId) external view returns (address); // Returns listing address
}

// Defining interface for listing logic
interface IOMFListingLogic {
    function deploy(bytes32 salt) external returns (address); // Deploys listing contract
}

// Defining interface for liquidity logic
interface IOMFLiquidityLogic {
    function deploy(bytes32 salt) external returns (address); // Deploys liquidity contract
}

// Defining interface for listing contract
interface IOMFListing {
    function liquidityAddressView(uint256 listingId) external view returns (address); // Retrieves liquidity address
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance); // Returns volume balances
    function volumeBalanceView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume); // Returns volume balances
    function getPrice() external view returns (uint256); // Returns oracle price
    function getRegistryAddress() external view returns (address); // Returns registry address
}

contract OMFAgent is Ownable {
    using SafeERC20 for IERC20;

    // State variables (hidden, accessed via view functions)
    address[] private routers; // Array of router addresses for operations
    address private _listingLogicAddress; // Address of listing logic contract
    address private _liquidityLogicAddress; // Address of liquidity logic contract
    address private _baseToken; // Reference token (Token-1) for all pairs
    address private _registryAddress; // Address of registry contract
    uint256 private _listingCount; // Total number of listings created

    // Mappings for listing and liquidity tracking
    mapping(address => mapping(address => address)) private _getListing; // tokenA => baseToken => listingAddress
    address[] private _allListings; // Array of all listing addresses
    address[] private _allListedTokens; // Array of listed tokenAs
    mapping(address => uint256[]) private _queryByAddress; // tokenA => listingId[]

    // Liquidity tracking mappings
    mapping(address => mapping(address => mapping(address => uint256))) private _globalLiquidity; // tokenA => baseToken => user => amount
    mapping(address => mapping(address => uint256)) private _totalLiquidityPerPair; // tokenA => baseToken => amount
    mapping(address => uint256) private _userTotalLiquidity; // user => total liquidity
    mapping(uint256 => mapping(address => uint256)) private _listingLiquidity; // listingId => user => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _historicalLiquidityPerPair; // tokenA => baseToken => timestamp => amount
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) private _historicalLiquidityPerUser; // tokenA => baseToken => user => timestamp => amount

    // Struct for global order data
    struct GlobalOrder {
        uint256 orderId; // Unique order identifier
        bool isBuy; // True if buy order
        address maker; // Order creator
        address recipient; // Order recipient
        uint256 amount; // Order amount
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp; // Order creation/update time
    }

    // Order tracking mappings
    mapping(address => mapping(address => mapping(uint256 => GlobalOrder))) private _globalOrders; // tokenA => baseToken => orderId => GlobalOrder
    mapping(address => mapping(address => uint256[])) private _pairOrders; // tokenA => baseToken => orderId[]
    mapping(address => uint256[]) private _userOrders; // user => orderId[]
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint8)))) private _historicalOrderStatus; // tokenA => baseToken => orderId => timestamp => status
    mapping(address => mapping(address => mapping(address => uint256))) private _userTradingSummaries; // user => tokenA => baseToken => volume

    // Structs for listing preparation and initialization
    struct PrepData {
        bytes32 listingSalt; // Salt for listing deployment
        bytes32 liquiditySalt; // Salt for liquidity deployment
        address tokenA; // Token-0 (paired with baseToken)
        address oracleAddress; // Oracle contract address
        uint8 oracleDecimals; // Oracle price decimals
        bytes4 oracleViewFunction; // Oracle view function selector
    }

    struct InitData {
        address listingAddress; // Deployed listing address
        address liquidityAddress; // Deployed liquidity address
        address tokenA; // Token-0
        address tokenB; // BaseToken (Token-1)
        uint256 listingId; // Listing identifier
        address oracleAddress; // Oracle contract address
        uint8 oracleDecimals; // Oracle price decimals
        bytes4 oracleViewFunction; // Oracle view function selector
    }

    struct TrendData {
        address token; // Token address
        uint256 timestamp; // Timestamp of data point
        uint256 amount; // Amount (liquidity or volume)
    }

    struct OrderData {
        uint256 orderId; // Order identifier
        bool isBuy; // True if buy order
        address maker; // Order creator
        address recipient; // Order recipient
        uint256 amount; // Order amount
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp; // Order creation/update time
    }

    // Events for tracking actions
    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);
    event GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);
    event RouterAdded(address indexed router); // Emitted when a router is added
    event RouterRemoved(address indexed router); // Emitted when a router is removed

    // Constructor (empty, addresses set via setters)
    constructor() {}

    // Checks if a token exists in allListedTokens
    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < _allListedTokens.length; i++) {
            if (_allListedTokens[i] == token) {
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

    // View function for routers
    function getRouters() external view returns (address[] memory) {
        return routers; // Returns the entire routers array
    }

    // View function for listingLogicAddress
    function listingLogicAddressView() external view returns (address) {
        return _listingLogicAddress;
    }

    // View function for liquidityLogicAddress
    function liquidityLogicAddressView() external view returns (address) {
        return _liquidityLogicAddress;
    }

    // View function for baseToken
    function baseTokenView() external view returns (address) {
        return _baseToken;
    }

    // View function for registryAddress
    function registryAddressView() external view returns (address) {
        return _registryAddress;
    }

    // View function for listingCount
    function listingCountView() external view returns (uint256) {
        return _listingCount;
    }

    // View function for getListing mapping
    function getListingView(address tokenA, address tokenB) external view returns (address) {
        return _getListing[tokenA][tokenB];
    }

    // View function for allListings length
    function allListingsLengthView() external view returns (uint256) {
        return _allListings.length;
    }

    // View function for allListedTokens length
    function allListedTokensLengthView() external view returns (uint256) {
        return _allListedTokens.length;
    }

    // Checks caller balance for 1% of token supply
    function checkCallerBalance(address tokenA, uint256 totalSupply) internal view returns (bool) {
        uint256 decimals = IERC20(tokenA).decimals(); // Retrieves token decimals
        uint256 requiredBalance = totalSupply / 100; // 1% of total supply
        if (decimals != 18) {
            requiredBalance = (totalSupply * 1e18) / (100 * 10 ** decimals); // Adjusts for non-18 decimal tokens
        }
        return IERC20(tokenA).balanceOf(msg.sender) >= requiredBalance; // Verifies caller balance
    }

    // Deploys listing and liquidity contracts with unique salts
    function _deployPair(address tokenA, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, _baseToken, listingId)); // Unique salt for listing
        bytes32 liquiditySalt = keccak256(abi.encodePacked(_baseToken, tokenA, listingId)); // Unique salt for liquidity
        listingAddress = IOMFListingLogic(_listingLogicAddress).deploy(listingSalt); // Deploys listing contract
        liquidityAddress = IOMFLiquidityLogic(_liquidityLogicAddress).deploy(liquiditySalt); // Deploys liquidity contract
        return (listingAddress, liquidityAddress);
    }

    // Initializes listing contract with router array and oracle details
    function _initializeListing(InitData memory init) internal {
        IOMFListingTemplate(init.listingAddress).setRouters(routers); // Sets routers array
        IOMFListingTemplate(init.listingAddress).setListingId(init.listingId); // Sets listing ID
        IOMFListingTemplate(init.listingAddress).setLiquidityAddress(init.liquidityAddress); // Links liquidity contract
        IOMFListingTemplate(init.listingAddress).setTokens(init.tokenA, init.tokenB); // Sets token pair
        IOMFListingTemplate(init.listingAddress).setOracleDetails(init.oracleAddress, init.oracleDecimals, init.oracleViewFunction); // Sets oracle parameters
        IOMFListingTemplate(init.listingAddress).setAgent(address(this)); // Sets agent as this contract
        IOMFListingTemplate(init.listingAddress).setRegistry(_registryAddress); // Sets registry address
    }

    // Initializes liquidity contract with router array
    function _initializeLiquidity(InitData memory init) internal {
        IOMFLiquidityTemplate(init.liquidityAddress).setRouters(routers); // Sets routers array
        IOMFLiquidityTemplate(init.liquidityAddress).setListingId(init.listingId); // Sets listing ID
        IOMFLiquidityTemplate(init.liquidityAddress).setListingAddress(init.listingAddress); // Links listing contract
        IOMFLiquidityTemplate(init.liquidityAddress).setTokens(init.tokenA, init.tokenB); // Sets token pair
        IOMFLiquidityTemplate(init.liquidityAddress).setAgent(address(this)); // Sets agent as this contract
    }

    // Updates state with new listing information
    function _updateState(address tokenA, address listingAddress, uint256 listingId) internal {
        _getListing[tokenA][_baseToken] = listingAddress; // Maps tokenA to baseToken
        _allListings.push(listingAddress); // Adds to all listings
        if (!tokenExists(tokenA)) _allListedTokens.push(tokenA); // Adds tokenA if not listed
        _queryByAddress[tokenA].push(listingId); // Tracks listing ID for tokenA
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

    // Sets listing logic address
    function setListingLogic(address listingLogic) external onlyOwner {
        require(listingLogic != address(0), "Invalid logic address");
        _listingLogicAddress = listingLogic; // Updates listing logic
    }

    // Sets liquidity logic address
    function setLiquidityLogic(address liquidityLogic) external onlyOwner {
        require(liquidityLogic != address(0), "Invalid logic address");
        _liquidityLogicAddress = liquidityLogic; // Updates liquidity logic
    }

    // Sets baseToken address
    function setBaseToken(address baseToken) external onlyOwner {
        require(baseToken != address(0), "Base token cannot be NATIVE");
        _baseToken = baseToken; // Updates base token (Token-1)
    }

    // Sets registry address
    function setRegistry(address registryAddress) external onlyOwner {
        require(registryAddress != address(0), "Invalid registry address");
        _registryAddress = registryAddress; // Updates registry address
    }

    // Prepares listing with validation and salt generation
    function prepListing(
        address tokenA,
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) internal returns (address) {
        require(_baseToken != address(0), "Base token not set");
        require(tokenA != _baseToken, "Identical tokens");
        require(tokenA != address(0), "TokenA cannot be NATIVE");
        require(_getListing[tokenA][_baseToken] == address(0), "Pair already listed");
        require(routers.length > 0, "No routers set");
        require(_listingLogicAddress != address(0), "Listing logic not set");
        require(_liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(_registryAddress != address(0), "Registry not set");
        require(oracleAddress != address(0), "Invalid oracle address");

        uint256 supply = IERC20(tokenA).totalSupply(); // Retrieves tokenA supply
        require(checkCallerBalance(tokenA, supply), "Must own at least 1% of token supply");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, _baseToken, _listingCount)); // Generates listing salt
        bytes32 liquiditySalt = keccak256(abi.encodePacked(_baseToken, tokenA, _listingCount)); // Generates liquidity salt

        PrepData memory prep = PrepData(listingSalt, liquiditySalt, tokenA, oracleAddress, oracleDecimals, oracleViewFunction);
        return executeListing(prep);
    }

    // Executes listing deployment and initialization
    function executeListing(PrepData memory prep) internal returns (address) {
        (address listingAddress, address liquidityAddress) = _deployPair(prep.tokenA, _listingCount); // Deploys contracts
        InitData memory init = InitData(
            listingAddress,
            liquidityAddress,
            prep.tokenA,
            _baseToken,
            _listingCount,
            prep.oracleAddress,
            prep.oracleDecimals,
            prep.oracleViewFunction
        ); // Prepares initialization data
        _initializeListing(init); // Initializes listing contract
        _initializeLiquidity(init); // Initializes liquidity contract
        _updateState(prep.tokenA, listingAddress, _listingCount); // Updates state

        emit ListingCreated(prep.tokenA, _baseToken, listingAddress, liquidityAddress, _listingCount); // Emits event
        _listingCount++; // Increments listing count
        return listingAddress;
    }

    // Lists a token pair with oracle details
    function listToken(
        address tokenA,
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) external returns (address listingAddress, address liquidityAddress) {
        address deployedListing = prepListing(tokenA, oracleAddress, oracleDecimals, oracleViewFunction); // Prepares and deploys listing
        listingAddress = deployedListing;
        liquidityAddress = IOMFListing(deployedListing).liquidityAddressView(_listingCount - 1); // Retrieves liquidity address
        return (listingAddress, liquidityAddress);
    }

    // Validates listing and returns details
    function validateListing(address listingAddress) external view returns (bool, address, address, address) {
        if (listingAddress == address(0)) {
            return (false, address(0), address(0), address(0)); // Invalid listing
        }
        address tokenA;
        for (uint256 i = 0; i < _allListedTokens.length; i++) {
            if (_getListing[_allListedTokens[i]][_baseToken] == listingAddress) {
                tokenA = _allListedTokens[i];
                break;
            }
        }
        if (tokenA == address(0) || _baseToken == address(0)) {
            return (false, address(0), address(0), address(0)); // Tokens not found
        }
        return (true, listingAddress, tokenA, _baseToken); // Valid listing
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
        require(tokenB == _baseToken, "TokenB must be baseToken");
        require(user != address(0), "Invalid user");
        require(listingId < _listingCount, "Invalid listing ID");

        address listingAddress = _getListing[tokenA][tokenB]; // Retrieves listing address
        require(listingAddress != address(0), "Listing not found");
        require(IOMFListing(listingAddress).liquidityAddressView(listingId) == msg.sender, "Caller is not liquidity contract");

        _updateGlobalLiquidity(listingId, tokenA, tokenB, user, amount, isDeposit); // Updates liquidity
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
        require(tokenB == _baseToken, "TokenB must be baseToken");
        require(maker != address(0), "Invalid maker");
        require(listingId < _listingCount, "Invalid listing ID");
        require(_getListing[tokenA][tokenB] == msg.sender, "Caller is not listing contract");

        GlobalOrder storage order = _globalOrders[tokenA][tokenB][orderId]; // Retrieves order
        if (order.maker == address(0) && status != 0) {
            order.orderId = orderId;
            order.isBuy = isBuy;
            order.maker = maker;
            order.recipient = recipient;
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
            _pairOrders[tokenA][tokenB].push(orderId); // Tracks order for pair
            _userOrders[maker].push(orderId); // Tracks order for user
        } else {
            order.amount = amount;
            order.status = status;
            order.timestamp = block.timestamp;
        }
        _historicalOrderStatus[tokenA][tokenB][orderId][block.timestamp] = status; // Updates historical status
        if (amount > 0) {
            _userTradingSummaries[maker][tokenA][tokenB] += amount; // Updates trading volume
        }
        emit GlobalOrderChanged(listingId, tokenA, tokenB, orderId, isBuy, maker, amount, status); // Emits event
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
            _globalLiquidity[tokenA][tokenB][user] += amount;
            _totalLiquidityPerPair[tokenA][tokenB] += amount;
            _userTotalLiquidity[user] += amount;
            _listingLiquidity[listingId][user] += amount;
        } else {
            require(_globalLiquidity[tokenA][tokenB][user] >= amount, "Insufficient user liquidity");
            require(_totalLiquidityPerPair[tokenA][tokenB] >= amount, "Insufficient pair liquidity");
            require(_userTotalLiquidity[user] >= amount, "Insufficient total liquidity");
            require(_listingLiquidity[listingId][user] >= amount, "Insufficient listing liquidity");
            _globalLiquidity[tokenA][tokenB][user] -= amount;
            _totalLiquidityPerPair[tokenA][tokenB] -= amount;
            _userTotalLiquidity[user] -= amount;
            _listingLiquidity[listingId][user] -= amount;
        }
        _historicalLiquidityPerPair[tokenA][tokenB][block.timestamp] = _totalLiquidityPerPair[tokenA][tokenB]; // Updates historical pair liquidity
        _historicalLiquidityPerUser[tokenA][tokenB][user][block.timestamp] = _globalLiquidity[tokenA][tokenB][user]; // Updates historical user liquidity
        emit GlobalLiquidityChanged(listingId, tokenA, tokenB, user, amount, isDeposit); // Emits event
    }

    // Retrieves liquidity trend for a pair
    function getPairLiquidityTrend(
        address tokenA,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (uint256[] memory timestamps, uint256[] memory amounts) {
        require(endTime >= startTime && tokenA != address(0), "Invalid parameters");
        require(focusOnTokenA || _baseToken != address(0), "Base token not set");

        TrendData[] memory temp = new TrendData[](endTime - startTime + 1); // Temporary array for data
        uint256 count = 0;

        if (focusOnTokenA) {
            if (_getListing[tokenA][_baseToken] != address(0)) {
                for (uint256 t = startTime; t <= endTime; t++) {
                    uint256 amount = _historicalLiquidityPerPair[tokenA][_baseToken][t];
                    if (amount > 0) {
                        temp[count] = TrendData(address(0), t, amount);
                        count++;
                    }
                }
            }
        } else {
            for (uint256 i = 0; i < _allListedTokens.length; i++) {
                address listedToken = _allListedTokens[i];
                if (_getListing[listedToken][tokenA] != address(0)) {
                    for (uint256 t = startTime; t <= endTime; t++) {
                        uint256 amount = _historicalLiquidityPerPair[listedToken][tokenA][t];
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

    // Retrieves user liquidity trend
    function getUserLiquidityTrend(
        address user,
        bool focusOnTokenA,
        uint256 startTime,
        uint256 endTime
    ) external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts) {
        require(endTime >= startTime && user != address(0), "Invalid parameters");
        require(_baseToken != address(0), "Base token not set");

        TrendData[] memory temp = new TrendData[]((endTime - startTime + 1) * _allListedTokens.length); // Temporary array
        uint256 count = 0;

        for (uint256 i = 0; i < _allListedTokens.length; i++) {
            address tokenA = _allListedTokens[i];
            address pairToken = focusOnTokenA ? _baseToken : _baseToken;
            for (uint256 t = startTime; t <= endTime; t++) {
                uint256 amount = _historicalLiquidityPerUser[tokenA][pairToken][user][t];
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
        require(_baseToken != address(0), "Base token not set");

        uint256 maxPairs = maxIterations < _allListedTokens.length ? maxIterations : _allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs); // Temporary array
        uint256 count = 0;

        for (uint256 i = 0; i < _allListedTokens.length && count < maxPairs; i++) {
            address tokenA = _allListedTokens[i];
            uint256 amount = _globalLiquidity[tokenA][_baseToken][user];
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
            tokenBs[i] = _baseToken;
            amounts[i] = temp[i].amount;
        }
    }

    // Retrieves top liquidity providers for a listing
    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory users, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        require(listingId < _listingCount, "Invalid listing ID");

        // Temporary array to store user addresses and liquidity amounts
        TrendData[] memory temp = new TrendData[](maxIterations);
        uint256 count = 0;

        // Iterate over all listed tokens to find users with liquidity for the listing
        for (uint256 i = 0; i < _allListedTokens.length && count < maxIterations; i++) {
            address tokenA = _allListedTokens[i];
            address listingAddress = _getListing[tokenA][_baseToken];
            if (listingAddress != address(0)) {
                // Check each user in _listingLiquidity for the given listingId
                for (uint256 j = 0; j < _allListings.length && count < maxIterations; j++) {
                    address user = _allListings[j]; // Note: Using _allListings as a proxy for potential users; adjust if user list is available
                    uint256 amount = _listingLiquidity[listingId][user];
                    if (amount > 0) {
                        temp[count] = TrendData(user, 0, amount);
                        count++;
                    }
                }
            }
        }

        // Sort in descending order by amount
        _sortDescending(temp, count);

        // Resize arrays to actual count
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
        require(tokenB == _baseToken, "TokenB must be baseToken");
        total = _totalLiquidityPerPair[tokenA][tokenB]; // Total liquidity for pair
        uint256 userAmount = _globalLiquidity[tokenA][tokenB][user]; // User liquidity for pair
        share = total > 0 ? (userAmount * 1e18) / total : 0; // Calculates share with 18 decimals
    }

    // Retrieves all pairs by liquidity
    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        require(_baseToken != address(0), "Base token not set");

        uint256 maxPairs = maxIterations < _allListedTokens.length ? maxIterations : _allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs); // Temporary array
        uint256 count = 0;

        if (focusOnTokenA) {
            for (uint256 i = 0; i < _allListedTokens.length && count < maxPairs; i++) {
                address tokenA = _allListedTokens[i];
                uint256 amount = _totalLiquidityPerPair[tokenA][_baseToken];
                if (amount >= minLiquidity) {
                    temp[count] = TrendData(tokenA, 0, amount);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < _allListedTokens.length && count < maxPairs; i++) {
                address tokenA = _allListedTokens[i];
                uint256 amount = _totalLiquidityPerPair[tokenA][_baseToken];
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
            tokenBs[i] = _baseToken;
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
        require(endTime >= startTime && tokenA != address(0) && tokenB != address(0), "Invalid parameters");
        require(tokenB == _baseToken, "TokenB must be baseToken");

        uint256[] memory pairOrderIds = _pairOrders[tokenA][tokenB]; // Retrieves order IDs
        OrderData[] memory temp = new OrderData[](pairOrderIds.length); // Temporary array
        uint256 count = 0;

        for (uint256 i = 0; i < pairOrderIds.length; i++) {
            GlobalOrder memory order = _globalOrders[tokenA][tokenB][pairOrderIds[i]];
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
        require(_baseToken != address(0), "Base token not set");
        uint256 maxPairs = _allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs); // Temporary array
        uint256 count = 0;

        for (uint256 i = 0; i < _allListedTokens.length; i++) {
            address tokenA = _allListedTokens[i];
            uint256 volume = _userTradingSummaries[user][tokenA][_baseToken];
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
            tokenBs[i] = _baseToken;
            volumes[i] = temp[i].amount;
        }
    }

    // Retrieves top traders by volume
    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory traders, uint256[] memory volumes)
    {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 maxLimit = maxIterations < _allListings.length ? maxIterations : _allListings.length;
        TrendData[] memory temp = new TrendData[](maxLimit); // Temporary array
        uint256 count = 0;

        for (uint256 i = 0; i < _allListings.length && count < maxLimit; i++) {
            address trader = _allListings[i];
            address tokenA;
            for (uint256 j = 0; j < _allListedTokens.length; j++) {
                if (_getListing[_allListedTokens[j]][_baseToken] == trader) {
                    tokenA = _allListedTokens[j];
                    break;
                }
            }
            if (tokenA != address(0)) {
                uint256 volume = _userTradingSummaries[trader][tokenA][_baseToken];
                if (volume > 0) {
                    temp[count] = TrendData(trader, 0, volume);
                    count++;
                }
            }
        }

        _sortDescending(temp, count); // Sorts in descending order
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
        require(_baseToken != address(0), "Base token not set");

        uint256 maxPairs = maxIterations < _allListedTokens.length ? maxIterations : _allListedTokens.length;
        TrendData[] memory temp = new TrendData[](maxPairs); // Temporary array
        uint256 count = 0;

        if (focusOnTokenA) {
            for (uint256 i = 0; i < _allListedTokens.length && count < maxPairs; i++) {
                address tokenA = _allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = _pairOrders[tokenA][_baseToken];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += _globalOrders[tokenA][_baseToken][orderIds[j]].amount;
                }
                if (volume >= minVolume) {
                    temp[count] = TrendData(tokenA, 0, volume);
                    count++;
                }
            }
        } else {
            for (uint256 i = 0; i < _allListedTokens.length && count < maxPairs; i++) {
                address tokenA = _allListedTokens[i];
                uint256 volume = 0;
                uint256[] memory orderIds = _pairOrders[tokenA][_baseToken];
                for (uint256 j = 0; j < orderIds.length; j++) {
                    volume += _globalOrders[tokenA][_baseToken][orderIds[j]].amount;
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
            tokenBs[i] = _baseToken;
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
        require(index < _allListings.length, "Invalid index");
        return _allListings[index]; // Returns listing address at index
    }

    // Queries listing indices by token address with pagination
    function queryByAddressView(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = _queryByAddress[target]; // Retrieves listing IDs
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start); // Results array
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    // Returns length of listing indices for a token
    function queryByAddressLength(address target) external view returns (uint256) {
        return _queryByAddress[target].length; // Returns number of listings for token
    }
}