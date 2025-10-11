/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025

 Version: 0.0.2
 Changes:
 - 0.0.2 (11/10): Removed unused local variables and params.
 - v0.0.1: Created MFPLiquidRouter.sol from CCLiquidRouter.sol v0.0.25, removed Uniswap functionality, aligned with MFPLiquidPartial.sol v0.0.46 for new impact price calculation.
*/

pragma solidity ^0.8.2;

import "./utils/MFPLiquidPartial.sol";

contract MFPLiquidRouter is MFPLiquidPartial {
    event NoPendingOrders(address indexed listingAddress, bool isBuyOrder);

    struct HistoricalUpdateContext {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    function _createHistoricalUpdate(address listingAddress, ICCListing listingContract) private {
    // Creates historical data update using live data
    HistoricalUpdateContext memory context;
    uint256 historicalLength = listingContract.historicalDataLengthView();
    if (historicalLength > 0) {
        ICCListing.HistoricalData memory historicalData = listingContract.getHistoricalDataView(historicalLength - 1);
        context.xVolume = historicalData.xVolume;
        context.yVolume = historicalData.yVolume;
    }
    ICCListing.HistoricalUpdate memory update = ICCListing.HistoricalUpdate({
        price: listingContract.prices(0),
        xBalance: 0,
        yBalance: 0,
        xVolume: context.xVolume,
        yVolume: context.yVolume,
        timestamp: block.timestamp
    });
    ICCListing.BuyOrderUpdate[] memory buyUpdates = new ICCListing.BuyOrderUpdate[](0);
    ICCListing.SellOrderUpdate[] memory sellUpdates = new ICCListing.SellOrderUpdate[](0);
    ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
    ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](1);
    historicalUpdates[0] = update;
    try listingContract.ccUpdate(buyUpdates, sellUpdates, balanceUpdates, historicalUpdates) {
    } catch Error(string memory reason) {
        emit UpdateFailed(listingAddress, string(abi.encodePacked("Historical update failed: ", reason)));
    }
}

    function settleBuyLiquid(address listingAddress, uint256 maxIterations, uint256 step) external onlyValidListing(listingAddress) nonReentrant {
    // Settles buy orders for msg.sender
    ICCListing listingContract = ICCListing(listingAddress);
    uint256[] memory pendingOrders = listingContract.makerPendingOrdersView(msg.sender);
    if (pendingOrders.length == 0 || step >= pendingOrders.length) {
        emit NoPendingOrders(listingAddress, true);
        return;
    }
    if (pendingOrders.length > 0) {
        _createHistoricalUpdate(listingAddress, listingContract);
    }
    bool success = _processOrderBatch(listingAddress, maxIterations, true, step);
    if (!success) {
        emit UpdateFailed(listingAddress, "Buy order batch processing failed");
    }
}

    function settleSellLiquid(address listingAddress, uint256 maxIterations, uint256 step) external onlyValidListing(listingAddress) nonReentrant {
    // Settles sell orders for msg.sender
    ICCListing listingContract = ICCListing(listingAddress);
    uint256[] memory pendingOrders = listingContract.makerPendingOrdersView(msg.sender);
    if (pendingOrders.length == 0 || step >= pendingOrders.length) {
        emit NoPendingOrders(listingAddress, false);
        return;
    }
    if (pendingOrders.length > 0) {
        _createHistoricalUpdate(listingAddress, listingContract);
    }
    bool success = _processOrderBatch(listingAddress, maxIterations, false, step);
    if (!success) {
        emit UpdateFailed(listingAddress, "Sell order batch processing failed");
    }
}
}