// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

// Version: 0.0.2

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./MFP-ListingTemplate.sol";
import "./MFP-LiquidityTemplate.sol";

contract MFPAgent is Ownable {
    using SafeERC20 for IERC20;

    // State Variables
    address public routerAddress;
    mapping(uint256 => ListingValidation) public listingValidationByIndex; // listingId -> validation details
    mapping(address => uint256) public listingIds; // listingAddress -> listingId

    // Structs
    struct ListingValidation {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xLiquidity;
        uint256 yLiquidity;
    }

    // Events
    event ListingCreated(uint256 indexed listingId, address listingAddress, address liquidityAddress, address tokenA, address tokenB);

    constructor() {
        _transferOwnership(msg.sender);
    }

    function setRouter(address _router) external onlyOwner {
        require(routerAddress == address(0), "Router already set");
        routerAddress = _router;
    }

    function listToken(
        uint256 listingId,
        address tokenA,
        address tokenB,
        bytes32 salt
    ) external onlyOwner returns (address listingAddress, address liquidityAddress) {
        require(listingValidationByIndex[listingId].listingAddress == address(0), "Listing ID already used");

        // Deploy MFP-ListingTemplate with CREATE2
        listingAddress = address(new MFPListingTemplate{salt: salt}());
        MFPListingTemplate(listingAddress).transferOwnership(msg.sender);
        MFPListingTemplate(listingAddress).setRouter(routerAddress);
        MFPListingTemplate(listingAddress).setTokens(tokenA, tokenB);

        // Deploy MFP-LiquidityTemplate with CREATE2
        liquidityAddress = address(new MFPLiquidityTemplate{salt: salt}());
        MFPLiquidityTemplate(liquidityAddress).transferOwnership(msg.sender);
        MFPLiquidityTemplate(liquidityAddress).setRouter(routerAddress);
        MFPLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);

        // Link liquidity to listing
        MFPListingTemplate(listingAddress).setLiquidityAddress(listingId, liquidityAddress);

        // Store validation details
        listingValidationByIndex[listingId] = ListingValidation({
            listingAddress: listingAddress,
            liquidityAddress: liquidityAddress,
            tokenA: tokenA,
            tokenB: tokenB,
            xBalance: 0,
            yBalance: 0,
            xLiquidity: 0,
            yLiquidity: 0
        });
        listingIds[listingAddress] = listingId;

        emit ListingCreated(listingId, listingAddress, liquidityAddress, tokenA, tokenB);
        return (listingAddress, liquidityAddress);
    }

    function writeValidationSlot(
        uint256 listingId,
        address listingAddress,
        address tokenA,
        address tokenB,
        uint256 xBalance,
        uint256 yBalance,
        uint256 xLiquidity,
        uint256 yLiquidity
    ) external {
        require(msg.sender == routerAddress, "Router only");
        ListingValidation storage validation = listingValidationByIndex[listingId];
        require(validation.listingAddress == listingAddress, "Invalid listing address");

        validation.tokenA = tokenA;
        validation.tokenB = tokenB;
        validation.xBalance = xBalance;
        validation.yBalance = yBalance;
        validation.xLiquidity = xLiquidity;
        validation.yLiquidity = yLiquidity;
    }

    function isValidListing(address listingAddress) external view returns (bool) {
        return listingIds[listingAddress] != 0 || listingValidationByIndex[listingIds[listingAddress]].listingAddress == listingAddress;
    }

    function getListingId(address listingAddress) external view returns (uint256) {
        uint256 listingId = listingIds[listingAddress];
        require(listingValidationByIndex[listingId].listingAddress == listingAddress, "Invalid listing");
        return listingId;
    }
}