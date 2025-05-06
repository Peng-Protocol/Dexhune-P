// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4 (Updated)
// Changes:
// - Removed normalize and denormalize functions, moved to OMFSharedUtils library.
// - Retained SafeERC20 import and usage for centralized ERC20 operations.
// - Retained UpdateType struct and IOMFListing/IOMFLiquidity interfaces.
// - From v0.0.3: Restored IOMFListing and IOMFLiquidity interfaces.
// - From v0.0.3: Added using OMFShared.SafeERC20 for IERC20.
// - From v0.0.2: Converted from library to abstract contract for interface declarations.
// - From v0.0.1: Centralized SafeERC20, UpdateType, and interfaces.

import "../imports/SafeERC20.sol";

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

abstract contract OMFShared {
    using SafeERC20 for IERC20;
}