// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.22
// Changes:
// - Updated executeBuyOrder and executeSellOrder to use revised calculateImpactPrice with buy/sell-specific logic.
// - Aligned settlement calculations: amount * impactPrice for buy, amount / impactPrice for sell.
// - Preserved all prior changes from v0.0.21.

import "./MFPOrderPartial.sol";

contract MFPSettlementPartial is MFPOrderPartial {
    function prepBuyLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) internal returns (IMFPListing.ListingUpdateType[] memory) {
        require(orderIds.length == amounts.length, "Array length mismatch");
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            try this.executeBuyOrder(listingAddress, orderIds[i], amounts[i]) returns (IMFPListing.ListingUpdateType[] memory updates) {
                if (updates.length == 0) {
                    continue;
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[index++] = updates[j];
                }
            } catch {
                continue;
            }
        }
        IMFPListing.ListingUpdateType[] memory finalUpdates = new IMFPListing.ListingUpdateType[](index);
        for (uint256 i = 0; i < index; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        return finalUpdates;
    }

    function prepSellLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) internal returns (IMFPListing.ListingUpdateType[] memory) {
        require(orderIds.length == amounts.length, "Array length mismatch");
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            try this.executeSellOrder(listingAddress, orderIds[i], amounts[i]) returns (IMFPListing.ListingUpdateType[] memory updates) {
                if (updates.length == 0) {
                    continue;
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[index++] = updates[j];
                }
            } catch {
                continue;
            }
        }
        IMFPListing.ListingUpdateType[] memory finalUpdates = new IMFPListing.ListingUpdateType[](index);
        for (uint256 i = 0; i < index; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        return finalUpdates;
    }

    function executeBuyLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) internal {
        IMFPListing.ListingUpdateType[] memory updates = prepBuyLiquid(listingAddress, orderIds, amounts);
        if (updates.length > 0) {
            IMFPListing(listingAddress).update(updates);
        }
    }

    function executeSellLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) internal {
        IMFPListing.ListingUpdateType[] memory updates = prepSellLiquid(listingAddress, orderIds, amounts);
        if (updates.length > 0) {
            IMFPListing(listingAddress).update(updates);
        }
    }

    function executeBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) internal {
        require(orderIds.length == amounts.length, "Array length mismatch");
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            try this.executeBuyOrder(listingAddress, orderIds[i], amounts[i]) returns (IMFPListing.ListingUpdateType[] memory updates) {
                if (updates.length == 0) {
                    continue;
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[index++] = updates[j];
                }
            } catch {
                continue;
            }
        }
        IMFPListing.ListingUpdateType[] memory finalUpdates = new IMFPListing.ListingUpdateType[](index);
        for (uint256 i = 0; i < index; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (index > 0) {
            IMFPListing(listingAddress).update(finalUpdates);
        }
    }

    function executeSellOrders(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) internal {
        require(orderIds.length == amounts.length, "Array length mismatch");
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            try this.executeSellOrder(listingAddress, orderIds[i], amounts[i]) returns (IMFPListing.ListingUpdateType[] memory updates) {
                if (updates.length == 0) {
                    continue;
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[index++] = updates[j];
                }
            } catch {
                continue;
            }
        }
        IMFPListing.ListingUpdateType[] memory finalUpdates = new IMFPListing.ListingUpdateType[](index);
        for (uint256 i = 0; i < index; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (index > 0) {
            IMFPListing(listingAddress).update(finalUpdates);
        }
    }

    function executeBuyOrder(
        address listingAddress,
        uint256 orderId,
        uint256 amount
    ) public override returns (IMFPListing.ListingUpdateType[] memory) {
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        uint256 maxPrice;
        uint256 minPrice;
        uint256 xBalance;
        uint256 yBalance;
        {
            (maxPrice, minPrice) = IMFPListing(listingAddress).buyOrderPricingView(orderId);
            (xBalance, yBalance,,) = IMFPListing(listingAddress).volumeBalances(listingId);
        }
        uint256 impactPrice = calculateImpactPrice(amount, xBalance, yBalance, true);
        if (impactPrice < minPrice || impactPrice > maxPrice) {
            return new IMFPListing.ListingUpdateType[](0);
        }
        // Settlement: amount * impactPrice for tokenA received
        uint256 amountOut = (amount * impactPrice) / 1e18;
        IMFPListing.ListingUpdateType[] memory core = executeBuyOrderCore(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory pricing = executeBuyOrderPricing(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory amounts = executeBuyOrderAmounts(listingId, orderId, amountOut);
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
    ) public override returns (IMFPListing.ListingUpdateType[] memory) {
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        uint256 maxPrice;
        uint256 minPrice;
        uint256 xBalance;
        uint256 yBalance;
        {
            (maxPrice, minPrice) = IMFPListing(listingAddress).sellOrderPricingView(orderId);
            (xBalance, yBalance,,) = IMFPListing(listingAddress).volumeBalances(listingId);
        }
        uint256 impactPrice = calculateImpactPrice(amount, xBalance, yBalance, false);
        if (impactPrice < minPrice || impactPrice > maxPrice) {
            return new IMFPListing.ListingUpdateType[](0);
        }
        // Settlement: amount / impactPrice for tokenB received
        uint256 amountOut = (amount * 1e18) / impactPrice;
        IMFPListing.ListingUpdateType[] memory core = executeSellOrderCore(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory pricing = executeSellOrderPricing(listingId, orderId);
        IMFPListing.ListingUpdateType[] memory amounts = executeSellOrderAmounts(listingId, orderId, amountOut);
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](core.length + pricing.length + amounts.length);
        uint256 index = 0;
        for (uint256 i = 0; i < core.length; i++) updates[index++] = core[i];
        for (uint256 i = 0; i < pricing.length; i++) updates[index++] = pricing[i];
        for (uint256 i = 0; i < amounts.length; i++) updates[index++] = amounts[i];
        return updates;
    }

    function processOrder(
        address listingAddress,
        uint256 orderId,
        uint256 amount,
        bool isBuy
    ) internal returns (IMFPListing.ListingUpdateType[] memory) {
        return isBuy
            ? executeBuyOrder(listingAddress, orderId, amount)
            : executeSellOrder(listingAddress, orderId, amount);
    }
}