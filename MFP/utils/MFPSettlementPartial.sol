// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.7 (01/10)
// Changes:
// - v0.1.7 (01/10): Commented out unused parameters (amount in _computeAmountSent, listingAddress in _validateOrderParams and _executeOrderSwap, settlementContext in _computeSwapAmount) to silence warnings.
// - v0.1.6 (01/10): Updated _computeSwapAmount to cap swapAmount to pendingAmount after impact adjustment to prevent over-transfer. Added detailed error messages for edge cases (zero balance, invalid price, insufficient pending amount). Ensured no overlapping calls by streamlining _applyOrderUpdate flow. Removed redundant _updateFilledAndStatus function.
// - v0.1.5: Redid 0.1.4, adjusted _executeOrderSwap and _prepareUpdateData (29/9).
// - v0.1.4: Updated _prepareUpdateData to accumulate amountSent by adding context.amountSent to prior context.amountSent, ensuring no overwrite of prior values (29/9).
// - v0.1.3: Modified _executeOrderSwap to revert on transfer failure instead of setting amountSent to 0, ensuring batch halts and no updates occur if transfer fails. This prevents overwriting prior amountSent values. Renamed "OrderFailed" to "OrderSkipped".
// - v0.1.2: Implemented non-reverting behavior for _validateOrderParams and _checkPricing, emitting OrderFailed event instead of reverting. Updated _executeOrderSwap to correctly calculate amountSent using pre/post balance checks. Modified _prepareUpdateData to set status based on pending amount after update (status = 3 if pending <= 0).
// - v0.1.1: Updated validation to check status >= 1 && < 3, accumulate filled and amountSent
// - v0.1.0: Initial implementation, removes Uniswap V2 logic from CCSettlementPartial.sol. Implements direct transfer settlement with impact price and partial settlement logic per instructions. Includes uint2str for error messages. Compatible with CCListingTemplate.sol (v0.3.9), CCMainPartial.sol (v0.1.5), MFPSettlementRouter.sol (v0.1.4).

import "./CCMainPartial.sol";

