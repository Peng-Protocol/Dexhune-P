// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.5 (Updated)
// Changes:
// - Clarified tokenA as Token-0 (listed token) and baseToken as Token-1 (reference token).
// - Mov
// - Removed fee collection in executeListing; added 1% supply ownership check for caller in prepListing (this revision).

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface IOMFListingTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setOracleDetails(address oracle, uint8 decimals, bytes4 viewFunction) external;
}

interface IOMFLiquidityTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
}

interface IOMFListingLibrary {
    function deploy(bytes32 salt) external returns (address);
}

interface IOMFLiquidityLibrary {
    function deploy(bytes32 salt) external returns (address);
}

interface IOMFListing {
    function liquidityAddresses(uint256 listingId) external view returns (address);
}

contract OMFAgent is Ownable {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public listingLibraryAddress;
    address public liquidityLibraryAddress;
    address public baseToken; // Token-1 (reference token)
    
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing; // tokenA (Token-0) to baseToken (Token-1)
    address[] public allListings;
    address[] public allListedTokens;

    struct PrepData {
        bytes32 listingSalt;
        bytes32 liquiditySalt;
        address tokenA; // Token-0 (listed token)
        address oracleAddress;
        uint8 oracleDecimals;
        bytes4 oracleViewFunction;
    }

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);

    constructor() {}

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

    function setListingLibrary(address _listingLibrary) external onlyOwner {
        require(_listingLibrary != address(0), "Invalid library address");
        listingLibraryAddress = _listingLibrary;
    }

    function setLiquidityLibrary(address _liquidityLibrary) external onlyOwner {
        require(_liquidityLibrary != address(0), "Invalid library address");
        liquidityLibraryAddress = _liquidityLibrary;
    }

    function setBaseToken(address _baseToken) external onlyOwner {
        require(_baseToken != address(0), "Base token cannot be NATIVE");
        baseToken = _baseToken; // Token-1
    }

    
    function checkCallerBalance(address tokenA, uint256 totalSupply) internal view returns (bool) {
        uint256 decimals = IERC20(tokenA).decimals();
        uint256 requiredBalance = totalSupply / 100; // 1% of total supply
        if (decimals != 18) {
            requiredBalance = (totalSupply * 1e18) / (100 * 10 ** decimals);
        }
        return IERC20(tokenA).balanceOf(msg.sender) >= requiredBalance;
    }

    function _initializePair(
        address listingAddress,
        address liquidityAddress,
        address tokenA, // Token-0
        address tokenB, // Token-1 (baseToken)
        uint256 listingId,
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) internal {
        IOMFListingTemplate(listingAddress).setRouter(routerAddress);
        IOMFListingTemplate(listingAddress).setListingId(listingId);
        IOMFListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        IOMFListingTemplate(listingAddress).setTokens(tokenA, tokenB); // Token-0, Token-1
        IOMFListingTemplate(listingAddress).setOracleDetails(oracleAddress, oracleDecimals, oracleViewFunction);

        IOMFLiquidityTemplate(liquidityAddress).setRouter(routerAddress);
        IOMFLiquidityTemplate(liquidityAddress).setListingId(listingId);
        IOMFLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        IOMFLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB); // Token-0, Token-1
    }

    function prepListing(
        address tokenA, // Token-0
        address oracleAddress,
        uint8 oracleDecimals,
        bytes4 oracleViewFunction
    ) public returns (address) {
        require(baseToken != address(0), "Base token not set");
        require(tokenA != baseToken, "Identical tokens");
        require(tokenA != address(0), "TokenA cannot be NATIVE");
        require(getListing[tokenA][baseToken] == address(0), "Pair already listed");
        require(routerAddress != address(0), "Router not set");
        require(listingLibraryAddress != address(0), "Listing library not set");
        require(liquidityLibraryAddress != address(0), "Liquidity library not set");
        
        require(oracleAddress != address(0), "Invalid oracle address");

        uint256 supply = IERC20(tokenA).totalSupply();
        require(checkCallerBalance(tokenA, supply), "Must own at least 1% of token supply");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, baseToken, listingCount));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(baseToken, tokenA, listingCount));

        PrepData memory prep = PrepData(listingSalt, liquiditySalt, tokenA, oracleAddress, oracleDecimals, oracleViewFunction);
        return executeListing(prep);
    }

    function executeListing(PrepData memory prep) internal returns (address) {
        address listingAddress = IOMFListingLibrary(listingLibraryAddress).deploy(prep.listingSalt);
        address liquidityAddress = IOMFLiquidityLibrary(liquidityLibraryAddress).deploy(prep.liquiditySalt);

        _initializePair(
            listingAddress,
            liquidityAddress,
            prep.tokenA, // Token-0
            baseToken,   // Token-1
            listingCount,
            prep.oracleAddress,
            prep.oracleDecimals,
            prep.oracleViewFunction
        );

        getListing[prep.tokenA][baseToken] = listingAddress; // Token-0 to Token-1
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
        liquidityAddress = IOMFListing(deployedListing).liquidityAddresses(0);
        return (listingAddress, liquidityAddress);
    }

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }
}