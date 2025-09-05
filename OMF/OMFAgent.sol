// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.4
// Changes:
// - v0.1.4: Created OMFAgent from MFPAgent. Added baseToken and setter, restricted tokenB to baseToken, removed listNative, added oracle params in listing/relisting.
// - v0.1.3: Created MFPAgent from CCAgent.

import "./imports/Ownable.sol";

interface ICCListingTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function setRegistry(address _registryAddress) external;
    function setGlobalizerAddress(address globalizerAddress_) external;
    function setOracleParams(address _oracleAddress, bytes4 _oracleFunction, uint16 _oracleBitSize, bool _oracleIsSigned, uint8 _oracleDecimals) external;
    function getTokens() external view returns (address tokenA, address tokenB);
}

interface ISSLiquidityTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
}

interface ICCListingLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface ISSLiquidityLogic {
    function deploy(bytes32 salt) external returns (address);
}

interface ICCListing {
    function liquidityAddressView() external view returns (address);
}

contract OMFAgent is Ownable {
    address[] public routers; // Array of router contract addresses
    address public listingLogicAddress; // CCListingLogic contract address
    address public liquidityLogicAddress; // CCLiquidityLogic contract address
    address public registryAddress; // Registry contract address
    address public baseToken; // Fixed tokenB for all listings
    uint256 public listingCount; // Counter for total listings created
    address public globalizerAddress; // Address for globalizer contract

    mapping(address tokenA => address listingAddress) public getListing; // tokenA => listing address (tokenB is baseToken)
    address[] private allListings; // Array of all listing addresses
    address[] private allListedTokens; // Array of all unique listed tokens
    mapping(address => uint256[]) private queryByAddress; // token => listing IDs
    mapping(address listingAddress => address lister) public getLister; // listingAddress => lister address
    mapping(address => uint256[]) private listingsByLister; // lister => listing IDs

    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Fixed to baseToken
        uint256 listingId; // Listing ID
    }

    struct OracleParams {
        address oracleAddress; // Oracle contract address
        bytes4 oracleFunction; // Oracle function selector
        uint16 oracleBitSize; // Bit size of oracle return type
        bool oracleIsSigned; // True for signed, false for unsigned
        uint8 oracleDecimals; // Oracle decimals
    }
    
