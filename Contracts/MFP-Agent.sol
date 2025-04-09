// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.11

import "./imports/Ownable.sol";

interface IMFPListingTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
}

interface IMFPLiquidityTemplate {
    function setRouter(address _routerAddress) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
}

interface IMFPListingLibrary {
    function deploy(bytes32 salt) external returns (address);
}

interface IMFPLiquidityLibrary {
    function deploy(bytes32 salt) external returns (address);
}

contract MFPAgent is Ownable {
    address public routerAddress;
    address public listingLibraryAddress;
    address public liquidityLibraryAddress;
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing;
    address[] public allListings;
    address[] public allListedTokens;

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);

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

    function _initializePair(
        address listingAddress,
        address liquidityAddress,
        address tokenA,
        address tokenB,
        uint256 listingId
    ) internal {
        IMFPListingTemplate(listingAddress).setRouter(routerAddress);
        IMFPListingTemplate(listingAddress).setListingId(listingId);
        IMFPListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        IMFPListingTemplate(listingAddress).setTokens(tokenA, tokenB);

        IMFPLiquidityTemplate(liquidityAddress).setRouter(routerAddress);
        IMFPLiquidityTemplate(liquidityAddress).setListingId(listingId);
        IMFPLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        IMFPLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);
    }

    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routerAddress != address(0), "Router not set");
        require(listingLibraryAddress != address(0), "Listing library not set");
        require(liquidityLibraryAddress != address(0), "Liquidity library not set");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingCount));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingCount));

        listingAddress = IMFPListingLibrary(listingLibraryAddress).deploy(listingSalt);
        liquidityAddress = IMFPLiquidityLibrary(liquidityLibraryAddress).deploy(liquiditySalt);

        _initializePair(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);

        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);

        if (!tokenExists(tokenA)) {
            allListedTokens.push(tokenA);
        }
        if (!tokenExists(tokenB)) {
            allListedTokens.push(tokenB);
        }

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;

        return (listingAddress, liquidityAddress);
    }

    function listNative(address token, bool isA) external returns (address listingAddress, address liquidityAddress) {
        address nativeAddress = address(0);
        address tokenA;
        address tokenB;
        if (isA) {
            tokenA = nativeAddress;
            tokenB = token;
        } else {
            tokenA = token;
            tokenB = nativeAddress;
        }

        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routerAddress != address(0), "Router not set");
        require(listingLibraryAddress != address(0), "Listing library not set");
        require(liquidityLibraryAddress != address(0), "Liquidity library not set");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingCount));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingCount));

        listingAddress = IMFPListingLibrary(listingLibraryAddress).deploy(listingSalt);
        liquidityAddress = IMFPLiquidityLibrary(liquidityLibraryAddress).deploy(liquiditySalt);

        _initializePair(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);

        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);

        if (!tokenExists(tokenA)) {
            allListedTokens.push(tokenA);
        }
        if (!tokenExists(tokenB)) {
            allListedTokens.push(tokenB);
        }

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;

        return (listingAddress, liquidityAddress);
    }

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }
}