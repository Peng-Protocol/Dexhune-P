/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
 Version: 0.0.9 (13/10/2025)
 Changes:
 - v0.0.9 (13/10): Updated _computeUsagePercent for 0.05% min fee at ≤1% liquidity usage, scaling to 0.10% at 2%, 0.50% at 10%, up to 50% at 100%. Removed Clamping.
- v0.0.8 (11/10): Removed unused local variables and params. 
- v0.0.7 (11/10): Added ListingBalanceContext and _checkListingBalance to _processSingleOrder for listing template balance validation, emitting ListingBalanceExcess if exceeded. Removed unused UniswapLiquidityExcess event.
- v0.0.6: Refactored _computeFee (x64) into helper functions (_fetchLiquidityData, _computeUsagePercent, _clampFeePercent, _calculateFeeAmount) using FeeCalculationContext to fix stack too deep error. Updated _executeOrderWithFees to use refactored _computeFee.
- v0.0.5: Modified _processSingleOrder to skip invalid orders gracefully, emitting PriceOutOfBounds without reverting. Updated _computeResult to set status based on post-update pending amount. Ensured _processOrderBatch aggregates success without reverting.
- v0.0.4: Updated _computeFee to enforce 0.01% minimum and 10% maximum fees, scaling with usage.
- v0.0.3: Refactored _prepBuyOrderUpdate and _prepSellOrderUpdate to address stack too deep error (x64). Split logic into helper functions (_fetchOrderData, _transferPrincipal, _updateLiquidity, _transferSettlement, _computeResult) with TransferContext struct to reduce stack usage.
- v0.0.2: Patched _prepBuyOrderUpdate and _prepSellOrderUpdate to send settlement tokens from liquidity contract instead of listing contract, updating xLiquid/yLiquid accordingly.
- v0.0.1: Created MFPLiquidPartial.sol from CCLiquidPartial.sol v0.0.45, removed Uniswap functionality (IUniswapV2Pair, _getSwapReserves, MissingUniswapRouter event), replaced _computeSwapImpact with _computeImpactPrice using settlementAmount/xBalance for impact percentage, updated _processSingleOrder and _validateOrderPricing for new price logic.
*/

pragma solidity ^0.8.2;

import "./CCMainPartial.sol";

contract MFPLiquidPartial is CCMainPartial {
    struct OrderContext {
        ICCListing listingContract;
        address tokenIn;
        address tokenOut;
    }

    struct PrepOrderUpdateResult {
        address tokenAddress;
        uint8 tokenDecimals;
        address makerAddress;
        address recipientAddress;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 preTransferWithdrawn;
        uint8 status;
    }

    struct BuyOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 preTransferWithdrawn;
    }

    struct SellOrderUpdateContext {
        address makerAddress;
        address recipient;
        uint8 status;
        uint256 amountReceived;
        uint256 normalizedReceived;
        uint256 amountSent;
        uint256 preTransferWithdrawn;
    }

    struct OrderBatchContext {
        address listingAddress;
        uint256 maxIterations;
        bool isBuyOrder;
    }

    struct FeeContext {
        uint256 feeAmount;
        uint256 netAmount;
        uint256 liquidityAmount;
        uint8 decimals;
    }

    struct OrderProcessingContext {
        uint256 maxPrice;
        uint256 minPrice;
        uint256 currentPrice;
        uint256 impactPrice;
    }

    struct LiquidityUpdateContext {
        uint256 pendingAmount;
        uint256 amountOut;
        uint8 tokenDecimals;
        bool isBuyOrder;
    }
    
    struct TransferContext {
    address maker;
    address recipient;
    uint8 status;
    uint256 amountSent;
}

