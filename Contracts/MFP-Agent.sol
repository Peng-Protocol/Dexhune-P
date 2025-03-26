// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version : 0.0.6

import "./MFP-ListingTemplate.sol";
import "./MFP-LiquidityTemplate.sol";
import "./imports/Ownable.sol";

contract MFPAgent is Ownable {
    address public routerAddress;
    uint256 public listingCount;

    struct ListingValidation {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xLiquid;
        uint256 yLiquid;
    }

    mapping(address => mapping(address => bool)) public listedPairs;
    mapping(uint256 => ListingValidation) public listingValidationByIndex;
    mapping(address => uint256) public listingValidationByAddress;
    mapping(address => uint256[]) public listingIndex;

    event ListingCreated(uint256 listingId, address listingAddress, address liquidityAddress);

    function setRouter(address _routerAddress) external onlyOwner {
        require(_routerAddress != address(0), "Invalid router address");
        routerAddress = _routerAddress;
    }

    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(!listedPairs[tokenA][tokenB], "Pair already listed");

        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingCount));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingCount));

        listingAddress = address(new MFPListingTemplate{salt: listingSalt}());
        liquidityAddress = address(new MFPLiquidityTemplate{salt: liquiditySalt}());

        MFPListingTemplate(listingAddress).setRouter(routerAddress);
        MFPListingTemplate(listingAddress).setLiquidityAddress(listingCount, liquidityAddress);
        MFPListingTemplate(listingAddress).setTokens(tokenA, tokenB);

        MFPLiquidityTemplate(liquidityAddress).setRouter(routerAddress);
        MFPLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        MFPLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);

        listingValidationByIndex[listingCount] = ListingValidation(
            listingAddress,
            liquidityAddress,
            tokenA,
            tokenB,
            0,
            0,
            0,
            0
        );
        listingValidationByAddress[listingAddress] = listingCount;
        listingIndex[tokenA].push(listingCount);
        listingIndex[tokenB].push(listingCount);
        listedPairs[tokenA][tokenB] = true;
        emit ListingCreated(listingCount, listingAddress, liquidityAddress);
        listingCount++;
    }

    function isValidListing(address listingAddress) external view returns (bool) {
        return listingValidationByAddress[listingAddress] != 0 || listingAddress == listingValidationByIndex[listingValidationByAddress[listingAddress]].listingAddress;
    }

    function getListingId(address listingAddress) external view returns (uint256) {
        require(this.isValidListing(listingAddress), "Invalid listing");
        return listingValidationByAddress[listingAddress];
    }

    function writeValidationSlot(
        uint256 listingId,
        address listingAddress,
        address tokenA,
        address tokenB,
        uint256 xBalance,
        uint256 yBalance,
        uint256 xLiquid,
        uint256 yLiquid
    ) external {
        require(msg.sender == routerAddress, "Router only");
        require(listingValidationByIndex[listingId].listingAddress == listingAddress, "Invalid listing");
        listingValidationByIndex[listingId] = ListingValidation(
            listingAddress,
            listingValidationByIndex[listingId].liquidityAddress,
            tokenA,
            tokenB,
            xBalance,
            yBalance,
            xLiquid,
            yLiquid
        );
    }
}