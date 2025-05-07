// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.1.0
// Most Recent Changes:
// - Renamed from LiquidPartial.sol to OrderPartial.sol.
// - Moved all OMFRouter.sol contents (createBuyOrder, createSellOrder, tempOrderUpdates, liquidExecutionStates) to OrderPartial.
// - Inherits MainPartial.sol to access agent, transferToken, normalizeAndFee, etc.
// - Ensured listingAddress is passed as a parameter in all functions (e.g., createBuyOrder).
// - Removed unnecessary SafeERC20 usage in view functions.
// - Maintained compatibility with MainPartial structs (UpdateType, TempOrderUpdate, etc.).

import "./MainPartial.sol";

contract OrderPartial is MainPartial {
    using SafeERC20 for IERC20;

    mapping(uint256 => TempOrderUpdate) internal tempOrderUpdates;
    mapping(uint256 => LiquidExecutionState) internal liquidExecutionStates;

    function createBuyOrder(
        address listingAddress,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        BuyOrderDetails memory details = BuyOrderDetails(recipient, amount, maxPrice, minPrice);
        PrimaryOrderUpdate memory coreUpdate = prepBuyOrderCore(listingAddress, details);
        PrimaryOrderUpdate memory pricingUpdate = prepBuyOrderPricing(listingAddress, details, coreUpdate.orderId);
        PrimaryOrderUpdate memory amountsUpdate = prepBuyOrderAmounts(listingAddress, details, coreUpdate.orderId);
        applySinglePrimaryUpdate(listingAddress, coreUpdate, true);
        applySinglePrimaryUpdate(listingAddress, pricingUpdate, true);
        applySinglePrimaryUpdate(listingAddress, amountsUpdate, true);
        SecondaryOrderUpdate memory secondaryUpdate = prepareSingleSecondaryUpdate(listingAddress, coreUpdate.orderId, true);
        applySingleSecondaryUpdate(listingAddress, secondaryUpdate, true);
    }

    function createSellOrder(
        address listingAddress,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        (bool isValid, , , ) = IOMF(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing");
        SellOrderDetails memory details = SellOrderDetails(recipient, amount, maxPrice, minPrice);
        PrimaryOrderUpdate memory coreUpdate = prepSellOrderCore(listingAddress, details);
        PrimaryOrderUpdate memory pricingUpdate = prepSellOrderPricing(listingAddress, details, coreUpdate.orderId);
        PrimaryOrderUpdate memory amountsUpdate = prepSellOrderAmounts(listingAddress, details, coreUpdate.orderId);
        applySinglePrimaryUpdate(listingAddress, coreUpdate, false);
        applySinglePrimaryUpdate(listingAddress, pricingUpdate, false);
        applySinglePrimaryUpdate(listingAddress, amountsUpdate, false);
        SecondaryOrderUpdate memory secondaryUpdate = prepareSingleSecondaryUpdate(listingAddress, coreUpdate.orderId, false);
        applySingleSecondaryUpdate(listingAddress, secondaryUpdate, false);
    }

    function prepBuyOrderCore(
        address listingAddress,
        BuyOrderDetails memory details
    ) internal returns (PrimaryOrderUpdate memory) {
        (, , , address baseToken) = IOMF(agent).validateListing(listingAddress);
        (uint256 orderId, , ) = transferAndPrepareOrder(baseToken, listingAddress, details.amount);
        tempOrderUpdates[orderId] = TempOrderUpdate({
            orderId: orderId,
            value: 0,
            recipient: details.recipient,
            isBuy: true
        });
        return PrimaryOrderUpdate({
            updateType: 1,
            structId: 0,
            orderId: orderId,
            pendingValue: 0,
            recipient: details.recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    function prepBuyOrderPricing(
        address listingAddress,
        BuyOrderDetails memory details,
        uint256 orderId
    ) internal pure returns (PrimaryOrderUpdate memory) {
        return PrimaryOrderUpdate({
            updateType: 1,
            structId: 1,
            orderId: orderId,
            pendingValue: 0,
            recipient: details.recipient,
            maxPrice: details.maxPrice,
            minPrice: details.minPrice
        });
    }

    function prepBuyOrderAmounts(
        address listingAddress,
        BuyOrderDetails memory details,
        uint256 orderId
    ) internal returns (PrimaryOrderUpdate memory) {
        (, , , address baseToken) = IOMF(agent).validateListing(listingAddress);
        (uint256 normalized, , uint256 principal) = normalizeAndFee(baseToken, details.amount);
        tempOrderUpdates[orderId].value = principal;
        return PrimaryOrderUpdate({
            updateType: 1,
            structId: 2,
            orderId: orderId,
            pendingValue: principal,
            recipient: details.recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    function prepSellOrderCore(
        address listingAddress,
        SellOrderDetails memory details
    ) internal returns (PrimaryOrderUpdate memory) {
        (, , address token0, ) = IOMF(agent).validateListing(listingAddress);
        (uint256 orderId, , ) = transferAndPrepareOrder(token0, listingAddress, details.amount);
        tempOrderUpdates[orderId] = TempOrderUpdate({
            orderId: orderId,
            value: 0,
            recipient: details.recipient,
            isBuy: false
        });
        return PrimaryOrderUpdate({
            updateType: 2,
            structId: 0,
            orderId: orderId,
            pendingValue: 0,
            recipient: details.recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    function prepSellOrderPricing(
        address listingAddress,
        SellOrderDetails memory details,
        uint256 orderId
    ) internal pure returns (PrimaryOrderUpdate memory) {
        return PrimaryOrderUpdate({
            updateType: 2,
            structId: 1,
            orderId: orderId,
            pendingValue: 0,
            recipient: details.recipient,
            maxPrice: details.maxPrice,
            minPrice: details.minPrice
        });
    }

    function prepSellOrderAmounts(
        address listingAddress,
        SellOrderDetails memory details,
        uint256 orderId
    ) internal returns (PrimaryOrderUpdate memory) {
        (, , address token0, ) = IOMF(agent).validateListing(listingAddress);
        (uint256 normalized, , uint256 principal) = normalizeAndFee(token0, details.amount);
        tempOrderUpdates[orderId].value = principal;
        return PrimaryOrderUpdate({
            updateType: 2,
            structId: 2,
            orderId: orderId,
            pendingValue: principal,
            recipient: details.recipient,
            maxPrice: 0,
            minPrice: 0
        });
    }

    function applySinglePrimaryUpdate(
        address listingAddress,
        PrimaryOrderUpdate memory primary,
        bool isBuy
    ) internal {
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType({
            updateType: primary.updateType,
            structId: primary.structId,
            index: primary.orderId,
            value: primary.pendingValue,
            addr: msg.sender,
            recipient: primary.recipient,
            maxPrice: primary.maxPrice,
            minPrice: primary.minPrice
        });
        IOMFListing(listingAddress).update(updates);
        if (primary.structId == 0) emit OrderCreated(primary.orderId, isBuy);
    }

    function prepareSingleSecondaryUpdate(
        address listingAddress,
        uint256 orderId,
        bool isBuy
    ) internal view returns (SecondaryOrderUpdate memory) {
        TempOrderUpdate memory temp = tempOrderUpdates[orderId];
        require(temp.orderId == orderId, "Invalid temp update");
        return SecondaryOrderUpdate({
            updateType: 3,
            structId: 0,
            orderId: 0,
            filledValue: temp.value,
            historicalPrice: 0
        });
    }

    function applySingleSecondaryUpdate(
        address listingAddress,
        SecondaryOrderUpdate memory secondary,
        bool isBuy
    ) internal {
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType({
            updateType: secondary.updateType,
            structId: 0,
            index: 0,
            value: secondary.filledValue,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0
        });
        IOMFListing(listingAddress).update(updates);
        delete tempOrderUpdates[secondary.orderId];
    }
}