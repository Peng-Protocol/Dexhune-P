// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1
// Changes:
// - Created to consolidate normalize and denormalize functions previously in OMFShared.sol.
// - Defined as a library to allow internal usage in OMF-OrderLibrary.sol, OMF-Router.sol, OMF-SettlementLibrary.sol, and OMF-LiquidLibrary.sol.
// - Functions normalize and denormalize moved from OMFShared.sol to resolve TypeError: Cannot call function via contract type name.
// - Functions marked internal pure for gas efficiency and compatibility with view functions.

library OMFSharedUtils {
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10**(18 - decimals);
        else return amount / 10**(decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - decimals);
        else return amount * 10**(decimals - 18);
    }
}