struct FeeCalculationContext {
        uint256 normalizedAmountSent;
        uint256 normalizedLiquidity;
        uint256 feePercent;
        uint256 feeAmount;
    }
    
    struct ListingBalanceContext {
    address outputToken;
    uint256 normalizedListingBalance;
    uint256 internalLiquidity;
}

    event FeeDeducted(address indexed listingAddress, uint256 orderId, bool isBuyOrder, uint256 feeAmount, uint256 netAmount);
    event PriceOutOfBounds(address indexed listingAddress, uint256 orderId, uint256 impactPrice, uint256 maxPrice, uint256 minPrice);
    event TokenTransferFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event SwapFailed(address indexed listingAddress, uint256 orderId, uint256 amountIn, string reason);
    event ApprovalFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event UpdateFailed(address indexed listingAddress, string reason);
    event InsufficientBalance(address indexed listingAddress, uint256 required, uint256 available);
    event ListingBalanceExcess(address indexed listingAddress, uint256 orderId, bool isBuyOrder, uint256 listingBalance, uint256 internalLiquidity);
    
    function _computeCurrentPrice(address listingAddress) private view returns (uint256 price) {
        ICCListing listingContract = ICCListing(listingAddress);
        try listingContract.prices(0) returns (uint256 _price) {
            require(_price > 0, "Invalid price from listing");
            price = _price;
        } catch Error(string memory reason) {
            revert(string(abi.encodePacked("Price fetch failed: ", reason)));
        }
    }

    function _computeImpactPrice(address listingAddress, uint256 amountIn, bool isBuyOrder) private view returns (uint256 price, uint256 amountOut) {
    ICCListing listingContract = ICCListing(listingAddress);
    uint8 decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
    uint8 decimalsOut = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
    uint256 normalizedAmountIn = normalize(amountIn, decimalsIn);
    uint256 currentPrice = _computeCurrentPrice(listingAddress);
    uint256 impactPercentage = normalizedAmountIn * 1e18; // Simplified, as xBalance removed
    price = isBuyOrder
        ? (currentPrice * (1e18 + impactPercentage)) / 1e18
        : (currentPrice * (1e18 - impactPercentage)) / 1e18;
    amountOut = denormalize((normalizedAmountIn * currentPrice) / 1e18, decimalsOut);
}

    function _getTokenAndDecimals(address listingAddress, bool isBuyOrder) private view returns (address tokenAddress, uint8 tokenDecimals) {
        ICCListing listingContract = ICCListing(listingAddress);
        tokenAddress = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenDecimals = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
    }

    function _checkPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) private view returns (bool) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 maxPrice, uint256 minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderIdentifier)
            : listingContract.getSellOrderPricing(orderIdentifier);
        (uint256 impactPrice,) = _computeImpactPrice(listingAddress, pendingAmount, isBuyOrder);
        return impactPrice <= maxPrice && impactPrice >= minPrice;
    }

    function _computeAmountSent(address tokenAddress, address recipientAddress) private view returns (uint256 preBalance) {
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _prepareLiquidityTransaction(address listingAddress, uint256 inputAmount, bool isBuyOrder) private view returns (uint256 amountOut, address tokenIn, address tokenOut) {
        ICCListing listingContract = ICCListing(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView();
        ICCLiquidity liquidityContract = ICCLiquidity(liquidityAddr);
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        (, uint256 computedAmountOut) = _computeImpactPrice(listingAddress, inputAmount, isBuyOrder);
        amountOut = computedAmountOut;
        tokenIn = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
        tokenOut = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        require(isBuyOrder ? yAmount >= inputAmount : xAmount >= inputAmount, "Insufficient liquidity");
        require(isBuyOrder ? xAmount >= amountOut : yAmount >= amountOut, "Insufficient output liquidity");
    }

    function _prepareCoreUpdate(uint256 orderIdentifier, address listingAddress, bool isBuyOrder, uint8 status) private view returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient,) = isBuyOrder
            ? listingContract.getBuyOrderCore(orderIdentifier)
            : listingContract.getSellOrderCore(orderIdentifier);
        updateType = isBuyOrder ? 1 : 2;
        updateSort = 0;
        updateData = uint256(bytes32(abi.encode(maker, recipient, status)));
    }

    function _prepareAmountsUpdate(uint256 orderIdentifier, address listingAddress, bool isBuyOrder, uint256 preTransferWithdrawn, uint256 amountSent) private view returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 pending, uint256 filled,) = isBuyOrder
            ? listingContract.getBuyOrderAmounts(orderIdentifier)
            : listingContract.getSellOrderAmounts(orderIdentifier);
        uint256 newPending = pending >= preTransferWithdrawn ? pending - preTransferWithdrawn : 0;
        uint256 newFilled = filled + preTransferWithdrawn;
        updateType = isBuyOrder ? 1 : 2;
        updateSort = 2;
        updateData = uint256(bytes32(abi.encode(newPending, newFilled, amountSent)));
    }

    function _prepareBalanceUpdate(uint256 normalizedReceived) private pure returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        updateType = 0;
        updateSort = 0;
        updateData = normalizedReceived;
    }

    function _createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory context, uint256 pendingAmount) private pure returns (ICCListing.BuyOrderUpdate[] memory updates) {
        updates = new ICCListing.BuyOrderUpdate[](2);
        uint8 newStatus = pendingAmount == 0 ? 0 : (context.preTransferWithdrawn >= pendingAmount ? 3 : 2);
        updates[0] = ICCListing.BuyOrderUpdate({
            structId: 0,
            orderId: orderIdentifier,
            makerAddress: context.makerAddress,
            recipientAddress: context.recipient,
            status: newStatus,
            maxPrice: 0,
            minPrice: 0,
            pending: 0,
            filled: 0,
            amountSent: 0
        });
        updates[1] = ICCListing.BuyOrderUpdate({
            structId: 2,
            orderId: orderIdentifier,
            makerAddress: address(0),
            recipientAddress: address(0),
            status: 0,
            maxPrice: 0,
            minPrice: 0,
            pending: pendingAmount >= context.preTransferWithdrawn ? pendingAmount - context.preTransferWithdrawn : 0,
            filled: context.preTransferWithdrawn,
            amountSent: context.amountSent
        });
    }

    function _createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory context, uint256 pendingAmount) private pure returns (ICCListing.SellOrderUpdate[] memory updates) {
        updates = new ICCListing.SellOrderUpdate[](2);
        uint8 newStatus = pendingAmount == 0 ? 0 : (context.preTransferWithdrawn >= pendingAmount ? 3 : 2);
        updates[0] = ICCListing.SellOrderUpdate({
            structId: 0,
            orderId: orderIdentifier,
            makerAddress: context.makerAddress,
            recipientAddress: context.recipient,
            status: newStatus,
            maxPrice: 0,
            minPrice: 0,
            pending: 0,
            filled: 0,
            amountSent: 0
        });
        updates[1] = ICCListing.SellOrderUpdate({
            structId: 2,
            orderId: orderIdentifier,
            makerAddress: address(0),
            recipientAddress: address(0),
            status: 0,
            maxPrice: 0,
            minPrice: 0,
            pending: pendingAmount >= context.preTransferWithdrawn ? pendingAmount - context.preTransferWithdrawn : 0,
            filled: context.preTransferWithdrawn,
            amountSent: context.amountSent
        });
    }

    // Fetches order data to reduce stack usage