contract MFPSettlementPartial is CCMainPartial {
    struct OrderProcessContext {
        uint256 orderId;
        uint256 pendingAmount;
        uint256 filled;
        uint256 amountSent;
        address makerAddress;
        address recipientAddress;
        uint8 status;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 currentPrice;
        uint256 maxAmountIn;
        uint256 swapAmount;
        ICCListing.BuyOrderUpdate[] buyUpdates;
        ICCListing.SellOrderUpdate[] sellUpdates;
    }

    struct SettlementContext {
        address tokenA;
        address tokenB;
        uint8 decimalsA;
        uint8 decimalsB;
        address uniswapV2Pair; // Unused, kept for compatibility
    }

    struct OrderContext {
        uint256 orderId;
        uint256 pending;
        uint8 status;
        ICCListing.BuyOrderUpdate[] buyUpdates;
        ICCListing.SellOrderUpdate[] sellUpdates;
    }

    event OrderSkipped(uint256 indexed orderId, string reason);

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        // Converts uint to string for error messages
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

    function _checkPricing(
        address listingAddress,
        uint256 orderIdentifier,
        bool isBuyOrder,
        uint256 pendingAmount
    ) internal returns (bool) {
        // Validates pricing, emits event on failure
        ICCListing listingContract = ICCListing(listingAddress);
        uint256 maxPrice;
        uint256 minPrice;
        if (isBuyOrder) {
            (maxPrice, minPrice) = listingContract.getBuyOrderPricing(orderIdentifier);
        } else {
            (maxPrice, minPrice) = listingContract.getSellOrderPricing(orderIdentifier);
        }
        uint256 currentPrice = listingContract.prices(0);
        if (currentPrice == 0) {
            emit OrderSkipped(orderIdentifier, string(abi.encodePacked("Invalid current price for order ", uint2str(orderIdentifier))));
            return false;
        }
        (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
        uint256 settlementBalance = isBuyOrder ? yBalance : xBalance;
        if (settlementBalance == 0) {
            emit OrderSkipped(orderIdentifier, string(abi.encodePacked("Zero settlement balance for order ", uint2str(orderIdentifier))));
            return false;
        }
        if (pendingAmount == 0) {
            emit OrderSkipped(orderIdentifier, string(abi.encodePacked("Zero pending amount for order ", uint2str(orderIdentifier))));
            return false;
        }
        uint256 impact = (pendingAmount * 1e18) / settlementBalance;
        uint256 impactPrice = isBuyOrder
            ? (currentPrice * (1e18 + impact)) / 1e18
            : (currentPrice * (1e18 - impact)) / 1e18;
        if (isBuyOrder && impactPrice > maxPrice || !isBuyOrder && impactPrice < minPrice) {
            emit OrderSkipped(orderIdentifier, string(abi.encodePacked("Price out of bounds for order ", uint2str(orderIdentifier), ": impactPrice=", uint2str(impactPrice))));
            return false;
        }
        return true;
    }

    function _computeAmountSent(
        address tokenAddress,
        address recipientAddress,
        uint256 /* amount */
    ) internal view returns (uint256 preBalance) {
        // Computes pre-transfer balance
        preBalance = tokenAddress == address(0)
            ? recipientAddress.balance
            : IERC20(tokenAddress).balanceOf(recipientAddress);
    }

    function _validateOrderParams(
        address /* listingAddress */,
        uint256 orderId,
        bool isBuyOrder,
        ICCListing listingContract
    ) internal returns (OrderProcessContext memory context, bool isValid) {
        // Validates order params, returns context and validity flag
        context.orderId = orderId;
        (context.pendingAmount, context.filled, context.amountSent) = isBuyOrder
            ? listingContract.getBuyOrderAmounts(orderId)
            : listingContract.getSellOrderAmounts(orderId);
        (context.makerAddress, context.recipientAddress, context.status) = isBuyOrder
            ? listingContract.getBuyOrderCore(orderId)
            : listingContract.getSellOrderCore(orderId);
        (context.maxPrice, context.minPrice) = isBuyOrder
            ? listingContract.getBuyOrderPricing(orderId)
            : listingContract.getSellOrderPricing(orderId);
        context.currentPrice = listingContract.prices(0);
        if (context.pendingAmount == 0) {
            emit OrderSkipped(orderId, string(abi.encodePacked("No pending amount for order ", uint2str(orderId))));
            return (context, false);
        }
        if (context.status < 1 || context.status >= 3) {
            emit OrderSkipped(orderId, string(abi.encodePacked("Invalid status ", uint2str(context.status), " for order ", uint2str(orderId))));
            return (context, false);
        }
        if (context.currentPrice == 0) {
            emit OrderSkipped(orderId, string(abi.encodePacked("Invalid current price for order ", uint2str(orderId))));
            return (context, false);
        }
        return (context, true);
    }

    function _computeSwapAmount(
        address listingAddress,
        bool isBuyOrder,
        OrderProcessContext memory context,
        SettlementContext memory /* settlementContext */
    ) internal returns (OrderProcessContext memory) {
        // Computes swap amount with partial settlement logic, caps to pendingAmount
        ICCListing listingContract = ICCListing(listingAddress);
        (uint256 xBalance, uint256 yBalance) = listingContract.volumeBalances(0);
        uint256 settlementBalance = isBuyOrder ? yBalance : xBalance;
        if (settlementBalance == 0) {
            emit OrderSkipped(context.orderId, string(abi.encodePacked("Zero balance for order ", uint2str(context.orderId))));
            return context;
        }
        uint256 impact = (context.pendingAmount * 1e18) / settlementBalance;
        uint256 impactPrice = isBuyOrder
            ? (context.currentPrice * (1e18 + impact)) / 1e18
            : (context.currentPrice * (1e18 - impact)) / 1e18;
        if (isBuyOrder && impactPrice > context.maxPrice || !isBuyOrder && impactPrice < context.minPrice) {
            // Partial settlement
            uint256 percentageDiff = isBuyOrder
                ? ((context.maxPrice * 100e18) / context.currentPrice - 100e18) / 1e18
                : ((context.currentPrice * 100e18) / context.minPrice - 100e18) / 1e18;
            context.swapAmount = (settlementBalance * percentageDiff) / 100;
            context.swapAmount = context.swapAmount > context.pendingAmount ? context.pendingAmount : context.swapAmount;
        } else {
            context.swapAmount = context.pendingAmount;
        }
        if (context.swapAmount == 0) {
            emit OrderSkipped(context.orderId, string(abi.encodePacked("Zero swap amount for order ", uint2str(context.orderId))));
            return context;
        }
        // Cap swapAmount to pendingAmount to prevent over-transfer
        context.swapAmount = context.swapAmount > context.pendingAmount ? context.pendingAmount : context.swapAmount;
        context.maxAmountIn = context.swapAmount;
        return context;
    }

    function _executeOrderSwap(
        address /* listingAddress */,
        bool isBuyOrder,
        OrderProcessContext memory context,
        ICCListing listingContract
    ) internal returns (OrderProcessContext memory) {
        // Executes swap with accurate pre/post balance checks, reverts on transfer failure
        address tokenToSend = isBuyOrder ? listingContract.tokenA() : listingContract.tokenB();
        uint8 decimals = isBuyOrder ? listingContract.decimalsA() : listingContract.decimalsB();
        uint256 amountToSend = denormalize(context.swapAmount, decimals);
        if (amountToSend == 0) {
            emit OrderSkipped(context.orderId, string(abi.encodePacked("Zero transfer amount for order ", uint2str(context.orderId))));
            return context;
        }
        uint256 preBalance = _computeAmountSent(tokenToSend, context.recipientAddress, amountToSend);
        if (tokenToSend == address(0)) {
            try listingContract.transactNative{value: amountToSend}(amountToSend, context.recipientAddress) {
                context.amountSent += (_computeAmountSent(tokenToSend, context.recipientAddress, amountToSend) - preBalance);
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Native transfer failed for order ", uint2str(context.orderId), ": ", reason)));
            }
        } else {
            try listingContract.transactToken(tokenToSend, amountToSend, context.recipientAddress) {
                context.amountSent += (_computeAmountSent(tokenToSend, context.recipientAddress, amountToSend) - preBalance);
            } catch Error(string memory reason) {
                revert(string(abi.encodePacked("Token transfer failed for order ", uint2str(context.orderId), ": ", reason)));
            }
        }
        return context;
    }

    function _extractPendingAmount(
        OrderProcessContext memory context,
        bool isBuyOrder
    ) internal pure returns (uint256 pending) {
        if (isBuyOrder && context.buyUpdates.length > 0) {
            return context.buyUpdates[0].pending;
        } else if (!isBuyOrder && context.sellUpdates.length > 0) {
            return context.sellUpdates[0].pending;
        }
        return context.pendingAmount;
    }

    function _prepareUpdateData(
        OrderProcessContext memory context,
        bool isBuyOrder
    ) internal pure returns (
        ICCListing.BuyOrderUpdate[] memory buyUpdates,
        ICCListing.SellOrderUpdate[] memory sellUpdates
    ) {
        // Prepares update data, sets status based on pending amount
        uint256 pendingAmount = _extractPendingAmount(context, isBuyOrder);
        uint256 newPending = pendingAmount > context.swapAmount ? pendingAmount - context.swapAmount : 0;
        uint256 newFilled = context.filled + context.swapAmount;
        uint8 newStatus = newPending == 0 ? 3 : 2;

        if (isBuyOrder) {
            buyUpdates = new ICCListing.BuyOrderUpdate[](2);
            buyUpdates[0] = ICCListing.BuyOrderUpdate({
                structId: 2,
                orderId: context.orderId,
                makerAddress: context.makerAddress,
                recipientAddress: context.recipientAddress,
                status: context.status,
                maxPrice: 0,
                minPrice: 0,
                pending: newPending,
                filled: newFilled,
                amountSent: context.amountSent
            });
            buyUpdates[1] = ICCListing.BuyOrderUpdate({
                structId: 0,
                orderId: context.orderId,
                makerAddress: context.makerAddress,
                recipientAddress: context.recipientAddress,
                status: newStatus,
                maxPrice: 0,
                minPrice: 0,
                pending: 0,
                filled: 0,
                amountSent: 0
            });
            sellUpdates = new ICCListing.SellOrderUpdate[](0);
        } else {
            sellUpdates = new ICCListing.SellOrderUpdate[](2);
            sellUpdates[0] = ICCListing.SellOrderUpdate({
                structId: 2,
                orderId: context.orderId,
                makerAddress: context.makerAddress,
                recipientAddress: context.recipientAddress,
                status: context.status,
                maxPrice: 0,
                minPrice: 0,
                pending: newPending,
                filled: newFilled,
                amountSent: context.amountSent
            });
            sellUpdates[1] = ICCListing.SellOrderUpdate({
                structId: 0,
                orderId: context.orderId,
                makerAddress: context.makerAddress,
                recipientAddress: context.recipientAddress,
                status: newStatus,
                maxPrice: 0,
                minPrice: 0,
                pending: 0,
                filled: 0,
                amountSent: 0
            });
            buyUpdates = new ICCListing.BuyOrderUpdate[](0);
        }
    }

    function _applyOrderUpdate(
        address listingAddress,
        ICCListing listingContract,
        OrderProcessContext memory context,
        bool isBuyOrder
    ) internal returns (
        ICCListing.BuyOrderUpdate[] memory buyUpdates,
        ICCListing.SellOrderUpdate[] memory sellUpdates
    ) {
        // Prepares update structs after executing swap
        context = _executeOrderSwap(listingAddress, isBuyOrder, context, listingContract);
        if (context.swapAmount == 0) {
            emit OrderSkipped(context.orderId, string(abi.encodePacked("No swap executed for order ", uint2str(context.orderId))));
            return (new ICCListing.BuyOrderUpdate[](0), new ICCListing.SellOrderUpdate[](0));
        }
        (buyUpdates, sellUpdates) = _prepareUpdateData(context, isBuyOrder);
        return (buyUpdates, sellUpdates);
    }

    function _processBuyOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract,
        SettlementContext memory settlementContext
    ) internal returns (ICCListing.BuyOrderUpdate[] memory buyUpdates) {
        // Processes buy order, skips invalid orders
        (OrderProcessContext memory context, bool isValid) = _validateOrderParams(listingAddress, orderIdentifier, true, listingContract);
        if (!isValid) {
            emit OrderSkipped(orderIdentifier, "Invalid buy order parameters");
            return new ICCListing.BuyOrderUpdate[](0);
        }
        context = _computeSwapAmount(listingAddress, true, context, settlementContext);
        if (context.swapAmount == 0) {
            emit OrderSkipped(orderIdentifier, "No swap amount calculated for buy order");
            return new ICCListing.BuyOrderUpdate[](0);
        }
        (buyUpdates, ) = _applyOrderUpdate(listingAddress, listingContract, context, true);
        return buyUpdates;
    }

    function _processSellOrder(
        address listingAddress,
        uint256 orderIdentifier,
        ICCListing listingContract,
        SettlementContext memory settlementContext
    ) internal returns (ICCListing.SellOrderUpdate[] memory sellUpdates) {
        // Processes sell order, skips invalid orders
        (OrderProcessContext memory context, bool isValid) = _validateOrderParams(listingAddress, orderIdentifier, false, listingContract);
        if (!isValid) {
            emit OrderSkipped(orderIdentifier, "Invalid sell order parameters");
            return new ICCListing.SellOrderUpdate[](0);
        }
        context = _computeSwapAmount(listingAddress, false, context, settlementContext);
        if (context.swapAmount == 0) {
            emit OrderSkipped(orderIdentifier, "No swap amount calculated for sell order");
            return new ICCListing.SellOrderUpdate[](0);
        }
        (, sellUpdates) = _applyOrderUpdate(listingAddress, listingContract, context, false);
        return sellUpdates;
    }
}