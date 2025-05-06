// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.14 (Updated)
// Changes:
// - Added import for OMFSharedUtils.sol to use normalize and denormalize functions.
// - Updated performTransactionAndAdjust to use OMFSharedUtils.normalize/denormalize (lines 44, 48).
// - From v0.0.13: Converted from library to abstract contract for interface declarations.
// - From v0.0.13: Made performTransactionAndAdjust public for accessibility.
// - From v0.0.12: Removed SafeERC20 import, used OMFShared.SafeERC20.
// - From v0.0.12: Replaced IOMFListing/IOMFLiquidity with OMFShared.IOMFListing/IOMFLiquidity.
// - From v0.0.12: Updated UpdateType to OMFShared.UpdateType.
// - From v0.0.10: Added performTransactionAndAdjust to handle tax-on-transfer tokens.
// - From v0.0.8: Removed listingId, aligned with OMFListingTemplate.
// - From v0.0.7: Renamed tokenA to token0, tokenB to baseToken.
// - From v0.0.7: Used transact for settlement, removed direct deposit/withdraw.
// - Side effects: Supports non-18 decimal and tax-on-transfer tokens.

import "./OMF-Shared.sol";
import "./OMFSharedUtils.sol";

abstract contract OMFLiquidAbstract {
    using OMFShared.SafeERC20 for IERC20;

    struct PreparedUpdate {
        uint256 orderId;
        uint256 value;
        address recipient;
    }

    struct SettlementData {
        uint256 orderCount;
        uint256[] orderIds;
        PreparedUpdate[] updates;
        address token0;    // Token-0 (listed token)
        address baseToken; // Token-1 (reference token)
    }

    struct PrepState {
        address token0;
        address baseToken;
    }

    function performTransactionAndAdjust(
        address listingAddress,
        address proxy,
        address token,
        uint256 amount,
        address recipient,
        uint8 decimals
    ) public returns (uint256 actualReceived) {
        uint256 rawAmount = OMFSharedUtils.denormalize(amount, decimals);
        uint256 preBalance = token == address(0) ? recipient.balance : IERC20(token).balanceOf(recipient);
        (bool success, ) = listingAddress.call(
            abi.encodeWithSignature(
                "transact(address,address,uint256,address)",
                proxy,
                token,
                rawAmount,
                recipient
            )
        );
        require(success, "Transact failed");
        uint256 postBalance = token == address(0) ? recipient.balance : IERC20(token).balanceOf(recipient);
        actualReceived = OMFSharedUtils.normalize(postBalance - preBalance, decimals);
    }

    function prepBuyLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        SettlementData memory data;
        data.orderCount = orderIds.length;
        data.orderIds = orderIds;
        data.updates = new PreparedUpdate[](orderIds.length);

        PrepState memory state;
        {
            state.token0 = OMFShared.IOMFListing(listingAddress).token0();
            state.baseToken = OMFShared.IOMFListing(listingAddress).baseToken();
        }
        data.token0 = state.token0;
        data.baseToken = state.baseToken;

        processPrepBuyLiquid(listingAddress, data, orderIds);
        return data;
    }

    function processPrepBuyLiquid(
        address listingAddress,
        SettlementData memory data,
        uint256[] memory orderIds
    ) internal view {
        for (uint256 i = 0; i < orderIds.length; i++) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = OMFShared.IOMFListing(listingAddress).buyOrders(orderIds[i]);
            require(status == 1, "Order not active");
            data.updates[i] = PreparedUpdate(orderIds[i], pending, recipientAddress);
        }
    }

    function prepSellLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        SettlementData memory data;
        data.orderCount = orderIds.length;
        data.orderIds = orderIds;
        data.updates = new PreparedUpdate[](orderIds.length);

        PrepState memory state;
        {
            state.token0 = OMFShared.IOMFListing(listingAddress).token0();
            state.baseToken = OMFShared.IOMFListing(listingAddress).baseToken();
        }
        data.token0 = state.token0;
        data.baseToken = state.baseToken;

        processPrepSellLiquid(listingAddress, data, orderIds);
        return data;
    }

    function processPrepSellLiquid(
        address listingAddress,
        SettlementData memory data,
        uint256[] memory orderIds
    ) internal view {
        for (uint256 i = 0; i < orderIds.length; i++) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = OMFShared.IOMFListing(listingAddress).sellOrders(orderIds[i]);
            require(status == 1, "Order not active");
            data.updates[i] = PreparedUpdate(orderIds[i], pending, recipientAddress);
        }
    }

    function executeBuyLiquid(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external {
        uint256 price = OMFShared.IOMFListing(listingAddress).getPrice();

        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](data.orderCount);
        uint256 totalToken0;
        uint8 baseTokenDecimals = data.baseToken == address(0) ? 18 : IERC20(data.baseToken).decimals();

        for (uint256 i = 0; i < data.orderCount; i++) {
            uint256 token0Amount = data.updates[i].value;
            uint256 token1Amount = (token0Amount * 1e18) / price;
            totalToken0 += token0Amount;

            uint256 actualReceived = performTransactionAndAdjust(
                listingAddress,
                proxy,
                data.baseToken,
                token1Amount,
                data.updates[i].recipient,
                baseTokenDecimals
            );

            updates[i] = OMFShared.UpdateType(
                1,
                data.updates[i].orderId,
                actualReceived,
                address(0),
                data.updates[i].recipient,
                0,
                0
            );
        }

        if (data.orderCount > 0) {
            (bool success, ) = listingAddress.call(
                abi.encodeWithSignature("update(address,(uint8,uint256,uint256,address,address,uint256,uint256)[])", proxy, updates)
            );
            require(success, "Update failed");
        }
    }

    function executeSellLiquid(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external {
        uint256 price = OMFShared.IOMFListing(listingAddress).getPrice();

        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](data.orderCount + 1);
        uint256 totalToken0;
        uint8 baseTokenDecimals = data.baseToken == address(0) ? 18 : IERC20(data.baseToken).decimals();

        for (uint256 i = 0; i < data.orderCount; i++) {
            uint256 token0Amount = data.updates[i].value;
            uint256 token1Amount = (token0Amount * price) / 1e18;
            totalToken0 += token0Amount;

            uint256 actualReceived = performTransactionAndAdjust(
                listingAddress,
                proxy,
                data.baseToken,
                token1Amount,
                data.updates[i].recipient,
                baseTokenDecimals
            );

            updates[i] = OMFShared.UpdateType(
                2,
                data.updates[i].orderId,
                actualReceived,
                address(0),
                data.updates[i].recipient,
                0,
                0
            );
        }

        updates[data.orderCount] = OMFShared.UpdateType(0, 0, totalToken0, data.token0, address(0), 0, 0);
        if (data.orderCount > 0) {
            (bool success, ) = listingAddress.call(
                abi.encodeWithSignature("update(address,(uint8,uint256,uint256,address,address,uint256,uint256)[])", proxy, updates)
            );
            require(success, "Update failed");
        }
    }

    function claimFees(
        address listingAddress,
        bool isX,
        uint256 volume
    ) external {
        address liquidity = OMFShared.IOMFListing(listingAddress).liquidityAddress();
        OMFShared.IOMFLiquidity(liquidity).claimFees(msg.sender, isX, 0, volume);
    }
}