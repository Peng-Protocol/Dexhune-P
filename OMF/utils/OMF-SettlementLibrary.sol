// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.11 (Updated)
// Changes:
// - Converted from library to abstract contract to support potential future interface declarations and avoid Remix AI library interface warnings.
// - Updated helper functions computeOrderAmounts, performTransactionAndAdjust to public to maintain external accessibility.
// - Retained processPrepBuyOrders, processPrepSellOrders, processBuyOrder, processSellOrder as internal, as used only within prep/execute functions.
// - Retained OMFShared.SafeERC20 usage, with single SafeERC20 import in OMF-Shared.sol.
// - From v0.0.10: Removed SafeERC20 import, added OMF-Shared.sol.
// - From v0.0.10: Replaced IOMFListing interface with OMFShared.IOMFListing.
// - From v0.0.10: Updated UpdateType to OMFShared.UpdateType.
// - From v0.0.10: Removed normalize/denormalize functions, used OMFShared.normalize/denormalize.
// - From v0.0.10: Replaced inline assembly in prepBuyOrders/prepSellOrders with Solidity array resizing.
// - From v0.0.8: Added normalize/denormalize functions (now in OMFShared).
// - From v0.0.8: Updated computeOrderAmounts to normalize inputs and denormalize outputs.
// - From v0.0.8: Updated performTransactionAndAdjust to denormalize amount before transact and normalize actualReceived.
// - From v0.0.7: Fixed stack-too-deep in processBuyOrder/processSellOrder with ProcessOrderState struct and helpers.
// - From v0.0.6: Removed listingId from all functions to align with OMFListingTemplate.
// - From v0.0.5: Updated for OMFListingTemplate v0.0.7: 7-field BuyOrder/SellOrder, token0/baseToken, yVolume tracking.
// - From v0.0.5: Fixed assembly errors in prepBuyOrders/prepSellOrders.
// - From v0.0.5: Fixed stack-too-deep in execute/prep with ExecutionState and PrepState structs.
// - From v0.0.4: Fixed E7: Added tax-on-transfer checks in executeBuyOrders/executeSellOrders.
// - From v0.0.4: Fixed E1: Inverted price for buy orders (tokenBAmount = tokenAAmount / price).
// - From v0.0.4: Fixed E2: Removed redundant decimal conversion, relying on OMFListingTemplate.getPrice().
// - Side effects: Ensures correct decimal handling for tax-on-transfer tokens; improves robustness for non-18 decimal tokens.

import "./OMF-Shared.sol";

