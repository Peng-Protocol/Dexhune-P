/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-19: Created MockOracleETH with fixed 3500e8 price for ETH/USD.
*/

pragma solidity ^0.8.2;

contract MockOracleETH {
    // Returns fixed ETH/USD price (3500e8)
    function latestAnswer() external pure returns (int256) {
        return 3500 * 10**8;
    }
}