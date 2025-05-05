// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1
// Changes:
// - Replaced OMFListingLibrary with OMFListingLogic contract.
// - Updated deploy function to deploy only OMFListingTemplate, removing OMFLiquidityTemplate deployment.
// - Removed OMFLiquidityTemplate import to resolve SafeERC20 import duplication.

import "./utils/OMF-ListingTemplate.sol";

contract OMFListingLogic {
    function deploy(bytes32 listingSalt) public returns (address listingAddress) {
        listingAddress = address(new OMFListingTemplate{salt: listingSalt}());
        return listingAddress;
    }
}