abstract contract OMFSettlementLibrary {
    using OMFShared.SafeERC20 for IERC20;

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
        OMFShared.IOMFListing listing;
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

    function computeOrderAmounts(
        uint256 price,
        uint256 pending,
        bool isBuy,
        uint8 token0Decimals,
        uint8 baseTokenDecimals
    ) public pure returns (uint256 baseTokenAmount, uint256 token0Amount) {
        uint256 normalizedPending = OMFShared.normalize(pending, isBuy ? baseTokenDecimals : token0Decimals);
        if (isBuy) {
            baseTokenAmount = normalizedPending;
            token0Amount = (baseTokenAmount * 1e18) / price;
            baseTokenAmount = OMFShared.denormalize(baseTokenAmount, baseTokenDecimals);
            token0Amount = OMFShared.denormalize(token0Amount, token0Decimals);
        } else {
            token0Amount = normalizedPending;
            baseTokenAmount = (token0Amount * price) / 1e18;
            token0Amount = OMFShared.denormalize(token0Amount, token0Decimals);
            baseTokenAmount = OMFShared.denormalize(baseTokenAmount, baseTokenDecimals);
        }
    }

    function performTransactionAndAdjust(
        OMFShared.IOMFListing listing,
        address proxy,
        IERC20 baseToken,
        uint256 amount,
        address recipient,
        uint256 price,
        bool isBuy,
        uint8 decimals
    ) public returns (uint256 actualReceived, uint256 adjustedValue) {
        uint256 rawAmount = OMFShared.denormalize(amount, decimals);
        uint256 preBalance = baseToken.balanceOf(recipient);
        listing.transact(proxy, address(baseToken), rawAmount, recipient);
        uint256 postBalance = baseToken.balanceOf(recipient);
        actualReceived = OMFShared.normalize(postBalance - preBalance, decimals);
        adjustedValue = isBuy ? (actualReceived * price) / 1e18 : (actualReceived * 1e18) / price;
    }

    function prepBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        uint256[] memory pendingOrders = orderIds.length > 0 ? orderIds : listing.pendingBuyOrdersView();
        SettlementData memory data;
        data.orderIds = pendingOrders;
        data.updates = new PreparedUpdate[](pendingOrders.length);
        data.token0 = listing.token0();
        data.baseToken = listing.baseToken();

        PrepState memory state = PrepState(listing.getPrice(), listing);
        processPrepBuyOrders(data, pendingOrders, state);

        if (data.orderCount < data.updates.length) {
            PreparedUpdate[] memory resized = new PreparedUpdate[](data.orderCount);
            for (uint256 i = 0; i < data.orderCount; i++) {
                resized[i] = data.updates[i];
            }
            data.updates = resized;
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
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](data.orderCount + 1);
        uint8 baseTokenDecimals = IERC20(data.baseToken).decimals();
        uint8 token0Decimals = IERC20(data.token0).decimals();
        ExecutionState memory state = ExecutionState(0, listing.getPrice(), IERC20(data.baseToken));

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            processBuyOrder(listing, updates, i, update, state, proxy, token0Decimals, baseTokenDecimals);
        }

        if (data.orderCount > 0) {
            updates[data.orderCount] = OMFShared.UpdateType(0, 3, state.totalBaseToken, data.baseToken, address(0), 0, 0); // yVolume
            listing.update(proxy, updates);
        }
    }

    function processBuyOrder(
        OMFShared.IOMFListing listing,
        OMFShared.UpdateType[] memory updates,
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
        updates[index] = OMFShared.UpdateType(
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
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        uint256[] memory pendingOrders = orderIds.length > 0 ? orderIds : listing.pendingSellOrdersView();
        SettlementData memory data;
        data.orderIds = pendingOrders;
        data.updates = new PreparedUpdate[](pendingOrders.length);
        data.token0 = listing.token0();
        data.baseToken = listing.baseToken();

        PrepState memory state = PrepState(listing.getPrice(), listing);
        processPrepSellOrders(data, pendingOrders, state);

        if (data.orderCount < data.updates.length) {
            PreparedUpdate[] memory resized = new PreparedUpdate[](data.orderCount);
            for (uint256 i = 0; i < data.orderCount; i++) {
                resized[i] = data.updates[i];
            }
            data.updates = resized;
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
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](data.orderCount + 1);
        uint8 baseTokenDecimals = IERC20(data.baseToken).decimals();
        uint8 token0Decimals = IERC20(data.token0).decimals();
        ExecutionState memory state = ExecutionState(0, listing.getPrice(), IERC20(data.baseToken));

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            processSellOrder(listing, updates, i, update, state, proxy, token0Decimals, baseTokenDecimals);
        }

        if (data.orderCount > 0) {
            updates[data.orderCount] = OMFShared.UpdateType(0, 1, state.totalBaseToken, data.baseToken, address(0), 0, 0); // yBalance
            listing.update(proxy, updates);
        }
    }

    function processSellOrder(
        OMFShared.IOMFListing listing,
        OMFShared.UpdateType[] memory updates,
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
        updates[index] = OMFShared.UpdateType(
            2,
            update.orderId,
            pending > orderState.adjustedValue ? pending - orderState.adjustedValue : 0,
            address(0),
            recipientAddress,
            0,
            0
        );
    }

    function settleBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external {
        SettlementData memory data = prepBuyOrders(listingAddress, orderIds, listingAgent, proxy);
        executeBuyOrders(listingAddress, data, listingAgent, proxy);
    }

    function settleSellOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external {
        SettlementData memory data = prepSellOrders(listingAddress, orderIds, listingAgent, proxy);
        executeSellOrders(listingAddress, data, listingAgent, proxy);
    }
}