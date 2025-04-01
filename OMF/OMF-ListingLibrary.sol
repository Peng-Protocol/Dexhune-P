// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1 (new library)

import "./OMF-ListingTemplate.sol";

contract OMFListingLibrary {
    function deploy(bytes32 salt) public returns (address) {
        address listingAddress = address(new OMFListingTemplate{salt: salt}());
        return listingAddress;
    }
} 