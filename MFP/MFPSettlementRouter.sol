// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.0
// Changes:
// - v0.1.0: Initial implementation, replaces Uniswap V2 with direct transfers from listing template. Added impact price and partial settlement logic per instructions. Compatible with CCListingTemplate.sol (v0.3.9), CCMainPartial.sol (v0.1.5), MFPSettlementPartial.sol (v0.1.0).

import "./utils/MFPSettlementPartial.sol";

contract MFPSettlementRouter is MFPSettlementPartial {
    struct SettlementState {
        address listingAddress;
        bool isBuyOrder;
        uint256 step;
        uint256 maxIterations;
    }

    function _validateOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuyOrder,
        ICCListing listingContract
    ) internal view returns (OrderContext memory context) {
        // Validates order details and pricing
        context.orderId = orderId;
        (context.pending, , ) = isBuyOrder ? listingContract.getBuyOrderAmounts(orderId) : listingContract.getSellOrderAmounts(orderId);
        (, , context.status) = isBuyOrder ? listingContract.getBuyOrderCore(orderId) : listingContract.getSellOrderCore(orderId);
        if (context.pending == 0 || context.status != 1) {
            revert(string(abi.encodePacked("Invalid order ", uint2str(orderId), ": no pending amount or status")));
        }
        if (!_checkPricing(listingAddress, orderId, isBuyOrder, context.pending)) {
            revert(string(abi.encodePacked("Price out of bounds for order ", uint2str(orderId))));
        }
    }

    function _processOrder(
        address listingAddress,
        bool isBuyOrder,
        ICCListing listingContract,
        OrderContext memory context,
        SettlementContext memory settlementContext
    ) internal returns (OrderContext memory) {
        // Processes order; updates prepared in MFPSettlementPartial.sol
        if (isBuyOrder) {
            context.buyUpdates = _processBuyOrder(listingAddress, context.orderId, listingContract, settlementContext);
        } else {
            context.sellUpdates = _processSellOrder(listingAddress, context.orderId, listingContract, settlementContext);
        }
        return context;
    }

    function _updateOrder(
        ICCListing listingContract,
        OrderContext memory context,
        bool isBuyOrder
    ) internal returns (bool success, string memory reason) {
        // Applies updates via ccUpdate
        if (isBuyOrder && context.buyUpdates.length == 0 || !isBuyOrder && context.sellUpdates.length == 0) {
            return (false, "");
        }
        try listingContract.ccUpdate(
            isBuyOrder ? context.buyUpdates : new ICCListing.BuyOrderUpdate[](0),
            isBuyOrder ? new ICCListing.SellOrderUpdate[](0) : context.sellUpdates,
            new ICCListing.BalanceUpdate[](0),
            new ICCListing.HistoricalUpdate[](0)
        ) {
            (, , context.status) = isBuyOrder
                ? listingContract.getBuyOrderCore(context.orderId)
                : listingContract.getSellOrderCore(context.orderId);
            if (context.status == 0 || context.status == 3) {
                return (false, "");
            }
            return (true, "");
        } catch Error(string memory updateReason) {
            return (false, string(abi.encodePacked("Update failed for order ", uint2str(context.orderId), ": ", updateReason)));
        }
    }

    function _initSettlement(
        address listingAddress,
        bool isBuyOrder,
        uint256 step,
        ICCListing listingContract
    ) private view returns (SettlementState memory state, uint256[] memory orderIds) {
        // Initializes settlement state and fetches order IDs
        state = SettlementState({
            listingAddress: listingAddress,
            isBuyOrder: isBuyOrder,
            step: step,
            maxIterations: 0
        });
        orderIds = isBuyOrder ? listingContract.pendingBuyOrdersView() : listingContract.pendingSellOrdersView();
        if (orderIds.length == 0 || step >= orderIds.length) {
            revert("No pending orders or invalid step");
        }
    }

    function _createHistoricalEntry(
        ICCListing listingContract
    ) private returns (ICCListing.HistoricalUpdate[] memory historicalUpdates) {
        // Creates historical data entry
        (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
        uint256 price = listingContract.prices(0);
        uint256 xVolume = 0;
        uint256 yVolume = 0;
        uint256 historicalLength = listingContract.historicalDataLengthView();
        if (historicalLength > 0) {
            ICCListing.HistoricalData memory historicalData = listingContract.getHistoricalDataView(historicalLength - 1);
            xVolume = historicalData.xVolume;
            yVolume = historicalData.yVolume;
        }
        historicalUpdates = new ICCListing.HistoricalUpdate[](1);
        historicalUpdates[0] = ICCListing.HistoricalUpdate({
            price: price,
            xBalance: xBalance,
            yBalance: yBalance,
            xVolume: xVolume,
            yVolume: yVolume,
            timestamp: block.timestamp
        });
        try listingContract.ccUpdate(
            new ICCListing.BuyOrderUpdate[](0),
            new ICCListing.SellOrderUpdate[](0),
            new ICCListing.BalanceUpdate[](0),
            historicalUpdates
        ) {} catch Error(string memory updateReason) {
            revert(string(abi.encodePacked("Failed to create historical data entry: ", updateReason)));
        }
    }

    function _processOrderBatch(
        SettlementState memory state,
        uint256[] memory orderIds,
        ICCListing listingContract,
        SettlementContext memory settlementContext
    ) private returns (uint256 count) {
        // Processes batch of orders
        count = 0;
        for (uint256 i = state.step; i < orderIds.length && count < state.maxIterations; i++) {
            OrderContext memory context = _validateOrder(state.listingAddress, orderIds[i], state.isBuyOrder, listingContract);
            context = _processOrder(state.listingAddress, state.isBuyOrder, listingContract, context, settlementContext);
            (bool success, string memory updateReason) = _updateOrder(listingContract, context, state.isBuyOrder);
            if (!success && bytes(updateReason).length > 0) {
                revert(updateReason);
            }
            if (success) {
                count++;
            }
        }
    }

    function settleOrders(
        address listingAddress,
        uint256 step,
        uint256 maxIterations,
        bool isBuyOrder
    ) external nonReentrant onlyValidListing(listingAddress) returns (string memory reason) {
        // Iterates over pending orders, completes each order fully
        ICCListing listingContract = ICCListing(listingAddress);
        SettlementContext memory settlementContext = SettlementContext({
            tokenA: listingContract.tokenA(),
            tokenB: listingContract.tokenB(),
            decimalsA: listingContract.decimalsA(),
            decimalsB: listingContract.decimalsB(),
            uniswapV2Pair: address(0) // No Uniswap V2 pair needed
        });
        (SettlementState memory state, uint256[] memory orderIds) = _initSettlement(listingAddress, isBuyOrder, step, listingContract);
        state.maxIterations = maxIterations;
        _createHistoricalEntry(listingContract);
        uint256 count = _processOrderBatch(state, orderIds, listingContract, settlementContext);
        if (count == 0) {
            return "No orders settled: price out of range or transfer failure";
        }
        return "";
    }
}