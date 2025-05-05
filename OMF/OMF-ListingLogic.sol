// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1
// Changes:
// - Replaced OMFListingLibrary with OMFListingLogic contract.
// - Updated deploy function to deploy both OMFListingTemplate and OMFLiquidityTemplate using separate salts.

import "./utils/OMF-ListingTemplate.sol";
import "./utils/OMF-LiquidityTemplate.sol";

contract OMFListingLogic {
    function deploy(bytes32 listingSalt, bytes32 liquiditySalt) public returns (address listingAddress, address liquidityAddress) {
        listingAddress = address(new OMFListingTemplate{salt: listingSalt}());
        liquidityAddress = address(new OMFLiquidityTemplate{salt: liquiditySalt}());
        return (listingAddress, liquidityAddress);
    }
}