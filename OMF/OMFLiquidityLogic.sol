// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.2 (Updated)
// Changes:
// - v0.0.2: Added note to remove taxCollector functionality from SS-LiquidityTemplate.sol.
// - v0.0.1: Converted library to regular contract SSLiquidityLogic.

// Note: Remove taxCollector functionality from LiquidityTemplate.sol.

import "./utils/OMFLiquidityTemplate.sol";

contract OMFLiquidityLogic {
    function deploy(bytes32 salt) external returns (address) {
        address liquidityAddress = address(new OMFLiquidityTemplate{salt: salt}());
        return liquidityAddress;
    }
}