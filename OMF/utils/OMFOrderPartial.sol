// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.73 (Updated)
// Changes:
// - v0.0.73: Added prepAndTransfer to handle fee and transfers, updated prepOrderCore to accept actualNetAmount, implemented call tree to reduce stack usage in OMFRouter.sol createBuyOrder.
// - v0.0.72: Added OrderDetails, OrderUpdate structs, prepOrderCore, prepOrderAmounts, applyOrderUpdate for modular order creation.
// - v0.0.71: Added _handleFeeAndAdd to compute fee and call addFees, updated _handleFeeAndTransfer.

import "./OMFMainPartial.sol";

contract OMFOrderPartial is OMFMainPartial {
    struct OrderDetails {
        address recipientAddress; // Order recipient
        uint256 amount; // Input amount (denormalized)
        uint256 maxPrice; // Maximum price (normalized)
        uint256 minPrice; // Minimum price (normalized)
    }

    struct OrderUpdate {
        uint8 updateType; // 1 for buy, 2 for sell
        uint256 orderId; // Order identifier
        uint256 value; // Amount or status
        address addr; // Maker address
        address recipient; // Recipient address
        uint256 maxPrice; // Maximum price
        uint256 minPrice; // Minimum price
        uint256 amountSent; // Amount sent
    }

    function _transferFees(
        address tokenAddress,
        address listingAddress,
        uint256 feeAmount
    ) internal returns (uint256 feeReceived) {
        // Transfers fees to liquidity contract with pre/post balance checks
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        uint8 tokenDecimals = IERC20(tokenAddress).decimals();
        uint256 preBalance = IERC20(tokenAddress).balanceOf(liquidityAddr);
        IERC20(tokenAddress).transfer(liquidityAddr, feeAmount);
        uint256 postBalance = IERC20(tokenAddress).balanceOf(liquidityAddr);
        feeReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        require(feeReceived > 0, "No fees received by liquidity");
    }

    function _checkTransferAmount(
        address tokenAddress,
        address from,
        address to,
        uint256 inputAmount
    ) internal returns (uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers tokens to router and normalizes received amount
        uint8 tokenDecimals = IERC20(tokenAddress).decimals();
        uint256 preBalance = IERC20(tokenAddress).balanceOf(to);
        IERC20(tokenAddress).transferFrom(from, to, inputAmount);
        uint256 postBalance = IERC20(tokenAddress).balanceOf(to);
        amountReceived = postBalance > preBalance ? postBalance - preBalance : 0;
        normalizedReceived = amountReceived > 0 ? normalize(amountReceived, tokenDecimals) : 0;
        require(amountReceived > 0, "No tokens received");
    }

    function _handleFeeAndAdd(
        address tokenAddress,
        address listingAddress,
        uint256 inputAmount,
        bool isToken0
    ) internal returns (uint256 feeAmount) {
        // Calculates 0.05% fee and adds to liquidity contract
        feeAmount = (inputAmount * 5) / 10000; // 0.05% fee
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        try IOMFLiquidityTemplate(liquidityAddr).addFees(address(this), isToken0, feeAmount) {} catch {
            revert("Fee addition failed");
        }
    }

    function _handleFeeAndTransfer(
        address tokenAddress,
        address listingAddress,
        uint256 inputAmount,
        uint256 feeAmount
    ) internal returns (uint256 netAmount, uint256 actualNetAmount, uint256 amountReceived, uint256 normalizedReceived) {
        // Transfers fee to liquidity and principal to listing, returns amounts
        netAmount = inputAmount - feeAmount;
        require(netAmount > 0, "Net amount after fee is zero");
        (amountReceived, normalizedReceived) = _checkTransferAmount(
            tokenAddress,
            msg.sender,
            address(this),
            inputAmount
        );
        uint256 feeReceived = _transferFees(tokenAddress, listingAddress, feeAmount);
        // Transfer principal to listingAddress
        uint256 listingPreBalance = IERC20(tokenAddress).balanceOf(listingAddress);
        IERC20(tokenAddress).transfer(listingAddress, netAmount);
        uint256 listingPostBalance = IERC20(tokenAddress).balanceOf(listingAddress);
        actualNetAmount = listingPostBalance > listingPreBalance
            ? listingPostBalance - listingPreBalance
            : 0;
        require(actualNetAmount > 0, "No principal received by listing");
    }

    function prepAndTransfer(
        address listingAddress,
        address tokenAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal returns (uint256 actualNetAmount, uint256 orderId) {
        // Handles fee calculation, transfer, and initiates order update chain
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        bool isToken0 = tokenAddress == listingContract.token0View();
        uint256 feeAmount = _handleFeeAndAdd(tokenAddress, listingAddress, inputAmount, isToken0);
        uint256 netAmount;
        uint256 amountReceived;
        uint256 normalizedReceived;
        (netAmount, actualNetAmount, amountReceived, normalizedReceived) = _handleFeeAndTransfer(
            tokenAddress,
            listingAddress,
            inputAmount,
            feeAmount
        );
        OrderDetails memory details = OrderDetails({
            recipientAddress: msg.sender,
            amount: actualNetAmount,
            maxPrice: 0,
            minPrice: 0
        });
        OrderUpdate memory coreUpdate = prepOrderCore(listingAddress, details, actualNetAmount, isBuyOrder);
        applyOrderUpdate(listingAddress, coreUpdate, isBuyOrder);
        orderId = coreUpdate.orderId;
        OrderUpdate memory amountsUpdate = prepOrderAmounts(listingAddress, details, orderId, isBuyOrder);
        applyOrderUpdate(listingAddress, amountsUpdate, isBuyOrder);
    }

    function prepOrderCore(
        address listingAddress,
        OrderDetails memory details,
        uint256 actualNetAmount,
        bool isBuyOrder
    ) internal returns (OrderUpdate memory) {
        // Prepares core order update
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint8 tokenDecimals = isBuyOrder ? listingContract.baseTokenDecimalsView() : listingContract.decimals0View();
        uint256 normalizedAmount = normalize(actualNetAmount, tokenDecimals);
        OrderUpdate memory update = OrderUpdate({
            updateType: isBuyOrder ? 1 : 2,
            orderId: 0,
            value: normalizedAmount,
            addr: msg.sender,
            recipient: details.recipientAddress,
            maxPrice: details.maxPrice,
            minPrice: details.minPrice,
            amountSent: 0
        });
        return update;
    }

    function prepOrderAmounts(
        address listingAddress,
        OrderDetails memory details,
        uint256 orderId,
        bool isBuyOrder
    ) internal view returns (OrderUpdate memory) {
        // Prepares amounts update for order
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint8 tokenDecimals = isBuyOrder ? listingContract.baseTokenDecimalsView() : listingContract.decimals0View();
        uint256 normalizedAmount = normalize(details.amount, tokenDecimals);
        return OrderUpdate({
            updateType: isBuyOrder ? 1 : 2,
            orderId: orderId,
            value: normalizedAmount,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
    }

    function applyOrderUpdate(
        address listingAddress,
        OrderUpdate memory update,
        bool isBuyOrder
    ) internal {
        // Applies a single order update
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        IOMFListingTemplate.UpdateType[] memory updates = new IOMFListingTemplate.UpdateType[](1);
        updates[0] = IOMFListingTemplate.UpdateType({
            updateType: update.updateType,
            structId: update.orderId == 0 ? 0 : 2, // Core for new order, Amounts for existing
            index: update.orderId,
            value: update.value,
            addr: update.addr,
            recipient: update.recipient,
            maxPrice: update.maxPrice,
            minPrice: update.minPrice,
            amountSent: update.amountSent
        });
        listingContract.update(address(this), updates);
    }
}