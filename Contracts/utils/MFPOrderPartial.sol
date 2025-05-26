// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.20
// Changes:
// - Preserved all prior changes from v0.0.20.
// - No changes required for override or visibility issues as clearSingleOrder and clearOrders are already public virtual.

import "./MFPMainPartial.sol";

contract MFPOrderPartial is MFPMainPartial {
    event OrderCreated(address indexed listingAddress, address indexed maker, uint256 amount, bool isBuy);
    event OrderCancelled(address indexed listingAddress, uint256 orderId);

    function prepBuyOrderCore(
        uint256 listingId,
        uint256 orderId,
        address maker,
        address recipient
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(1, 0, orderId, 0, maker, recipient, 0, 0);
        return updates;
    }

    function prepBuyOrderPricing(
        uint256 listingId,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(1, 1, orderId, 0, address(0), address(0), maxPrice, minPrice);
        return updates;
    }

    function prepBuyOrderAmounts(
        uint256 listingId,
        uint256 orderId,
        uint256 amount
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(1, 2, orderId, amount, address(0), address(0), 0, 0);
        return updates;
    }

    function prepSellOrderCore(
        uint256 listingId,
        uint256 orderId,
        address maker,
        address recipient
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(2, 0, orderId, 0, maker, recipient, 0, 0);
        return updates;
    }

    function prepSellOrderPricing(
        uint256 listingId,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(2, 1, orderId, 0, address(0), address(0), maxPrice, minPrice);
        return updates;
    }

    function prepSellOrderAmounts(
        uint256 listingId,
        uint256 orderId,
        uint256 amount
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(2, 2, orderId, amount, address(0), address(0), 0, 0);
        return updates;
    }

    function executeBuyOrderCore(
        uint256 listingId,
        uint256 orderId
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        (address maker, address recipient, uint8 status) = IMFPListing(msg.sender).buyOrderCoreView(orderId);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(1, 0, orderId, 0, maker, recipient, 0, 0);
        return updates;
    }

    function executeBuyOrderPricing(
        uint256 listingId,
        uint256 orderId
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        (uint256 maxPrice, uint256 minPrice) = IMFPListing(msg.sender).buyOrderPricingView(orderId);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(1, 1, orderId, 0, address(0), address(0), maxPrice, minPrice);
        return updates;
    }

    function executeBuyOrderAmounts(
        uint256 listingId,
        uint256 orderId,
        uint256 amount
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(1, 2, orderId, amount, address(0), address(0), 0, 0);
        return updates;
    }

    function executeSellOrderCore(
        uint256 listingId,
        uint256 orderId
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        (address maker, address recipient, uint8 status) = IMFPListing(msg.sender).sellOrderCoreView(orderId);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(2, 0, orderId, 0, maker, recipient, 0, 0);
        return updates;
    }

    function executeSellOrderPricing(
        uint256 listingId,
        uint256 orderId
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        (uint256 maxPrice, uint256 minPrice) = IMFPListing(msg.sender).sellOrderPricingView(orderId);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(2, 1, orderId, 0, address(0), address(0), maxPrice, minPrice);
        return updates;
    }

    function executeSellOrderAmounts(
        uint256 listingId,
        uint256 orderId,
        uint256 amount
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(2, 2, orderId, amount, address(0), address(0), 0, 0);
        return updates;
    }

    function executeBuyOrder(
        address listingAddress,
        uint256 orderId,
        uint256 amount
    ) public virtual returns (IMFPListing.ListingUpdateType[] memory) {
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory core = executeBuyOrderCore(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory pricing = executeBuyOrderPricing(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory amounts = executeBuyOrderAmounts(listingId, orderId, amount);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](core.length + pricing.length + amounts.length);
        uint256 index = 0;
        for (uint256 i = 0; i < core.length; i++) updates[index++] = core[i];
        for (uint256 i = 0; i < pricing.length; i++) updates[index++] = pricing[i];
        for (uint256 i = 0; i < amounts.length; i++) updates[index++] = amounts[i];
        return updates;
    }

    function executeSellOrder(
        address listingAddress,
        uint256 orderId,
        uint256 amount
    ) public virtual returns (IMFPListing.ListingUpdateType[] memory) {
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory core = executeSellOrderCore(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory pricing = executeSellOrderPricing(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory amounts = executeSellOrderAmounts(listingId, orderId, amount);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](core.length + pricing.length + amounts.length);
        uint256 index = 0;
        for (uint256 i = 0; i < core.length; i++) updates[index++] = core[i];
        for (uint256 i = 0; i < pricing.length; i++) updates[index++] = pricing[i];
        for (uint256 i = 0; i < amounts.length; i++) updates[index++] = amounts[i];
        return updates;
    }

    function clearSingleOrder(address listingAddress, uint256 orderId) public virtual {
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(0, 0, orderId, 0, address(0), address(0), 0, 0);
        IMFPListing(listingAddress).update(updates);
        emit OrderCancelled(listingAddress, orderId);
    }

    function clearOrders(address listingAddress) public virtual {
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](1);
        updates[0] = IMFPListing.ListingUpdateType(0, 0, 0, 0, address(0), address(0), 0, 0);
        IMFPListing(listingAddress).update(updates);
        emit OrderCancelled(listingAddress, 0);
    }
}