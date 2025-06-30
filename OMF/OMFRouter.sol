// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.77 (Updated)
// Changes:
// - v0.0.77: Refactored createBuyOrder/createSellOrder to use prepAndTransfer call tree in OMFOrderPartial.sol, reducing local variables to fix stack too deep at line 131.
// - v0.0.76: Refactored createBuyOrder/createSellOrder using OrderDetails, prepOrderCore, prepOrderAmounts, applyOrderUpdate.
// - v0.0.75: Fixed stack too deep by adding _handleFeeAndAdd; corrected inheritance to OMFSettlementPartial.

import "./utils/OMFSettlementPartial.sol";

contract OMFRouter is OMFSettlementPartial {
    function _computeAmountSent(address tokenAddress, address recipient, uint256 amount) internal view returns (uint256) {
        // Computes amount sent to recipient
        uint256 preBalance = IERC20(tokenAddress).balanceOf(recipient);
        return preBalance >= amount ? preBalance - amount : 0;
    }

    function _prepBuyLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (IOMFListingTemplate.UpdateType[] memory) {
        // Prepares updates for buy order liquidation
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
            address(context.listingContract),
            pendingAmount,
            true
        );
        BuyOrderUpdateContext memory updateContext;
        {
            PrepOrderUpdateResult memory prepResult = _prepBuyOrderUpdate(
                address(context.listingContract),
                orderIdentifier,
                amountOut
            );
            updateContext.makerAddress = prepResult.makerAddress;
            updateContext.recipient = prepResult.recipientAddress;
            updateContext.status = prepResult.orderStatus;
            updateContext.amountReceived = prepResult.amountReceived;
            updateContext.normalizedReceived = prepResult.normalizedReceived;
            updateContext.amountSent = prepResult.amountSent;
            uint8 tokenDecimals = prepResult.tokenDecimals;
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try IOMFLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new IOMFListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
        }
        if (updateContext.normalizedReceived == 0) {
            return new IOMFListingTemplate.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, false, pendingAmount);
        return _createBuyOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function _prepSellLiquidUpdates(
        OrderContext memory context,
        uint256 orderIdentifier,
        uint256 pendingAmount
    ) internal returns (IOMFListingTemplate.UpdateType[] memory) {
        // Prepares updates for sell order liquidation
        uint256 amountOut;
        address tokenIn;
        address tokenOut;
        (amountOut, tokenIn, tokenOut) = _prepareLiquidityTransaction(
            address(context.listingContract),
            pendingAmount,
            false
        );
        SellOrderUpdateContext memory updateContext;
        {
            PrepOrderUpdateResult memory prepResult = _prepSellOrderUpdate(
                address(context.listingContract),
                orderIdentifier,
                amountOut
            );
            updateContext.makerAddress = prepResult.makerAddress;
            updateContext.recipient = prepResult.recipientAddress;
            updateContext.status = prepResult.orderStatus;
            updateContext.amountReceived = prepResult.amountReceived;
            updateContext.normalizedReceived = prepResult.normalizedReceived;
            updateContext.amountSent = prepResult.amountSent;
            uint8 tokenDecimals = prepResult.tokenDecimals;
            uint256 denormalizedAmount = denormalize(amountOut, tokenDecimals);
            try IOMFLiquidityTemplate(context.liquidityAddr).transact(address(this), tokenOut, denormalizedAmount, updateContext.recipient) {} catch {
                return new IOMFListingTemplate.UpdateType[](0);
            }
            updateContext.amountReceived = denormalizedAmount;
            updateContext.normalizedReceived = normalize(denormalizedAmount, tokenDecimals);
            updateContext.amountSent = _computeAmountSent(tokenOut, updateContext.recipient, denormalizedAmount);
        }
        if (updateContext.normalizedReceived == 0) {
            return new IOMFListingTemplate.UpdateType[](0);
        }
        _updateLiquidity(address(context.listingContract), tokenIn, true, pendingAmount);
        return _createSellOrderUpdates(orderIdentifier, updateContext, pendingAmount);
    }

    function createBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Creates a buy order, initiates call tree for fee and order updates
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address tokenBAddress = listingContract.baseTokenView();
        OrderDetails memory details = OrderDetails({
            recipientAddress: recipientAddress,
            amount: inputAmount,
            maxPrice: maxPrice,
            minPrice: minPrice
        });
        (uint256 actualNetAmount, uint256 orderId) = prepAndTransfer(
            listingAddress,
            tokenBAddress,
            inputAmount,
            true
        );
    }

    function createSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Creates a sell order, initiates call tree for fee and order updates
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address tokenAAddress = listingContract.token0View();
        OrderDetails memory details = OrderDetails({
            recipientAddress: recipientAddress,
            amount: inputAmount,
            maxPrice: maxPrice,
            minPrice: minPrice
        });
        (uint256 actualNetAmount, uint256 orderId) = prepAndTransfer(
            listingAddress,
            tokenAAddress,
            inputAmount,
            false
        );
    }

    function executeBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amount
    ) internal returns (IOMFListingTemplate.UpdateType[] memory) {
        // Executes a buy order, handles liquidation
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.baseTokenView(),
            tokenOut: listingContract.token0View(),
            liquidityAddr: listingContract.liquidityAddressView(listingContract.listingIdView())
        });
        return _prepBuyLiquidUpdates(context, orderIdentifier, amount);
    }

    function executeSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        uint256 amount
    ) internal returns (IOMFListingTemplate.UpdateType[] memory) {
        // Executes a sell order, handles liquidation
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.token0View(),
            tokenOut: listingContract.baseTokenView(),
            liquidityAddr: listingContract.liquidityAddressView(listingContract.listingIdView())
        });
        return _prepSellLiquidUpdates(context, orderIdentifier, amount);
    }

    function executeSingleBuyLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (IOMFListingTemplate.UpdateType[] memory) {
        // Executes a single buy order liquidation
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.buyOrderAmountsView(orderIdentifier);
        if (pendingAmount == 0) {
            return new IOMFListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.baseTokenView(),
            tokenOut: listingContract.token0View(),
            liquidityAddr: listingContract.liquidityAddressView(listingContract.listingIdView())
        });
        return _prepBuyLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function executeSingleSellLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (IOMFListingTemplate.UpdateType[] memory) {
        // Executes a single sell order liquidation
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.sellOrderAmountsView(orderIdentifier);
        if (pendingAmount == 0) {
            return new IOMFListingTemplate.UpdateType[](0);
        }
        OrderContext memory context = OrderContext({
            listingContract: listingContract,
            tokenIn: listingContract.token0View(),
            tokenOut: listingContract.baseTokenView(),
            liquidityAddr: listingContract.liquidityAddressView(listingContract.listingIdView())
        });
        return _prepSellLiquidUpdates(context, orderIdentifier, pendingAmount);
    }

    function settleSingleLongLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (IOMFListingTemplate.PayoutUpdate[] memory) {
        // Settles a single long liquidation
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        (address recipient, uint256 amount) = listingContract.longPayoutDetailsView(orderIdentifier);
        if (amount == 0) {
            return new IOMFListingTemplate.PayoutUpdate[](0);
        }
        try liquidityContract.transact(address(this), listingContract.baseTokenView(), amount, recipient) {} catch {
            return new IOMFListingTemplate.PayoutUpdate[](0);
        }
        IOMFListingTemplate.PayoutUpdate[] memory updates = new IOMFListingTemplate.PayoutUpdate[](1);
        updates[0] = IOMFListingTemplate.PayoutUpdate({
            index: orderIdentifier,
            amount: amount,
            recipient: recipient
        });
        return updates;
    }

    function settleSingleShortLiquid(
        address listingAddress,
        uint256 orderIdentifier
    ) internal returns (IOMFListingTemplate.PayoutUpdate[] memory) {
        // Settles a single short liquidation
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        (address recipient, uint256 amount) = listingContract.shortPayoutDetailsView(orderIdentifier);
        if (amount == 0) {
            return new IOMFListingTemplate.PayoutUpdate[](0);
        }
        try liquidityContract.transact(address(this), listingContract.token0View(), amount, recipient) {} catch {
            return new IOMFListingTemplate.PayoutUpdate[](0);
        }
        IOMFListingTemplate.PayoutUpdate[] memory updates = new IOMFListingTemplate.PayoutUpdate[](1);
        updates[0] = IOMFListingTemplate.PayoutUpdate({
            index: orderIdentifier,
            amount: amount,
            recipient: recipient
        });
        return updates;
    }

    function executeLongPayouts(address listingAddress, uint256 maxIterations) internal {
        // Executes long payouts
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            IOMFListingTemplate.PayoutUpdate[] memory updates = settleSingleLongLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        IOMFListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function executeShortPayouts(address listingAddress, uint256 maxIterations) internal {
        // Executes short payouts
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            IOMFListingTemplate.PayoutUpdate[] memory updates = settleSingleShortLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        IOMFListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function _clearOrderData(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) internal {
        // Clears order data
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        IOMFListingTemplate.UpdateType[] memory updates = new IOMFListingTemplate.UpdateType[](1);
        updates[0] = IOMFListingTemplate.UpdateType({
            updateType: isBuyOrder ? 1 : 2,
            structId: 0, // Core
            index: orderIdentifier,
            value: 0, // Set status to cancelled
            addr: address(0),
            recipient: address(0),
            maxPrice: 0,
            minPrice: 0,
            amountSent: 0
        });
        listingContract.update(address(this), updates);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        IOMFListingTemplate listingContract
    ) internal returns (IOMFListingTemplate.UpdateType[] memory updates) {
        // Processes a single buy order, handling token decimals and execution
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.buyOrderAmountsView(orderIdentifier);
        if (pendingAmount == 0) {
            return new IOMFListingTemplate.UpdateType[](0);
        }
        (address tokenAddr, uint8 tokenDec) = _getTokenAndDecimals(listingAddress, true);
        uint256 denormAmount = denormalize(pendingAmount, tokenDec);
        updates = executeBuyOrder(listingAddress, orderIdentifier, denormAmount);
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        IOMFListingTemplate listingContract
    ) internal returns (IOMFListingTemplate.UpdateType[] memory updates) {
        // Processes a single sell order, handling token decimals and execution
        (uint256 pendingAmount, uint256 filled, uint256 amountSent) = listingContract.sellOrderAmountsView(orderIdentifier);
        if (pendingAmount == 0) {
            return new IOMFListingTemplate.UpdateType[](0);
        }
        (address tokenAddr, uint8 tokenDec) = _getTokenAndDecimals(listingAddress, false);
        uint256 denormAmount = denormalize(pendingAmount, tokenDec);
        updates = executeSellOrder(listingAddress, orderIdentifier, denormAmount);
    }

    function settleBuyOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy orders up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.UpdateType[] memory tempUpdates = new IOMFListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdent = orderIdentifiers[i];
            IOMFListingTemplate.UpdateType[] memory updates = _processBuyOrder(listingAddress, orderIdent, listingContract);
            if (updates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        IOMFListingTemplate.UpdateType[] memory finalUpdates = new IOMFListingTemplate.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function settleSellOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple sell orders up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.UpdateType[] memory tempUpdates = new IOMFListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            uint256 orderIdent = orderIdentifiers[i];
            IOMFListingTemplate.UpdateType[] memory updates = _processSellOrder(listingAddress, orderIdent, listingContract);
            if (updates.length == 0) {
                continue;
            }
            for (uint256 j = 0; j < updates.length; j++) {
                tempUpdates[updateIndex++] = updates[j];
            }
        }
        IOMFListingTemplate.UpdateType[] memory finalUpdates = new IOMFListingTemplate.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple buy order liquidations up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingBuyOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.UpdateType[] memory tempUpdates = new IOMFListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            IOMFListingTemplate.UpdateType[] memory updates = executeSingleBuyLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length > 0) {
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[updateIndex++] = updates[j];
                }
            }
        }
        IOMFListingTemplate.UpdateType[] memory finalUpdates = new IOMFListingTemplate.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function settleSellLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple sell order liquidations up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory orderIdentifiers = listingContract.pendingSellOrdersView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.UpdateType[] memory tempUpdates = new IOMFListingTemplate.UpdateType[](iterationCount * 2);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            IOMFListingTemplate.UpdateType[] memory updates = executeSingleSellLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length > 0) {
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[updateIndex++] = updates[j];
                }
            }
        }
        IOMFListingTemplate.UpdateType[] memory finalUpdates = new IOMFListingTemplate.UpdateType[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.update(address(this), finalUpdates);
        }
    }

    function settleLongPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes long payouts
        executeLongPayouts(listingAddress, maxIterations);
    }

    function settleShortPayouts(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Executes short payouts
        executeShortPayouts(listingAddress, maxIterations);
    }

    function settleLongLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple long liquidations up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        uint256[] memory orderIdentifiers = listingContract.longPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            IOMFListingTemplate.PayoutUpdate[] memory updates = settleSingleLongLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        IOMFListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function settleShortLiquid(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Settles multiple short liquidations up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        uint256[] memory orderIdentifiers = listingContract.shortPayoutByIndexView();
        uint256 iterationCount = maxIterations < orderIdentifiers.length ? maxIterations : orderIdentifiers.length;
        IOMFListingTemplate.PayoutUpdate[] memory tempPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](iterationCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < iterationCount; i++) {
            IOMFListingTemplate.PayoutUpdate[] memory updates = settleSingleShortLiquid(listingAddress, orderIdentifiers[i]);
            if (updates.length == 0) {
                continue;
            }
            tempPayoutUpdates[updateIndex++] = updates[0];
        }
        IOMFListingTemplate.PayoutUpdate[] memory finalPayoutUpdates = new IOMFListingTemplate.PayoutUpdate[](updateIndex);
        for (uint256 i = 0; i < updateIndex; i++) {
            finalPayoutUpdates[i] = tempPayoutUpdates[i];
        }
        if (updateIndex > 0) {
            listingContract.ssUpdate(address(this), finalPayoutUpdates);
        }
    }

    function deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user) external onlyValidListing(listingAddress) nonReentrant {
        // Deposits ERC-20 tokens to liquidity pool
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        address tokenAddress = isTokenA ? listingContract.token0View() : listingContract.baseTokenView();
        uint256 preBalance = IERC20(tokenAddress).balanceOf(address(this));
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), inputAmount);
        uint256 postBalance = IERC20(tokenAddress).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        require(receivedAmount > 0, "No tokens received");
        IERC20(tokenAddress).approve(liquidityAddr, receivedAmount);
        try liquidityContract.deposit(user, tokenAddress, receivedAmount) {} catch {
            revert("Deposit failed");
        }
    }

    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user) external onlyValidListing(listingAddress) nonReentrant {
        // Withdraws tokens from liquidity pool
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        IOMFLiquidityTemplate.PreparedWithdrawal memory withdrawal;
        if (isX) {
            try liquidityContract.xPrepOut(user, inputAmount, index) returns (IOMFLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.xExecuteOut(user, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        } else {
            try liquidityContract.yPrepOut(user, inputAmount, index) returns (IOMFLiquidityTemplate.PreparedWithdrawal memory w) {
                withdrawal = w;
            } catch {
                revert("Withdrawal preparation failed");
            }
            try liquidityContract.yExecuteOut(user, index, withdrawal) {} catch {
                revert("Withdrawal execution failed");
            }
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user) external onlyValidListing(listingAddress) nonReentrant {
        // Claims fees from liquidity pool
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        try liquidityContract.claimFees(user, listingAddress, liquidityIndex, isX, volumeAmount) {} catch {
            revert("Claim fees failed");
        }
    }

    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external onlyValidListing(listingAddress) nonReentrant {
        // Clears a single order
        _clearOrderData(listingAddress, orderIdentifier, isBuyOrder);
    }

    function clearOrders(address listingAddress, uint256 maxIterations) external onlyValidListing(listingAddress) nonReentrant {
        // Clears multiple orders up to maxIterations
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        uint256[] memory buyOrderIds = listingContract.pendingBuyOrdersView();
        uint256 buyIterationCount = maxIterations < buyOrderIds.length ? maxIterations : buyOrderIds.length;
        for (uint256 i = 0; i < buyIterationCount; i++) {
            _clearOrderData(listingAddress, buyOrderIds[i], true);
        }
        uint256[] memory sellOrderIds = listingContract.pendingSellOrdersView();
        uint256 sellIterationCount = maxIterations < sellOrderIds.length ? maxIterations : sellOrderIds.length;
        for (uint256 k = 0; k < sellIterationCount; k++) {
            _clearOrderData(listingAddress, sellOrderIds[k], false);
        }
    }

    function changeDepositor(
        address listingAddress,
        bool isX,
        uint256 slotIndex,
        address newDepositor,
        address user
    ) external onlyValidListing(listingAddress) nonReentrant {
        // Changes depositor for a liquidity slot
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        address liquidityAddr = listingContract.liquidityAddressView(listingContract.listingIdView());
        IOMFLiquidityTemplate liquidityContract = IOMFLiquidityTemplate(liquidityAddr);
        require(liquidityContract.routersView(address(this)), "Router not registered");
        require(user != address(0), "Invalid user address");
        require(newDepositor != address(0), "Invalid new depositor");
        try liquidityContract.changeSlotDepositor(user, isX, slotIndex, newDepositor) {} catch {
            revert("Failed to change depositor");
        }
    }
}