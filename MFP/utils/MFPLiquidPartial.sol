/*
 SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
 Version: 0.1.0
 Changes:
 - v0.1.0: Created MFPLiquidPartial.sol from CCLiquidPartial.sol v0.0.45, removed Uniswap functionality (IUniswapV2Pair, _getSwapReserves, MissingUniswapRouter event), replaced _computeSwapImpact with _computeImpactPrice using settlementAmount/xBalance for impact percentage, updated _processSingleOrder and _validateOrderPricing for new price logic.
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

    event FeeDeducted(address indexed listingAddress, uint256 orderId, bool isBuyOrder, uint256 feeAmount, uint256 netAmount);
    event PriceOutOfBounds(address indexed listingAddress, uint256 orderId, uint256 impactPrice, uint256 maxPrice, uint256 minPrice);
    event TokenTransferFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event SwapFailed(address indexed listingAddress, uint256 orderId, uint256 amountIn, string reason);
    event ApprovalFailed(address indexed listingAddress, uint256 orderId, address token, string reason);
    event UpdateFailed(address indexed listingAddress, string reason);
    event InsufficientBalance(address indexed listingAddress, uint256 required, uint256 available);

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
        (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
        uint8 decimalsIn = isBuyOrder ? listingContract.decimalsB() : listingContract.decimalsA();
        uint8 decimalsOut = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
        uint256 normalizedAmountIn = normalize(amountIn, decimalsIn);
        uint256 currentPrice = _computeCurrentPrice(listingAddress);
        uint256 impactPercentage = xBalance > 0 ? (normalizedAmountIn * 1e18) / xBalance : 0;
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

    function _computeAmountSent(address tokenAddress, address recipientAddress, uint256 amount) private view returns (uint256 preBalance) {
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

    function _prepareBalanceUpdate(uint256 normalizedReceived, bool isBuyOrder) private pure returns (uint8 updateType, uint8 updateSort, uint256 updateData) {
        updateType = 0;
        updateSort = 0;
        updateData = normalizedReceived;
    }

    function _createBuyOrderUpdates(uint256 orderIdentifier, BuyOrderUpdateContext memory context, uint256 pendingAmount) private view returns (ICCListing.BuyOrderUpdate[] memory updates) {
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

    function _createSellOrderUpdates(uint256 orderIdentifier, SellOrderUpdateContext memory context, uint256 pendingAmount) private view returns (ICCListing.SellOrderUpdate[] memory updates) {
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

    function _prepBuyOrderUpdate(
        address listingAddress,
        uint256 orderId,
        uint256 pendingAmount,
        uint256 amountOut
    ) private returns (PrepOrderUpdateResult memory result) {
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient, uint8 status) = listingContract.getBuyOrderCore(orderId);
        (, uint256 minPrice) = listingContract.getBuyOrderPricing(orderId);
        (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, false);
        uint256 preBalance = _computeAmountSent(tokenAddress, recipient, amountOut);
        listingContract.transactToken(tokenAddress, amountOut, recipient);
        uint256 postBalance = _computeAmountSent(tokenAddress, recipient, amountOut);
        uint256 amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
        uint256 normalizedReceived = normalize(amountOut, tokenDecimals);
        uint8 newStatus = pendingAmount == 0 ? 0 : (amountOut >= pendingAmount ? 3 : 2);
        result = PrepOrderUpdateResult({
            tokenAddress: tokenAddress,
            tokenDecimals: tokenDecimals,
            makerAddress: maker,
            recipientAddress: recipient,
            amountReceived: amountOut,
            normalizedReceived: normalizedReceived,
            amountSent: amountSent,
            preTransferWithdrawn: amountOut,
            status: newStatus
        });
    }

    function _prepSellOrderUpdate(
        address listingAddress,
        uint256 orderId,
        uint256 pendingAmount,
        uint256 amountOut
    ) private returns (PrepOrderUpdateResult memory result) {
        ICCListing listingContract = ICCListing(listingAddress);
        (address maker, address recipient, uint8 status) = listingContract.getSellOrderCore(orderId);
        (, uint256 minPrice) = listingContract.getSellOrderPricing(orderId);
        (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, true);
        uint256 preBalance = _computeAmountSent(tokenAddress, recipient, amountOut);
        listingContract.transactToken(tokenAddress, amountOut, recipient);
        uint256 postBalance = _computeAmountSent(tokenAddress, recipient, amountOut);
        uint256 amountSent = postBalance > preBalance ? postBalance - preBalance : 0;
        uint256 normalizedReceived = normalize(amountOut, tokenDecimals);
        uint8 newStatus = pendingAmount == 0 ? 0 : (amountOut >= pendingAmount ? 3 : 2);
        result = PrepOrderUpdateResult({
            tokenAddress: tokenAddress,
            tokenDecimals: tokenDecimals,
            makerAddress: maker,
            recipientAddress: recipient,
            amountReceived: amountOut,
            normalizedReceived: normalizedReceived,
            amountSent: amountSent,
            preTransferWithdrawn: amountOut,
            status: newStatus
        });
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

    function _collectOrderIdentifiers(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal view returns (uint256[] memory orderIdentifiers, uint256 iterationCount) {
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

    function _computeFee(address listingAddress, uint256 pendingAmount, bool isBuyOrder) private view returns (FeeContext memory feeContext) {
        ICCLiquidity liquidityContract = ICCLiquidity(ICCListing(listingAddress).liquidityAddressView());
        (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
        (, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, isBuyOrder);
        uint256 liquidityAmount = isBuyOrder ? yLiquid : xLiquid;
        uint256 normalizedPending = normalize(pendingAmount, tokenDecimals);
        uint256 normalizedLiquidity = normalize(liquidityAmount, tokenDecimals);
        uint256 feePercent = normalizedLiquidity > 0 ? (normalizedPending * 1e18) / normalizedLiquidity : 1e18;
        feePercent = feePercent > 1e18 ? 1e18 : feePercent;
        feeContext.feeAmount = (pendingAmount * feePercent) / 1e20;
        feeContext.netAmount = pendingAmount - feeContext.feeAmount;
        feeContext.liquidityAmount = liquidityAmount;
        feeContext.decimals = tokenDecimals;
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

    function _prepareLiquidityUpdates(address listingAddress, uint256 orderIdentifier, LiquidityUpdateContext memory context) private {
        ICCListing listingContract = ICCListing(listingAddress);
        ICCLiquidity liquidityContract = ICCLiquidity(listingContract.liquidityAddressView());
        (uint256 xLiquid, uint256 yLiquid) = liquidityContract.liquidityAmounts();
        (address tokenAddress, uint8 tokenDecimals) = _getTokenAndDecimals(listingAddress, context.isBuyOrder);
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

    function _executeOrderWithFees(address listingAddress, uint256 orderIdentifier, bool isBuyOrder, uint256 pendingAmount, FeeContext memory feeContext) private returns (bool success) {
        ICCListing listingContract = ICCListing(listingAddress);
        emit FeeDeducted(listingAddress, orderIdentifier, isBuyOrder, feeContext.feeAmount, feeContext.netAmount);
        LiquidityUpdateContext memory liquidityContext = _computeSwapAmount(listingAddress, feeContext, isBuyOrder);
        _prepareLiquidityUpdates(listingAddress, orderIdentifier, liquidityContext);

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

        FeeContext memory feeContext = _computeFee(listingAddress, pendingAmount, isBuyOrder);
        PrepOrderUpdateResult memory result = isBuyOrder
            ? _prepBuyOrderUpdate(listingAddress, orderIdentifier, pendingAmount, amountOut)
            : _prepSellOrderUpdate(listingAddress, orderIdentifier, pendingAmount, amountOut);
        success = _executeOrderWithFees(listingAddress, orderIdentifier, isBuyOrder, pendingAmount, feeContext);
    }

    function _processOrderBatch(address listingAddress, uint256 maxIterations, bool isBuyOrder, uint256 step) internal returns (bool success) {
        (uint256[] memory orderIdentifiers, uint256 iterationCount) = _collectOrderIdentifiers(listingAddress, maxIterations, isBuyOrder, step);
        success = false;
        for (uint256 i = 0; i < iterationCount; i++) {
            (uint256 pendingAmount,,) = isBuyOrder
                ? ICCListing(listingAddress).getBuyOrderAmounts(orderIdentifiers[i])
                : ICCListing(listingAddress).getSellOrderAmounts(orderIdentifiers[i]);
            if (pendingAmount == 0) continue;
            if (_processSingleOrder(listingAddress, orderIdentifiers[i], isBuyOrder, pendingAmount)) {
                success = true;
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