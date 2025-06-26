// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.27
// Changes: Removed all references to orderLibrary as it is depreciated. 
// Changes 0.0.26:
// - Fixed TypeError in processOrderSettlement by replacing invalid ternary operator in try-catch with if-else blocks for separate try-catch on this.executeBuyOrder and this.executeSellOrder.
// - Preserved all prior changes from v0.0.25 (stack depth fixes, helper functions, etc.).

import "./utils/MFPSettlementPartial.sol";

contract MFPRouter is MFPSettlementPartial {
    using SafeERC20 for IERC20;

    address public listingAgent;
    address public agent;
    address public registryAddress;

    // Struct to group common variables and reduce stack usage
    struct OrderContext {
        address tokenA;
        address tokenB;
        uint256 listingId;
        address liquidityAddress;
    }

    event OrderSettlementSkipped(uint256 orderId, string reason);
    event OrderSettlementFailed(uint256 orderId, string reason);

    function setListingAgent(address _listingAgent) external onlyOwner {
        require(_listingAgent != address(0), "Invalid listing agent");
        listingAgent = _listingAgent;
    }

    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
    }

    function setRegistry(address _registryAddress) external onlyOwner {
        require(_registryAddress != address(0), "Invalid registry");
        registryAddress = _registryAddress;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure override returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (18 - decimals);
        else return amount / 10 ** (decimals - 18);
    }

    function _transferToken(address token, address from, address to, uint256 amount) internal override {
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            if (to != address(this)) {
                (bool success, ) = to.call{value: amount}("");
                require(success, "ETH transfer failed");
            }
        } else {
            if (from == address(this)) {
                IERC20(token).safeTransfer(to, amount);
            } else {
                IERC20(token).safeTransferFrom(from, to, amount);
            }
        }
    }

    // Helper to validate listing and retrieve context
    function validateListing(address listingAddress) internal view returns (OrderContext memory) {
        address tokenA = IMFPListing(listingAddress).tokenA();
        address tokenB = IMFPListing(listingAddress).tokenB();
        require(IMFPAgent(agent).getListing(tokenA, tokenB) == listingAddress, "Listing not registered in agent");
        uint256 listingId = IMFPListing(listingAddress).getListingId();
        address liquidityAddress = IMFPListing(listingAddress).liquidityAddress();
        return OrderContext(tokenA, tokenB, listingId, liquidityAddress);
    }

    // Helper to transfer tokens for order creation
    function transferOrderToken(address token, uint256 amount, address sender) internal returns (uint256) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        _transferToken(token, sender, address(this), amount);
        return normalizedAmount;
    }

    // Helper to prepare combined updates for order creation
    function prepareOrderUpdates(
        uint256 listingId,
        uint256 orderId,
        address maker,
        address recipient,
        uint256 normalizedAmount,
        uint256 maxPrice,
        uint256 minPrice,
        bool isBuy
    ) internal view returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory coreUpdates = isBuy
            ? prepBuyOrderCore(listingId, orderId, maker, recipient)
            : prepSellOrderCore(listingId, orderId, maker, recipient);
        IMFPListing.ListingUpdateType[] memory pricingUpdates = isBuy
            ? prepBuyOrderPricing(listingId, orderId, maxPrice, minPrice)
            : prepSellOrderPricing(listingId, orderId, maxPrice, minPrice);
        IMFPListing.ListingUpdateType[] memory amounts = isBuy
            ? prepBuyOrderAmounts(listingId, orderId, normalizedAmount)
            : prepSellOrderAmounts(listingId, orderId, normalizedAmount);

        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](
            coreUpdates.length + pricingUpdates.length + amounts.length
        );
        uint256 index = 0;
        for (uint256 i = 0; i < coreUpdates.length; i++) updates[index++] = coreUpdates[i];
        for (uint256 i = 0; i < pricingUpdates.length; i++) updates[index++] = pricingUpdates[i];
        for (uint256 i = 0; i < amounts.length; i++) updates[index++] = amounts[i];

        return updates;
    }

    // Helper to validate settlement inputs for liquid functions
    function validateLiquidSettlement(address listingAddress, uint256[] memory orderIds, uint256[] memory amounts)
        internal
        view
        returns (OrderContext memory)
    {
        OrderContext memory context = validateListing(listingAddress);
        require(orderIds.length == amounts.length, "Array length mismatch");
        require(context.liquidityAddress != address(0), "Liquidity address not set");
        return context;
    }

    // Helper to process individual order settlements
    function processOrderSettlement(
        address listingAddress,
        uint256 orderId,
        uint256 amount,
        bool isBuy,
        IMFPListing.ListingUpdateType[] memory tempUpdates,
        uint256 index
    ) internal returns (uint256 newIndex, uint256 amountSettled) {
        if (isBuy) {
            try this.executeBuyOrder(listingAddress, orderId, amount) returns (IMFPListing.ListingUpdateType[] memory updates) {
                if (updates.length == 0) {
                    emit OrderSettlementSkipped(orderId, "Invalid price range");
                    return (index, 0);
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[index++] = updates[j];
                }
                return (index, amount);
            } catch Error(string memory reason) {
                emit OrderSettlementFailed(orderId, reason);
                return (index, 0);
            } catch {
                emit OrderSettlementFailed(orderId, "Unknown error");
                return (index, 0);
            }
        } else {
            try this.executeSellOrder(listingAddress, orderId, amount) returns (IMFPListing.ListingUpdateType[] memory updates) {
                if (updates.length == 0) {
                    emit OrderSettlementSkipped(orderId, "Invalid price range");
                    return (index, 0);
                }
                for (uint256 j = 0; j < updates.length; j++) {
                    tempUpdates[index++] = updates[j];
                }
                return (index, amount);
            } catch Error(string memory reason) {
                emit OrderSettlementFailed(orderId, reason);
                return (index, 0);
            } catch {
                emit OrderSettlementFailed(orderId, "Unknown error");
                return (index, 0);
            }
        }
    }

    // Helper to finalize settlement updates
    function finalizeSettlement(
        address listingAddress,
        IMFPListing.ListingUpdateType[] memory tempUpdates,
        uint256 index
    ) internal returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory finalUpdates = new IMFPListing.ListingUpdateType[](index);
        for (uint256 i = 0; i < index; i++) {
            finalUpdates[i] = tempUpdates[i];
        }
        if (index > 0) {
            IMFPListing(listingAddress).update(finalUpdates);
        }
        return finalUpdates;
    }

    function createBuyOrder(
        address listingAddress,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external payable nonReentrant returns (IMFPListing.ListingUpdateType[] memory) {
        OrderContext memory context = validateListing(listingAddress);
        uint256 normalizedAmount = transferOrderToken(context.tokenB, amount, msg.sender);
        uint256 orderId = IMFPListing(listingAddress).nextOrderId();

        IMFPListing.ListingUpdateType[] memory updates = prepareOrderUpdates(
            context.listingId,
            orderId,
            msg.sender,
            recipient,
            normalizedAmount,
            maxPrice,
            minPrice,
            true
        );

        IMFPListing(listingAddress).update(updates);
        emit OrderCreated(listingAddress, msg.sender, normalizedAmount, true);
        return updates;
    }

    function createSellOrder(
        address listingAddress,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external payable nonReentrant returns (IMFPListing.ListingUpdateType[] memory) {
        OrderContext memory context = validateListing(listingAddress);
        uint256 normalizedAmount = transferOrderToken(context.tokenA, amount, msg.sender);
        uint256 orderId = IMFPListing(listingAddress).nextOrderId();

        IMFPListing.ListingUpdateType[] memory updates = prepareOrderUpdates(
            context.listingId,
            orderId,
            msg.sender,
            recipient,
            normalizedAmount,
            maxPrice,
            minPrice,
            false
        );

        IMFPListing(listingAddress).update(updates);
        emit OrderCreated(listingAddress, msg.sender, normalizedAmount, false);
        return updates;
    }

    function settleBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory) {
        OrderContext memory context = validateListing(listingAddress);
        require(orderIds.length == amounts.length, "Array length mismatch");
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            (index, ) = processOrderSettlement(listingAddress, orderIds[i], amounts[i], true, tempUpdates, index);
        }

        return finalizeSettlement(listingAddress, tempUpdates, index);
    }

    function settleSellOrders(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory) {
        OrderContext memory context = validateListing(listingAddress);
        require(orderIds.length == amounts.length, "Array length mismatch");
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            (index, ) = processOrderSettlement(listingAddress, orderIds[i], amounts[i], false, tempUpdates, index);
        }

        return finalizeSettlement(listingAddress, tempUpdates, index);
    }

    function settleBuyLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory) {
        OrderContext memory context = validateLiquidSettlement(listingAddress, orderIds, amounts);
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 amountSettled;
            (index, amountSettled) = processOrderSettlement(listingAddress, orderIds[i], amounts[i], true, tempUpdates, index);
            totalAmount += amountSettled;
        }

        IMFPListing.ListingUpdateType[] memory finalUpdates = finalizeSettlement(listingAddress, tempUpdates, index);
        if (index > 0) {
            executeBuyLiquid(listingAddress, orderIds, amounts);
            if (totalAmount > 0) {
                IMFPLiquidityTemplate(context.liquidityAddress).addFees(address(this), false, totalAmount);
            }
        }
        return finalUpdates;
    }

    function settleSellLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        uint256[] memory amounts
    ) external nonReentrant returns (IMFPListing.ListingUpdateType[] memory) {
        OrderContext memory context = validateLiquidSettlement(listingAddress, orderIds, amounts);
        IMFPListing.ListingUpdateType[] memory tempUpdates = new IMFPListing.ListingUpdateType[](orderIds.length * 3);
        uint256 index = 0;
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 amountSettled;
            (index, amountSettled) = processOrderSettlement(listingAddress, orderIds[i], amounts[i], false, tempUpdates, index);
            totalAmount += amountSettled;
        }

        IMFPListing.ListingUpdateType[] memory finalUpdates = finalizeSettlement(listingAddress, tempUpdates, index);
        if (index > 0) {
            executeSellLiquid(listingAddress, orderIds, amounts);
            if (totalAmount > 0) {
                IMFPLiquidityTemplate(context.liquidityAddress).addFees(address(this), true, totalAmount);
            }
        }
        return finalUpdates;
    }

    function deposit(
        address listingAddress,
        bool isX,
        uint256 amount
    ) external payable nonReentrant {
        OrderContext memory context = validateListing(listingAddress);
        address token = isX ? context.tokenA : context.tokenB;
        require(context.liquidityAddress != address(0), "Liquidity address not set");
        _transferToken(token, msg.sender, context.liquidityAddress, amount);
        IMFPLiquidityTemplate(context.liquidityAddress).deposit(address(this), token, amount);
    }

    function withdraw(
        address listingAddress,
        bool isX,
        uint256 amount,
        uint256 index
    ) external nonReentrant {
        OrderContext memory context = validateListing(listingAddress);
        require(context.liquidityAddress != address(0), "Liquidity address not set");
        IMFPListing.PreparedWithdrawal memory withdrawal = isX
            ? IMFPLiquidityTemplate(context.liquidityAddress).xPrepOut(address(this), amount, index)
            : IMFPLiquidityTemplate(context.liquidityAddress).yPrepOut(address(this), amount, index);
        if (isX) {
            IMFPLiquidityTemplate(context.liquidityAddress).xExecuteOut(address(this), index, withdrawal);
        } else {
            IMFPLiquidityTemplate(context.liquidityAddress).yExecuteOut(address(this), index, withdrawal);
        }
    }

    function claimFees(
        address listingAddress,
        uint256 liquidityIndex,
        bool isX,
        uint256 volume
    ) external nonReentrant {
        OrderContext memory context = validateListing(listingAddress);
        require(context.liquidityAddress != address(0), "Liquidity address not set");
        IMFPLiquidityTemplate(context.liquidityAddress).claimFees(address(this), listingAddress, liquidityIndex, isX, volume);
    }

    function clearSingleOrder(address listingAddress, uint256 orderId) public nonReentrant override {
        OrderContext memory context = validateListing(listingAddress);
        clearSingleOrder(listingAddress, orderId);
    }

    function clearOrders(address listingAddress) public nonReentrant override {
        OrderContext memory context = validateListing(listingAddress);
        clearOrders(listingAddress);
    }

    function viewLiquidity(
        address listingAddress
    ) external view returns (uint256 xAmount, uint256 yAmount) {
        OrderContext memory context = validateListing(listingAddress);
        require(context.liquidityAddress != address(0), "Liquidity address not set");
        (xAmount, yAmount) = IMFPLiquidityTemplate(context.liquidityAddress).liquidityAmounts();
        return (xAmount, yAmount);
    }
}