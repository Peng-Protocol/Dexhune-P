// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1 (new library)

import "./MFP-LiquidityTemplate.sol";

contract MFPLiquidityLibrary {
    function deploy(bytes32 salt) public returns (address) {
        address liquidityAddress = address(new MFPLiquidityTemplate{salt: salt}());
        return liquidityAddress;
    }
} 