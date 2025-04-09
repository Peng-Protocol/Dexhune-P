// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.5 (Updated)
// Changes:
// - Fixed E7: Added tax-on-transfer checks in executeBuyOrders/executeSellOrders (from v0.0.4).
// - Fixed E1: Inverted price for buy orders (tokenBAmount = tokenAAmount / price) (from v0.0.4).
// - Fixed E2: Removed redundant decimal conversion, relying on OMFListingTemplate.getPrice() (from v0.0.4).
// - Updated for OMFListingTemplate v0.0.7: 7-field BuyOrder/SellOrder, token0/baseToken, added yVolume tracking (new in v0.0.5).
// - Fixed assembly errors in prepBuyOrders/prepSellOrders: Correctly set data.updates length using data.orderCount (previous revision).
// - Fixed stack-too-deep in execute$order and prep$order: Added ExecutionState and PrepState structs with helper functions (this revision).

import "./imports/SafeERC20.sol";

interface IOMFListing {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function token0() external view returns (address);
    function baseToken() external view returns (address);
    function getPrice() external view returns (uint256);
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
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
}

library OMFSettlementLibrary {
    using SafeERC20 for IERC20;

    struct PreparedUpdate {
        uint256 orderId;
        uint256 value;
        address recipient;
    }

    struct SettlementData {
        uint256 orderCount;
        uint256[] orderIds;
        PreparedUpdate[] updates;
        address token0;    // Token-0 (listed token)
        address baseToken; // Token-1 (reference token)
    }

    struct PrepState {
        uint256 price;
        IOMFListing listing;
    }

    struct ExecutionState {
        uint256 totalBaseToken;
        uint256 price;
        IERC20 baseToken;
    }

    function prepBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        IOMFListing listing = IOMFListing(listingAddress);
        uint256[] memory pendingOrders = orderIds.length > 0 ? orderIds : listing.pendingBuyOrdersView();
        SettlementData memory data;
        data.orderIds = pendingOrders;
        data.updates = new PreparedUpdate[](pendingOrders.length);
        data.token0 = listing.token0();
        data.baseToken = listing.baseToken();

        PrepState memory state = PrepState(listing.getPrice(), listing);
        processPrepBuyOrders(data, pendingOrders, state);

        assembly {
            let updatesPtr := add(data, 0x40) // Offset to data.updates
            let count := mload(data)          // data.orderCount at offset 0x00
            mstore(updatesPtr, count)         // Set length of data.updates
        }
        return data;
    }

    function processPrepBuyOrders(
        SettlementData memory data,
        uint256[] memory pendingOrders,
        PrepState memory state
    ) internal view {
        for (uint256 i = 0; i < pendingOrders.length; i++) {
            (
                address maker,
                address recipient,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = state.listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && state.price >= minPrice && state.price <= maxPrice) {
                data.updates[data.orderCount] = PreparedUpdate(pendingOrders[i], pending, recipient);
                data.orderCount++;
            }
        }
    }

    function executeBuyOrders(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](data.orderCount + 1);
        ExecutionState memory state = ExecutionState(0, listing.getPrice(), IERC20(data.baseToken));

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            processBuyOrder(listing, updates, i, update, state, proxy);
        }

        if (data.orderCount > 0) {
            updates[data.orderCount] = IOMFListing.UpdateType(0, 3, state.totalBaseToken, data.baseToken, address(0), 0, 0); // yVolume
            listing.update(proxy, updates);
        }
    }

    function processBuyOrder(
        IOMFListing listing,
        IOMFListing.UpdateType[] memory updates,
        uint256 index,
        PreparedUpdate memory update,
        ExecutionState memory state,
        address proxy
    ) internal {
        (, address recipient, , , uint256 pending, , ) = listing.buyOrders(update.orderId);
        uint256 baseTokenAmount = pending; // baseToken to spend
        uint256 token0Amount = (baseTokenAmount * 1e18) / state.price; // token0 to receive
        state.totalBaseToken += baseTokenAmount;

        uint256 preBalance = state.baseToken.balanceOf(recipient);
        listing.transact(proxy, address(state.baseToken), token0Amount, recipient);
        uint256 postBalance = state.baseToken.balanceOf(recipient);
        uint256 actualReceived = postBalance - preBalance;
        uint256 adjustedValue = (actualReceived * state.price) / 1e18; // Adjust baseToken spent
        updates[index] = IOMFListing.UpdateType(
            1, update.orderId, pending > adjustedValue ? pending - adjustedValue : 0, address(0), recipient, 0, 0
        );
    }

    function prepSellOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        IOMFListing listing = IOMFListing(listingAddress);
        uint256[] memory pendingOrders = orderIds.length > 0 ? orderIds : listing.pendingSellOrdersView();
        SettlementData memory data;
        data.orderIds = pendingOrders;
        data.updates = new PreparedUpdate[](pendingOrders.length);
        data.token0 = listing.token0();
        data.baseToken = listing.baseToken();

        PrepState memory state = PrepState(listing.getPrice(), listing);
        processPrepSellOrders(data, pendingOrders, state);

        assembly {
            let updatesPtr := add(data, 0x40) // Offset to data.updates
            let count := mload(data)          // data.orderCount at offset 0x00
            mstore(updatesPtr, count)         // Set length of data.updates
        }
        return data;
    }

    function processPrepSellOrders(
        SettlementData memory data,
        uint256[] memory pendingOrders,
        PrepState memory state
    ) internal view {
        for (uint256 i = 0; i < pendingOrders.length; i++) {
            (
                address maker,
                address recipient,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = state.listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && state.price >= minPrice && state.price <= maxPrice) {
                data.updates[data.orderCount] = PreparedUpdate(pendingOrders[i], pending, recipient);
                data.orderCount++;
            }
        }
    }

    function executeSellOrders(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](data.orderCount + 1);
        ExecutionState memory state = ExecutionState(0, listing.getPrice(), IERC20(data.baseToken));

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            processSellOrder(listing, updates, i, update, state, proxy);
        }

        if (data.orderCount > 0) {
            updates[data.orderCount] = IOMFListing.UpdateType(0, 1, state.totalBaseToken, data.baseToken, address(0), 0, 0); // yBalance
            listing.update(proxy, updates);
        }
    }

    function processSellOrder(
        IOMFListing listing,
        IOMFListing.UpdateType[] memory updates,
        uint256 index,
        PreparedUpdate memory update,
        ExecutionState memory state,
        address proxy
    ) internal {
        (, address recipient, , , uint256 pending, , ) = listing.sellOrders(update.orderId);
        uint256 token0Amount = pending; // token0 to send
        uint256 baseTokenAmount = (token0Amount * state.price) / 1e18; // baseToken to receive
        state.totalBaseToken += baseTokenAmount;

        uint256 preBalance = state.baseToken.balanceOf(recipient);
        listing.transact(proxy, address(state.baseToken), baseTokenAmount, recipient);
        uint256 postBalance = state.baseToken.balanceOf(recipient);
        uint256 actualReceived = postBalance - preBalance;
        uint256 adjustedValue = (actualReceived * 1e18) / state.price; // Adjust token0 sent
        updates[index] = IOMFListing.UpdateType(
            2, update.orderId, pending > adjustedValue ? pending - adjustedValue : 0, address(0), recipient, 0, 0
        );
    }
}
