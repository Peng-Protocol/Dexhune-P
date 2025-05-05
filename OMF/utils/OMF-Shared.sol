// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.3 (Updated)
// Changes:
// - Restored IOMFListing and IOMFLiquidity interfaces, as intended to remain in OMF-Shared.sol.
// - Retained as abstract contract to support interface declarations, addressing Remix AI’s library issue.
// - Retained SafeERC20 import for centralized ERC20 operations via OMFShared.SafeERC20.
// - Added using OMFShared.SafeERC20 for IERC20 to enable SafeERC20 operations across all files.
// - From v0.0.2: Converted from library to abstract contract to address Remix AI issue.
// - From v0.0.2: Removed IOMFListing/IOMFLiquidity interfaces (now restored).
// - From v0.0.1: Created to consolidate SafeERC20 import, UpdateType struct, and normalize/denormalize functions.
// - From v0.0.1: Centralized utilities previously duplicated across OMFRouter, OMF-OrderLibrary, OMF-SettlementLibrary, and OMF-LiquidLibrary.
// - From v0.0.1: Defined UpdateType struct to unify OMFRouter, OMF-OrderLibrary, and OMF-LiquidLibrary UpdateType definitions.
// - From v0.0.1: Added normalize/denormalize functions to handle decimal conversions for non-18 decimal tokens.

import "../imports/SafeERC20.sol";

abstract contract OMFShared {
    using SafeERC20 for IERC20;

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    interface IOMFListing {
        function token0() external view returns (address);
        function baseToken() external view returns (address);
        function liquidityAddress() external view returns (address);
        function getPrice() external view returns (uint256);
        function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
        function listingPriceView() external view returns (uint256);
        function buyOrders(uint256 orderId) external view returns (
            address makerAddress,
            address recipientAddress,
            uint256 maxPrice,
            uint256 minPrice,
            uint256 pending,
            uint256 filled,
            uint8 status
        );
        function sellOrders(uint256 orderId) external view returns (
            address makerAddress,
            address recipientAddress,
            uint256 maxPrice,
            uint256 minPrice,
            uint256 pending,
            uint256 filled,
            uint8 status
        );
        function pendingBuyOrdersView() external view returns (uint256[] memory);
        function pendingSellOrdersView() external view returns (uint256[] memory);
        function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
        function update(address caller, UpdateType[] memory updates) external;
        function transact(address caller, address token, uint256 amount, address recipient) external;
        function nextOrderId() external returns (uint256);
    }

    interface IOMFLiquidity {
        struct PreparedWithdrawal {
            uint256 amount0;
            uint256 amount1;
        }
        function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
        function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
        function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
        function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
        function deposit(address caller, bool isX, uint256 amount) external;
        function addFees(address caller, bool isX, uint256 fee) external;
        function claimFees(address caller, bool isX, uint256 slotIndex, uint256 volume) external;
    }

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