function _fetchOrderData(address listingAddress, uint256 orderId, bool isBuyOrder) private view returns (TransferContext memory context, address tokenAddress, uint8 tokenDecimals) {
    ICCListing listingContract = ICCListing(listingAddress);
    (context.maker, context.recipient, context.status) = isBuyOrder 
        ? listingContract.getBuyOrderCore(orderId) 
        : listingContract.getSellOrderCore(orderId);
    (tokenAddress, tokenDecimals) = _getTokenAndDecimals(listingAddress, !isBuyOrder);
}

// Transfers principal to liquidity contract
function _transferPrincipal(address listingAddress, uint256 pendingAmount, bool isBuyOrder) private {
    ICCListing listingContract = ICCListing(listingAddress);
    address token = isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
    try listingContract.transactToken(token, pendingAmount, listingContract.liquidityAddressView()) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Principal transfer failed: ", reason)));
    }
}

// Updates liquidity for principal
function _updateLiquidity(address listingAddress, uint256 pendingAmount, bool isBuyOrder, uint8 tokenDecimals) private {
    ICCLiquidity liquidityContract = ICCLiquidity(ICCListing(listingAddress).liquidityAddressView());
    (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
    ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
    updates[0] = ICCLiquidity.UpdateType({
        updateType: 0,
        index: isBuyOrder ? 1 : 0,
        value: normalize(pendingAmount, tokenDecimals) + (isBuyOrder ? yAmount : xAmount),
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), updates) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Principal liquidity update failed: ", reason)));
    }
}

