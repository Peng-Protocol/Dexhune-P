// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1
// Changes:
// - Created to handle OMFLiquidityTemplate deployment separately from OMFListingLogic.
// - Resolves SafeERC20 import duplication by isolating liquidity template deployment.

import "./utils/OMF-LiquidityTemplate.sol";

contract OMFLiquidityLogic {
    function deploy(bytes32 liquiditySalt) public returns (address liquidityAddress) {
        liquidityAddress = address(new OMFLiquidityTemplate{salt: liquiditySalt}());
        return liquidityAddress;
    }
}