// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.8

import "./MFP-ListingTemplate.sol";
import "./MFP-LiquidityTemplate.sol";
import "./imports/Ownable.sol";

contract MFPAgent is Ownable {
    address public routerAddress;
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing; // tokenA -> tokenB -> listingAddress
    address[] public allListings;
    address[] public allListedTokens; // New: Stores unique token addresses

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);

    // Helper function to check if a token already exists in allListedTokens
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

    // Internal function to initialize the deployed pair
    function _initializePair(
        address listingAddress,
        address liquidityAddress,
        address tokenA,
        address tokenB,
        uint256 listingId
    ) internal {
        MFPListingTemplate(listingAddress).setRouter(routerAddress);
        MFPListingTemplate(listingAddress).setLiquidityAddress(listingId, liquidityAddress);
        MFPListingTemplate(listingAddress).setTokens(tokenA, tokenB);

        MFPLiquidityTemplate(liquidityAddress).setRouter(routerAddress);
        MFPLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        MFPLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);
    }

    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(routerAddress != address(0), "Router not set");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingCount));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingCount));

        listingAddress = address(new MFPListingTemplate{salt: listingSalt}());
        liquidityAddress = address(new MFPLiquidityTemplate{salt: liquiditySalt}());

        _initializePair(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);

        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);

        // Add unique tokens to allListedTokens
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
        (address tokenA, address tokenB) = isA ? (nativeAddress, token) : (token, nativeAddress);
        (listingAddress, liquidityAddress) = this.listToken(tokenA, tokenB);
        return (listingAddress, liquidityAddress);
    }

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }
}