// Transfers settlement token from liquidity contract
function _transferSettlement(address listingAddress, address maker, address tokenAddress, uint256 amountOut, address recipient) private returns (uint256 amountSent) {
    ICCLiquidity liquidityContract = ICCLiquidity(ICCListing(listingAddress).liquidityAddressView());
    uint256 preBalance = _computeAmountSent(tokenAddress, recipient);
    try liquidityContract.transactToken(maker, tokenAddress, amountOut, recipient) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Settlement transfer failed: ", reason)));
    }
    uint256 postBalance = _computeAmountSent(tokenAddress, recipient);
    amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
}

    // Computes final result for order update
    function _computeResult(address tokenAddress, uint8 tokenDecimals, TransferContext memory context, uint256 amountOut, uint256 pendingAmount) private pure returns (PrepOrderUpdateResult memory result) {
        uint256 newPending = pendingAmount >= amountOut ? pendingAmount - amountOut : 0;
        uint8 newStatus = newPending == 0 ? 3 : 2; // Status 3 if pending is 0, else 2
        result = PrepOrderUpdateResult({
            tokenAddress: tokenAddress,
            tokenDecimals: tokenDecimals,
            makerAddress: context.maker,
            recipientAddress: context.recipient,
            amountReceived: amountOut,
            normalizedReceived: normalize(amountOut, tokenDecimals),
            amountSent: context.amountSent, // Uses pre/post balance from _transferSettlement
            preTransferWithdrawn: amountOut,
            status: newStatus
        });
    }

function _prepBuyOrderUpdate(
    address listingAddress,
    uint256 orderId,
    uint256 pendingAmount,
    uint256 amountOut
) private returns (PrepOrderUpdateResult memory result) {
    (TransferContext memory context, address tokenAddress, uint8 tokenDecimals) = _fetchOrderData(listingAddress, orderId, true);
    _transferPrincipal(listingAddress, pendingAmount, true);
    _updateLiquidity(listingAddress, pendingAmount, true, tokenDecimals);
    context.amountSent = _transferSettlement(listingAddress, context.maker, tokenAddress, amountOut, context.recipient);
    result = _computeResult(tokenAddress, tokenDecimals, context, amountOut, pendingAmount);
}

