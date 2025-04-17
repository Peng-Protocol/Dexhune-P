// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.8 (Updated)
// Changes:
// - From v0.0.7: Added normalize/denormalize functions for decimal handling (new in v0.0.8).
// - From v0.0.7: Updated computeOrderAmounts to normalize inputs and denormalize outputs (new in v0.0.8).
// - From v0.0.7: Updated performTransactionAndAdjust to denormalize amount before transact and normalize actualReceived (new in v0.0.8).
// - From v0.0.6: Fixed stack-too-deep in processBuyOrder/processSellOrder by introducing ProcessOrderState struct and helper functions computeOrderAmounts/performTransactionAndAdjust.
// - From v0.0.5: Removed listingId from all functions and interfaces to align with implicit listingId in OMFListingTemplate.
// - Updated IOMFListing interface: Removed listingId from volumeBalances(), liquidityAddresses().
// - Fixed E7: Added tax-on-transfer checks in executeBuyOrders/executeSellOrders (from v0.0.4).
// - Fixed E1: Inverted price for buy orders (tokenBAmount = tokenAAmount / price) (from v0.0.4).
// - Fixed E2: Removed redundant decimal conversion, relying on OMFListingTemplate.getPrice() (from v0.0.4).
// - Updated for OMFListingTemplate v0.0.7: 7-field BuyOrder/SellOrder, token0/baseToken, added yVolume tracking (from v0.0.5).
// - Fixed assembly errors in prepBuyOrders/prepSellOrders: Correctly set data.updates length using data.orderCount (from v0.0.5).
// - Fixed stack-too-deep in execute$order and prep$order: Added ExecutionState and PrepState structs with helper functions (from v0.0.5).
// - Side effects: Ensures correct decimal handling for tax-on-transfer tokens; improves robustness for non-18 decimal tokens.

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
    function volumeBalances() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
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

    struct ProcessOrderState {
        uint256 baseTokenAmount;
        uint256 token0Amount;
        uint256 actualReceived;
        uint256 adjustedValue;
        address recipientAddress;
        uint256 preBalance;
        uint256 postBalance;
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

    function computeOrderAmounts(
        uint256 price,
        uint256 pending,
        bool isBuy,
        uint8 token0Decimals,
        uint8 baseTokenDecimals
    ) internal pure returns (uint256 baseTokenAmount, uint256 token0Amount) {
        uint256 normalizedPending = normalize(pending, isBuy ? baseTokenDecimals : token0Decimals);
        if (isBuy) {
            baseTokenAmount = normalizedPending;
            token0Amount = (baseTokenAmount * 1e18) / price;
            baseTokenAmount = denormalize(baseTokenAmount, baseTokenDecimals);
            token0Amount = denormalize(token0Amount, token0Decimals);
        } else {
            token0Amount = normalizedPending;
            baseTokenAmount = (token0Amount * price) / 1e18;
            token0Amount = denormalize(token0Amount, token0Decimals);
            baseTokenAmount = denormalize(baseTokenAmount, baseTokenDecimals);
        }
    }

    function performTransactionAndAdjust(
        IOMFListing listing,
        address proxy,
        IERC20 baseToken,
        uint256 amount,
        address recipient,
        uint256 price,
        bool isBuy,
        uint8 decimals
    ) internal returns (uint256 actualReceived, uint256 adjustedValue) {
        uint256 rawAmount = denormalize(amount, decimals);
        uint256 preBalance = baseToken.balanceOf(recipient);
        listing.transact(proxy, address(baseToken), rawAmount, recipient);
        uint256 postBalance = baseToken.balanceOf(recipient);
        actualReceived = normalize(postBalance - preBalance, decimals);
        adjustedValue = isBuy ? (actualReceived * price) / 1e18 : (actualReceived * 1e18) / price;
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
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = state.listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && state.price >= minPrice && state.price <= maxPrice) {
                data.updates[data.orderCount] = PreparedUpdate(pendingOrders[i], pending, recipientAddress);
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
        uint8 baseTokenDecimals = IERC20(data.baseToken).decimals();
        uint8 token0Decimals = IERC20(data.token0).decimals();
        ExecutionState memory state = ExecutionState(0, listing.getPrice(), IERC20(data.baseToken));

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            processBuyOrder(listing, updates, i, update, state, proxy, token0Decimals, baseTokenDecimals);
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
        address proxy,
        uint8 token0Decimals,
        uint8 baseTokenDecimals
    ) internal {
        // Explicit destructuring
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint8 status;
        (
            makerAddress,
            recipientAddress,
            maxPrice,
            minPrice,
            pending,
            filled,
            status
        ) = listing.buyOrders(update.orderId);

        ProcessOrderState memory orderState;
        orderState.recipientAddress = recipientAddress;

        // Compute amounts
        (orderState.baseTokenAmount, orderState.token0Amount) = computeOrderAmounts(state.price, pending, true, token0Decimals, baseTokenDecimals);
        state.totalBaseToken += orderState.baseTokenAmount;

        // Perform transaction and adjust
        (orderState.actualReceived, orderState.adjustedValue) = performTransactionAndAdjust(
            listing,
            proxy,
            state.baseToken,
            orderState.token0Amount,
            recipientAddress,
            state.price,
            true,
            token0Decimals
        );

        // Update order
        updates[index] = IOMFListing.UpdateType(
            1,
            update.orderId,
            pending > orderState.adjustedValue ? pending - orderState.adjustedValue : 0,
            address(0),
            recipientAddress,
            0,
            0
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
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = state.listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && state.price >= minPrice && state.price <= maxPrice) {
                data.updates[data.orderCount] = PreparedUpdate(pendingOrders[i], pending, recipientAddress);
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
        uint8 baseTokenDecimals = IERC20(data.baseToken).decimals();
        uint8 token0Decimals = IERC20(data.token0).decimals();
        ExecutionState memory state = ExecutionState(0, listing.getPrice(), IERC20(data.baseToken));

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            processSellOrder(listing, updates, i, update, state, proxy, token0Decimals, baseTokenDecimals);
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
        address proxy,
        uint8 token0Decimals,
        uint8 baseTokenDecimals
    ) internal {
        // Explicit destructuring
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint8 status;
        (
            makerAddress,
            recipientAddress,
            maxPrice,
            minPrice,
            pending,
            filled,
            status
        ) = listing.sellOrders(update.orderId);

        ProcessOrderState memory orderState;
        orderState.recipientAddress = recipientAddress;

        // Compute amounts
        (orderState.baseTokenAmount, orderState.token0Amount) = computeOrderAmounts(state.price, pending, false, token0Decimals, baseTokenDecimals);
        state.totalBaseToken += orderState.baseTokenAmount;

        // Perform transaction and adjust
        (orderState.actualReceived, orderState.adjustedValue) = performTransactionAndAdjust(
            listing,
            proxy,
            state.baseToken,
            orderState.baseTokenAmount,
            recipientAddress,
            state.price,
            false,
            baseTokenDecimals
        );

        // Update order
        updates[index] = IOMFListing.UpdateType(
            2,
            update.orderId,
            pending > orderState.adjustedValue ? pending - orderState.adjustedValue : 0,
            address(0),
            recipientAddress,
            0,
            0
        );
    }
}