// System expects a tuple for the oracleParams struct, entered as a single text field in the format: `(oracleAddress,oracleFunction,oracleBitSize,oracleIsSigned,oracleDecimals)`.
// Example input:
// (0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,0x50d25bcd,256,true,8)

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId, address indexed lister);
    event RouterAdded(address indexed router); // Emitted when a router is added
    event RouterRemoved(address indexed router); // Emitted when a router is removed
    event ListingRelisted(address indexed tokenA, address indexed tokenB, address oldListingAddress, address newListingAddress, uint256 listingId, address indexed lister);
    event GlobalizerAddressSet(address indexed globalizer); // Emitted when globalizer address is set
    event BaseTokenSet(address indexed baseToken); // Emitted when baseToken is set
    event ListerTransferred(address indexed listingAddress, address indexed oldLister, address indexed newLister);

    // Sets globalizer contract address, restricted to owner
    function setGlobalizerAddress(address _globalizerAddress) external onlyOwner {
        require(_globalizerAddress != address(0), "Invalid globalizer address");
        globalizerAddress = _globalizerAddress;
        emit GlobalizerAddressSet(_globalizerAddress);
    }

    // Sets baseToken address, restricted to owner, callable once
    function setBaseToken(address _baseToken) external onlyOwner {
        require(_baseToken != address(0), "Invalid base token address");
        require(baseToken == address(0), "Base token already set");
        baseToken = _baseToken;
        emit BaseTokenSet(_baseToken);
    }

    // Checks if a token exists in allListedTokens
    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (allListedTokens[i] == token) {
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

    // Deploys listing and liquidity contracts using create2 with provided salt
    function _deployPair(address tokenA, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, baseToken, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(baseToken, tokenA, listingId));
        listingAddress = ICCListingLogic(listingLogicAddress).deploy(listingSalt);
        liquidityAddress = ISSLiquidityLogic(liquidityLogicAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    // Initializes listing contract with routers, listing ID, liquidity address, tokens, agent, registry, globalizer, and oracle params
    function _initializeListing(address listingAddress, address liquidityAddress, address tokenA, uint256 listingId, OracleParams memory oracleParams) internal {
        ICCListingTemplate(listingAddress).setRouters(routers);
        ICCListingTemplate(listingAddress).setListingId(listingId);
        ICCListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        ICCListingTemplate(listingAddress).setTokens(tokenA, baseToken);
        ICCListingTemplate(listingAddress).setAgent(address(this));
        ICCListingTemplate(listingAddress).setRegistry(registryAddress);
        if (globalizerAddress != address(0)) {
            ICCListingTemplate(listingAddress).setGlobalizerAddress(globalizerAddress);
        }
        ICCListingTemplate(listingAddress).setOracleParams(
            oracleParams.oracleAddress,
            oracleParams.oracleFunction,
            oracleParams.oracleBitSize,
            oracleParams.oracleIsSigned,
            oracleParams.oracleDecimals
        );
    }

    // Initializes liquidity contract with routers, listing ID, listing address, tokens, and agent
    function _initializeLiquidity(address listingAddress, address liquidityAddress, address tokenA, uint256 listingId) internal {
        ISSLiquidityTemplate(liquidityAddress).setRouters(routers);
        ISSLiquidityTemplate(liquidityAddress).setListingId(listingId);
        ISSLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        ISSLiquidityTemplate(liquidityAddress).setTokens(tokenA, baseToken);
        ISSLiquidityTemplate(liquidityAddress).setAgent(address(this));
    }

    // Updates state mappings and arrays for new listing
    function _updateState(address tokenA, address listingAddress, uint256 listingId, address lister) internal {
        getListing[tokenA] = listingAddress;
        allListings.push(listingAddress);
        if (!tokenExists(tokenA)) allListedTokens.push(tokenA);
        if (!tokenExists(baseToken)) allListedTokens.push(baseToken);
        queryByAddress[tokenA].push(listingId);
        queryByAddress[baseToken].push(listingId);
        getLister[listingAddress] = lister;
        listingsByLister[lister].push(listingId);
    }

    // Adds a router address to the routers array, restricted to owner
    function addRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(!routerExists(router), "Router already exists");
        routers.push(router);
        emit RouterAdded(router);
    }

    // Removes a router address from the routers array, restricted to owner
    function removeRouter(address router) external onlyOwner {
        require(router != address(0), "Invalid router address");
        require(routerExists(router), "Router does not exist");
        for (uint256 i = 0; i < routers.length; i++) {
            if (routers[i] == router) {
                routers[i] = routers[routers.length - 1];
                routers.pop();
                break;
            }
        }
        emit RouterRemoved(router);
    }

    // Returns the current list of routers
    function getRouters() external view returns (address[] memory) {
        return routers;
    }

    // Sets listing logic contract address, restricted to owner
    function setListingLogic(address _listingLogic) external onlyOwner {
        require(_listingLogic != address(0), "Invalid logic address");
        listingLogicAddress = _listingLogic;
    }

    // Sets liquidity logic contract address, restricted to owner
    function setLiquidityLogic(address _liquidityLogic) external onlyOwner {
        require(_liquidityLogic != address(0), "Invalid logic address");
        liquidityLogicAddress = _liquidityLogic;
    }

    // Sets registry contract address, restricted to owner
    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry address");
        registryAddress = _registryAddress;
    }

    // Lists a new token pair with baseToken, deploying listing and liquidity contracts, stores msg.sender as lister
    function listToken(address tokenA, OracleParams memory oracleParams) external returns (address listingAddress, address liquidityAddress) {
        require(baseToken != address(0), "Base token not set");
        require(tokenA != address(0) && tokenA != baseToken, "Invalid tokenA");
        require(getListing[tokenA] == address(0), "Pair already listed");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");
        require(oracleParams.oracleAddress != address(0), "Invalid oracle address");
        require(oracleParams.oracleFunction != bytes4(0), "Invalid oracle function");
        require(oracleParams.oracleBitSize > 0 && oracleParams.oracleBitSize <= 256, "Invalid bit size");
        require(oracleParams.oracleDecimals <= 18, "Invalid oracle decimals");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, listingCount);
        _initializeListing(listingAddress, liquidityAddress, tokenA, listingCount, oracleParams);
        _initializeLiquidity(listingAddress, liquidityAddress, tokenA, listingCount);
        _updateState(tokenA, listingAddress, listingCount, msg.sender);

        emit ListingCreated(tokenA, baseToken, listingAddress, liquidityAddress, listingCount, msg.sender);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // Relists an existing token pair with baseToken, replacing the old listing, restricted to original lister
    function relistToken(address tokenA, OracleParams memory oracleParams) external returns (address newListingAddress, address newLiquidityAddress) {
        require(baseToken != address(0), "Base token not set");
        require(tokenA != address(0) && tokenA != baseToken, "Invalid tokenA");
        address oldListingAddress = getListing[tokenA];
        require(oldListingAddress != address(0), "Pair not listed");
        require(getLister[oldListingAddress] == msg.sender, "Not original lister");
        require(routers.length > 0, "No routers set");
        require(listingLogicAddress != address(0), "Listing logic not set");
        require(liquidityLogicAddress != address(0), "Liquidity logic not set");
        require(registryAddress != address(0), "Registry not set");
        require(oracleParams.oracleAddress != address(0), "Invalid oracle address");
        require(oracleParams.oracleFunction != bytes4(0), "Invalid oracle function");
        require(oracleParams.oracleBitSize > 0 && oracleParams.oracleBitSize <= 256, "Invalid bit size");
        require(oracleParams.oracleDecimals <= 18, "Invalid oracle decimals");

        (newListingAddress, newLiquidityAddress) = _deployPair(tokenA, listingCount);
        _initializeListing(newListingAddress, newLiquidityAddress, tokenA, listingCount, oracleParams);
        _initializeLiquidity(newListingAddress, newLiquidityAddress, tokenA, listingCount);

        getListing[tokenA] = newListingAddress;
        allListings.push(newListingAddress);
        queryByAddress[tokenA].push(listingCount);
        queryByAddress[baseToken].push(listingCount);
        getLister[newListingAddress] = msg.sender;
        listingsByLister[msg.sender].push(listingCount);

        emit ListingRelisted(tokenA, baseToken, oldListingAddress, newListingAddress, listingCount, msg.sender);
        listingCount++;
        return (newListingAddress, newLiquidityAddress);
    }

    // Transfers lister status to a new address, restricted to current lister
    function transferLister(address listingAddress, address newLister) external {
        require(getLister[listingAddress] == msg.sender, "Not current lister");
        require(newLister != address(0), "Invalid new lister address");
        address oldLister = getLister[listingAddress];
        getLister[listingAddress] = newLister;
        uint256 listingId;
        for (uint256 i = 0; i < allListings.length; i++) {
            if (allListings[i] == listingAddress) {
                listingId = i;
                break;
            }
        }
        listingsByLister[newLister].push(listingId);
        emit ListerTransferred(listingAddress, oldLister, newLister);
    }

    // Returns paginated listing IDs for a given lister
    function getListingsByLister(address lister, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = listingsByLister[lister];
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    // Checks if a listing address is valid and returns its details
    function isValidListing(address listingAddress) public view returns (bool isValid, ListingDetails memory details) {
        isValid = false;
        for (uint256 i = 0; i < allListings.length; i++) {
            if (allListings[i] == listingAddress) {
                isValid = true;
                (address tokenA, address tokenB) = ICCListingTemplate(listingAddress).getTokens();
                address liquidityAddress = ICCListing(listingAddress).liquidityAddressView();
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

    // Returns listing address by index
    function queryByIndex(uint256 index) external view returns (address) {
        require(index < allListings.length, "Invalid index");
        return allListings[index];
    }

    // Returns paginated listing IDs for a token
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

    // Returns number of listing IDs for a token
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