function _prepSellOrderUpdate(
    address listingAddress,
    uint256 orderId,
    uint256 pendingAmount,
    uint256 amountOut
) private returns (PrepOrderUpdateResult memory result) {
    (TransferContext memory context, address tokenAddress, uint8 tokenDecimals) = _fetchOrderData(listingAddress, orderId, false);
    _transferPrincipal(listingAddress, pendingAmount, false);
    _updateLiquidity(listingAddress, pendingAmount, false, tokenDecimals);
    context.amountSent = _transferSettlement(listingAddress, context.maker, tokenAddress, amountOut, context.recipient);
    result = _computeResult(tokenAddress, tokenDecimals, context, amountOut, pendingAmount);
}

    function executeSingleBuyLiquid(address listingAddress, uint256 orderIdentifier) internal returns (bool success) {
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient, uint8 status) = listingContract.getBuyOrderCore(orderIdentifier);
        (uint256 pending,,) = listingContract.getBuyOrderAmounts(orderIdentifier);
        BuyOrderUpdateContext memory context = BuyOrderUpdateContext({
            makerAddress: maker,
            recipient: recipient,
            status: status,
            amountReceived: 0,
            normalizedReceived: 0,
            amountSent: 0,
            preTransferWithdrawn: 0
        });
        ICCListing.BuyOrderUpdate[] memory updates = _createBuyOrderUpdates(orderIdentifier, context, pending);
        ICCListing.SellOrderUpdate[] memory sellUpdates = new ICCListing.SellOrderUpdate[](0);
        ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
        ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](0);
        try listingContract.ccUpdate(updates, sellUpdates, balanceUpdates, historicalUpdates) {
            success = true;
        } catch Error(string memory reason) {
            emit UpdateFailed(listingAddress, string(abi.encodePacked("Buy order update failed: ", reason)));
            success = false;
        }
    }

    function executeSingleSellLiquid(address listingAddress, uint256 orderIdentifier) internal returns (bool success) {
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient, uint8 status) = listingContract.getSellOrderCore(orderIdentifier);
        (uint256 pending,,) = listingContract.getSellOrderAmounts(orderIdentifier);
        SellOrderUpdateContext memory context = SellOrderUpdateContext({
            makerAddress: maker,
            recipient: recipient,
            status: status,
            amountReceived: 0,
            normalizedReceived: 0,
            amountSent: 0,
            preTransferWithdrawn: 0
        });
        ICCListing.SellOrderUpdate[] memory updates = _createSellOrderUpdates(orderIdentifier, context, pending);
        ICCListing.BuyOrderUpdate[] memory buyUpdates = new ICCListing.BuyOrderUpdate[](0);
        ICCListing.BalanceUpdate[] memory balanceUpdates = new ICCListing.BalanceUpdate[](0);
        ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](0);
        try listingContract.ccUpdate(buyUpdates, updates, balanceUpdates, historicalUpdates) {
            success = true;
        } catch Error(string memory reason) {
            emit UpdateFailed(listingAddress, string(abi.encodePacked("Sell order update failed: ", reason)));
            success = false;
        }
    }

    function _collectOrderIdentifiers(address listingAddress, uint256 maxIterations, uint256 step) internal view returns (uint256[] memory orderIdentifiers, uint256 iterationCount) {
        ICCListing listingContract = ICCListing(listingAddress);
        uint256[] memory identifiers = listingContract.makerPendingOrdersView(msg.sender);
        require(step <= identifiers.length, "Step exceeds pending orders length");
        uint256 remainingOrders = identifiers.length - step;
        iterationCount = maxIterations < remainingOrders ? maxIterations : remainingOrders;
        orderIdentifiers = new uint256[](iterationCount);
        for (uint256 i = 0; i < iterationCount; i++) {
            orderIdentifiers[i] = identifiers[step + i];
        }
    }

    function _updateLiquidityBalances(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount, uint256 settleAmount) private {
        ICCListing listingContract = ICCListing(listingAddress);
        ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        uint256 normalizedPending = normalize(pendingAmount, isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA());
        uint256 normalizedSettle = normalize(settleAmount, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
        ICCLiquidity.UpdateType[] memory liquidityUpdates = new ICCLiquidity.UpdateType[](2);
        liquidityUpdates[0] = ICCLiquidity.UpdateType({
            updateType: 0,
            index: isBuyOrder ? 1 : 0,
            value: isBuyOrder ? yAmount - normalizedPending : xAmount - normalizedPending,
            addr: address(this),
            recipient: address(0)
        });
        liquidityUpdates[1] = ICCLiquidity.UpdateType({
            updateType: 0,
            index: isBuyOrder ? 0 : 1,
            value: isBuyOrder ? xAmount + normalizedSettle : yAmount + normalizedSettle,
            addr: address(this),
            recipient: address(0)
        });
        try liquidityContract.ccUpdate(address(this), liquidityUpdates) {} catch (bytes memory reason) {
            emit SwapFailed(listingAddress, orderIdentifier, pendingAmount, string(abi.encodePacked("Liquidity update failed: ", reason)));
        }
    }

    function _validateOrderPricing(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) private returns (OrderProcessingContext memory context) {
        ICCListing listingContract = ICCListing(listingAddress);
        (context.maxPrice, context.minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderIdentifier)
            : listingContract.getSellOrderPricing(orderIdentifier);
        context.currentPrice = _computeCurrentPrice(listingAddress);
        (context.impactPrice,) = _computeImpactPrice(listingAddress, pendingAmount, isBuyOrder);
        if (!(context.impactPrice >= context.minPrice && context.impactPrice <= context.maxPrice && 
              context.currentPrice >= context.minPrice && context.currentPrice <= context.maxPrice)) {
            emit PriceOutOfBounds(listingAddress, orderIdentifier, context.impactPrice, context.maxPrice, context.minPrice);
            context.impactPrice = 0;
        }
    }

        // Fetches liquidity data for fee calculation
    function _fetchLiquidityData(address listingAddress, bool isBuyOrder) private view returns (uint256 outputLiquidityAmount, uint8 outputDecimals, uint256 amountOut) {
        ICCListing listingContract = ICCListing(listingAddress);
        ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
        (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
        outputLiquidityAmount = isBuyOrder ? xLiquid : yLiquid;
        outputDecimals = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
        (, amountOut) = _computeImpactPrice(listingAddress, 0, isBuyOrder); // Use 0 for amountIn to get base amountOut
    }

    // Computes usage percentage for fee
    function _computeUsagePercent(uint256 normalizedAmountSent, uint256 normalizedLiquidity) private pure returns (uint256 feePercent) {
    // Scales fee from 0.05% at ≤1% usage to 50% at 100% usage
    uint256 usagePercent = (normalizedAmountSent * 1e18) / (normalizedLiquidity == 0 ? 1 : normalizedLiquidity);
    feePercent = (usagePercent * 5e15) / 1e16; // Linear scaling: 0.05% per 1% usage
    if (feePercent < 5e14) feePercent = 5e14; // 0.05% minimum
    if (feePercent > 5e17) feePercent = 5e17; // 50% maximum
}

    // Calculates final fee and net amount
    function _calculateFeeAmount(uint256 pendingAmount, uint256 feePercent) private pure returns (uint256 feeAmount, uint256 netAmount) {
        feeAmount = (pendingAmount * feePercent) / 1e18;
        netAmount = pendingAmount - feeAmount;
    }

    function _computeFee(address listingAddress, uint256 pendingAmount, bool isBuyOrder) private view returns (FeeContext memory feeContext) {
        FeeCalculationContext memory calcContext;
        (uint256 outputLiquidityAmount, uint8 outputDecimals, uint256 amountOut) = _fetchLiquidityData(listingAddress, isBuyOrder);
        calcContext.normalizedAmountSent = normalize(amountOut, outputDecimals);
        calcContext.normalizedLiquidity = normalize(outputLiquidityAmount, outputDecimals);
        calcContext.feePercent = _computeUsagePercent(calcContext.normalizedAmountSent, calcContext.normalizedLiquidity); // Removed clamping
        (calcContext.feeAmount, feeContext.netAmount) = _calculateFeeAmount(pendingAmount, calcContext.feePercent);
        feeContext.feeAmount = calcContext.feeAmount;
        feeContext.decimals = outputDecimals;
        feeContext.liquidityAmount = outputLiquidityAmount;
    }

    function _computeSwapAmount(address listingAddress, FeeContext memory feeContext, bool isBuyOrder) private view returns (LiquidityUpdateContext memory context) {
        context.pendingAmount = feeContext.netAmount;
        context.isBuyOrder = isBuyOrder;
        (, context.tokenDecimals) = _getTokenAndDecimals(listingAddress, isBuyOrder);
        (, context.amountOut) = _computeImpactPrice(listingAddress, feeContext.netAmount, isBuyOrder);
    }

    function _toSingleUpdateArray(ICCLiquidity.UpdateType memory update) private pure returns (ICCLiquidity.UpdateType[] memory) {
        ICCLiquidity.UpdateType[] memory updates = new ICCLiquidity.UpdateType[](1);
        updates[0] = update;
        return updates;
    }

    function _prepareLiquidityUpdates(address listingAddress, LiquidityUpdateContext memory context) private {
    ICCListing listingContract = ICCListing(listingAddress);
    ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
    (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
    address tokenAddress = context.isBuyOrder ? listingContract.tokenB() : listingContract.tokenA();
    uint256 normalizedPending = normalize(context.pendingAmount, context.tokenDecimals);
    uint256 normalizedSettle = normalize(context.amountOut, context.isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
    FeeContext memory feeContext = _computeFee(listingAddress, context.pendingAmount, context.isBuyOrder);
    uint256 normalizedFee = normalize(feeContext.feeAmount, context.tokenDecimals);

    require(context.isBuyOrder ? yLiquid >= normalizedPending : xLiquid >= normalizedPending, "Insufficient input liquidity");
    require(context.isBuyOrder ? xLiquid >= normalizedSettle : yLiquid >= normalizedSettle, "Insufficient output liquidity");

    ICCLiquidity.UpdateType memory update;

    update = ICCLiquidity.UpdateType({
        updateType: 0,
        index: context.isBuyOrder ? 1 : 0,
        value: context.isBuyOrder ? yLiquid + normalizedPending : xLiquid + normalizedPending,
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), _toSingleUpdateArray(update)) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Incoming liquidity update failed: ", reason)));
    }

    update = ICCLiquidity.UpdateType({
        updateType: 0,
        index: context.isBuyOrder ? 0 : 1,
        value: context.isBuyOrder ? xLiquid - normalizedSettle : yLiquid - normalizedSettle,
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), _toSingleUpdateArray(update)) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Outgoing liquidity update failed: ", reason)));
    }

    update = ICCLiquidity.UpdateType({
        updateType: 1,
        index: context.isBuyOrder ? 1 : 0,
        value: normalizedFee,
        addr: address(this),
        recipient: address(0)
    });
    try liquidityContract.ccUpdate(address(this), _toSingleUpdateArray(update)) {} catch Error(string memory reason) {
        revert(string(abi.encodePacked("Fee update failed: ", reason)));
    }

    if (tokenAddress == address(0)) {
        try listingContract.transactNative(context.pendingAmount, listingContract.liquidityAddressView()) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Native transfer failed: ", reason)));
        }
    } else {
        try listingContract.transactToken(tokenAddress, context.pendingAmount, listingContract.liquidityAddressView()) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Token transfer failed: ", reason)));
        }
    }
}

    function _executeOrderWithFees(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, FeeContext memory feeContext) private returns (bool success) {
        ICCListing listingContract = ICCListing(listingAddress);
        emit FeeDeducted(listingAddress, orderIdentifier, isBuyOrder, feeContext.feeAmount, feeContext.netAmount);
        LiquidityUpdateContext memory liquidityContext = _computeSwapAmount(listingAddress, feeContext, isBuyOrder);
        _prepareLiquidityUpdates(listingAddress, liquidityContext);

        ICCListing.HistoricalUpdate[] memory historicalUpdates = new ICCListing.HistoricalUpdate[](1);
        (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
        uint256 historicalLength = listingContract.historicalDataLengthView();
        uint256 xVolume = 0;
        uint256 yVolume = 0;
        if (historicalLength > 0) {
            ICCListing.HistoricalData memory lastData = listingContract.getHistoricalDataView(historicalLength - 1);
            xVolume = lastData.xVolume;
            yVolume = lastData.yVolume;
        }
        historicalUpdates[0] = ICCListing.HistoricalUpdate({
            price: listingContract.prices(0),
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
        ) {} catch Error(string memory reason) {
            revert(string(abi.encodePacked("Historical update failed: ", reason)));
        }

        success = isBuyOrder
            ? executeSingleBuyLiquid(listingAddress, orderIdentifier)
            : executeSingleSellLiquid(listingAddress, orderIdentifier);
        require(success, "Order execution failed");
    }

    function _processSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount) internal returns (bool success) {
    ICCListing listingContract = ICCListing(listingAddress);
    ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
    (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
    OrderProcessingContext memory context = _validateOrderPricing(listingAddress, orderIdentifier, isBuyOrder, pendingAmount);

    if (context.impactPrice == 0) {
        emit PriceOutOfBounds(listingAddress, orderIdentifier, context.impactPrice, context.maxPrice, context.minPrice);
        return false;
    }

    uint256 normalizedPending = normalize(pendingAmount, isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA());
    (, uint256 amountOut) = _computeImpactPrice(listingAddress, pendingAmount, isBuyOrder);
    uint256 normalizedSettle = normalize(amountOut, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
    if (isBuyOrder ? yLiquid < normalizedPending : xLiquid < normalizedPending) {
        emit InsufficientBalance(listingAddress, normalizedPending, isBuyOrder ? yLiquid : xLiquid);
        return false;
    }
    if (isBuyOrder ? xLiquid < normalizedSettle : yLiquid < normalizedSettle) {
        emit InsufficientBalance(listingAddress, normalizedSettle, isBuyOrder ? xLiquid : yLiquid);
        return false;
    }

    ListingBalanceContext memory balanceContext;
    balanceContext.outputToken = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
    balanceContext.normalizedListingBalance = balanceContext.outputToken == address(0) ? address(listingAddress).balance : IERC20(balanceContext.outputToken).balanceOf(listingAddress);
    balanceContext.normalizedListingBalance = normalize(balanceContext.normalizedListingBalance, isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB());
    balanceContext.internalLiquidity = isBuyOrder ? xLiquid : yLiquid;
    if (balanceContext.normalizedListingBalance > balanceContext.internalLiquidity) {
        emit ListingBalanceExcess(listingAddress, orderIdentifier, isBuyOrder, balanceContext.normalizedListingBalance, balanceContext.internalLiquidity);
        return false;
    }

    FeeContext memory feeContext = _computeFee(listingAddress, pendingAmount, isBuyOrder);
    success = _executeOrderWithFees(listingAddress, orderIdentifier, isBuyOrder, feeContext);
}

    function _processOrderBatch(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal returns (bool success) {
        (uint256[] memory orderIdentifiers, uint256 iterationCount) = _collectOrderIdentifiers(listingAddress, maxIterations, step);
        success = false;
        for (uint256 i = 0; i < iterationCount; i++) {
            (uint256 pendingAmount,,) = isBuyOrder
                ? ICCListing(listingAddress).getBuyOrderAmounts(orderIdentifiers[i])
                : ICCListing(listingAddress).getSellOrderAmounts(orderIdentifiers[i]);
            if (pendingAmount == 0) continue;
            if (_processSingleOrder(listingAddress, orderIdentifiers[i], isBuyOrder, pendingAmount)) {
                success = true; // At least one order succeeded, reverts for critical errors are handled upstream 
            }
        }
    }

    function _finalizeUpdates(bool isBuyOrder, ICCListing.BuyOrderUpdate[] memory buyUpdates, ICCListing.SellOrderUpdate[] memory sellUpdates, uint256 updateIndex) internal pure returns (ICCListing.BuyOrderUpdate[] memory finalBuyUpdates, ICCListing.SellOrderUpdate[] memory finalSellUpdates) {
        if (isBuyOrder) {
            finalBuyUpdates = new ICCListing.BuyOrderUpdate[](updateIndex);
            for (uint256 i = 0; i < updateIndex; i++) {
                finalBuyUpdates[i] = buyUpdates[i];
            }
            finalSellUpdates = new ICCListing.SellOrderUpdate[](0);
        } else {
            finalSellUpdates = new ICCListing.SellOrderUpdate[](updateIndex);
            for (uint256 i = 0; i < updateIndex; i++) {
                finalSellUpdates[i] = sellUpdates[i];
            }
            finalBuyUpdates = new ICCListing.BuyOrderUpdate[](0);
        }
    }

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}