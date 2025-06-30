// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.67 (Updated)
// Changes:
// - v0.0.67: Removed ETH handling in _checkAndTransferPrincipal and _updateLiquidity to use only ERC-20 tokens for consistency with OMF’s ERC-20-only requirement.
// - v0.0.66: Removed _transferFees as it was moved to OMFOrderPartial.sol as an order creation helper to resolve DeclarationError.
// - v0.0.65: Updated to use interfaces from OMFMainPartial.sol; retained listingContract.volumeBalanceView().

import "./OMFOrderPartial.sol";

contract OMFSettlementPartial is OMFOrderPartial {
    struct OrderContext {
        IOMFListingTemplate listingContract; // Listing contract interface
        address tokenIn; // Input token address
        address tokenOut; // Output token address
        address liquidityAddr; // Liquidity contract address
    }

    struct SellOrderUpdateContext {
        address makerAddress; // Order creator
        address recipient; // Order recipient
        uint8 status; // Order status
        uint256 amountReceived; // Received amount (denormalized)
        uint256 normalizedReceived; // Received amount (normalized)
        uint256 amountSent; // Amount sent to recipient
    }

    struct BuyOrderUpdateContext {
        address makerAddress; // Order creator
        address recipient; // Order recipient
        uint8 status; // Order status
        uint256 amountReceived; // Received amount (denormalized)
        uint256 normalizedReceived; // Received amount (normalized)
        uint256 amountSent; // Amount sent to recipient
    }

    struct PrepOrderUpdateResult {
        address makerAddress; // Order creator
        address recipientAddress; // Order recipient
        uint8 orderStatus; // Order status
        uint256 amountReceived; // Received amount (denormalized)
        uint256 normalizedReceived; // Received amount (normalized)
        uint256 amountSent; // Amount sent to recipient
        uint8 tokenDecimals; // Output token decimals
    }

    function _checkAndTransferPrincipal(
        address listingAddress,
        address tokenIn,
        uint256 inputAmount,
        address liquidityAddr
    ) internal returns (uint256 actualAmount, uint8 tokenDecimals) {
        // Transfers principal amount to listing address with pre/post balance checks
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        tokenDecimals = IERC20(tokenIn).decimals();
        uint256 listingPreBalance = IERC20(tokenIn).balanceOf(listingAddress);
        IERC20(tokenIn).transfer(listingAddress, inputAmount);
        uint256 listingPostBalance = IERC20(tokenIn).balanceOf(listingAddress);
        actualAmount = listingPostBalance > listingPreBalance
            ? listingPostBalance - listingPreBalance
            : 0;
        require(actualAmount > 0, "No amount received by listing");
    }

    function _prepareLiquidityTransaction(
        address listingAddress,
        uint256 inputAmount,
        bool isBuyOrder
    ) internal view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        // Calculates output amount using oracle price and volume balances
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        (uint256 xBalance, uint256 yBalance, , ) = listingContract.volumeBalanceView();
        uint256 price = listingContract.getPrice();
        if (isBuyOrder) {
            require(yBalance >= inputAmount, "Insufficient y liquidity");
            tokenIn = listingContract.baseTokenView();
            tokenOut = listingContract.token0View();
            amountOut = (inputAmount * 1e18) / price; // USD to LINK: amount / price
        } else {
            require(xBalance >= inputAmount, "Insufficient x liquidity");
            tokenIn = listingContract.token0View();
            tokenOut = listingContract.baseTokenView();
            amountOut = (inputAmount * price) / 1e18; // LINK to USD: amount * price
        }
    }

    function _updateLiquidity(
        address listingAddress,
        address tokenIn,
        bool isX,
        uint256 inputAmount
    ) internal {
        // Updates liquidity pool with transferred tokens
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        uint256 actualAmount;
        uint8 tokenDecimals;
        (actualAmount, tokenDecimals) = _checkAndTransferPrincipal(
            listingAddress,
            tokenIn,
            inputAmount,
            liquidityAddr
        );
        uint256 normalizedAmount = normalize(actualAmount, tokenDecimals);
        require(normalizedAmount > 0, "Normalized amount is zero");
        try liquidityContract.updateLiquidity(address(this), isX, normalizedAmount) {} catch {
            revert("Liquidity update failed");
        }
    }

    function _createBuyOrderUpdates(
        uint256 orderIdentifier,
        BuyOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (IOMFListingTemplate.UpdateType[] memory) {
        // Creates update structs for buy order processing
        IOMFListingTemplate.UpdateType[] memory updates = new IOMFListingTemplate.UpdateType[](2);
        updates[0] = IOMFListingTemplate.UpdateType({
            updateType: 1, // Buy order
            structId: 2, // Amounts
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: updateContext.amountSent
        });
        updates[1] = IOMFListingTemplate.UpdateType({
            updateType: 1, // Buy order
            structId: 0, // Core
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _createSellOrderUpdates(
        uint256 orderIdentifier,
        SellOrderUpdateContext memory updateContext,
        uint256 pendingAmount
    ) internal pure returns (IOMFListingTemplate.UpdateType[] memory) {
        // Creates update structs for sell order processing
        IOMFListingTemplate.UpdateType[] memory updates = new IOMFListingTemplate.UpdateType[](2);
        updates[0] = IOMFListingTemplate.UpdateType({
            updateType: 2, // Sell order
            structId: 2, // Amounts
            index: orderIdentifier,
            value: updateContext.normalizedReceived,
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: updateContext.amountSent
        });
        updates[1] = IOMFListingTemplate.UpdateType({
            updateType: 2, // Sell order
            structId: 0, // Core
            index: orderIdentifier,
            value: updateContext.status == 1 && updateContext.normalizedReceived >= pendingAmount ? 3 : 2,
            addr: updateContext.makerAddress,
            recipient: updateContext.recipient,
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        return updates;
    }

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal view returns (PrepOrderUpdateResult memory) {
        // Prepares buy order update data
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.buyOrderAmountsView(orderIdentifier);
        (address makerAddress, address recipientAddress, uint8 orderStatus) = listingContract.buyOrderDetailsView(orderIdentifier);
        (address tokenAddr, uint8 tokenDec) = _getTokenAndDecimals(listingAddress, false);
        uint256 normalizedReceived = normalize(amountOut, tokenDec);
        return PrepOrderUpdateResult({
            makerAddress: makerAddress,
            recipientAddress: recipientAddress,
            orderStatus: orderStatus,
            amountReceived: amountOut,
            normalizedReceived: normalizedReceived,
            amountSent: amountSent,
            tokenDecimals: tokenDec
        });
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amountOut
    ) internal view returns (PrepOrderUpdateResult memory) {
        // Prepares sell order update data
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.sellOrderAmountsView(orderIdentifier);
        (address makerAddress, address recipientAddress, uint8 orderStatus) = listingContract.sellOrderDetailsView(orderIdentifier);
        (address tokenAddr, uint8 tokenDec) = _getTokenAndDecimals(listingAddress, true);
        uint256 normalizedReceived = normalize(amountOut, tokenDec);
        return PrepOrderUpdateResult({
            makerAddress: makerAddress,
            recipientAddress: recipientAddress,
            orderStatus: orderStatus,
            amountReceived: amountOut,
            normalizedReceived: normalizedReceived,
            amountSent: amountSent,
            tokenDecimals: tokenDec
        });
    }
}