/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-19: Created MockOracleXAU with fixed 4000e8 price for XAU/USD.
*/

pragma solidity ^0.8.2;

contract MockOracleXAU {
    // Returns fixed XAU/USD price (4000e8)
    function latestAnswer() external pure returns (int256) {
        return 4000 * 10**8;
    }
}