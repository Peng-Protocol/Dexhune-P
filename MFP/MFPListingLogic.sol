// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.2 (converted from library to contract)

import "./utils/MFP-ListingTemplate.sol";

contract MFPListingLogic {
    function deploy(bytes32 salt) public returns (address) {
        address listingAddress = address(new MFPListingTemplate{salt: salt}());
        return listingAddress;
    }
}