// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.13 (Updated)
// Changes:
// - Converted from library to abstract contract to support potential future interface declarations and avoid Remix AI library interface warnings.
// - Updated helper function performTransactionAndAdjust to public to maintain external accessibility.
// - Retained processPrepBuyLiquid, processPrepSellLiquid as internal, as used only within prepBuyLiquid/prepSellLiquid.
// - Retained OMFShared.SafeERC20 usage, with single SafeERC20 import in OMF-Shared.sol.
// - From v0.0.12: Removed SafeERC20 import, added OMF-Shared.sol.
// - From v0.0.12: Replaced inlined IOMFListing/IOMFLiquidity calls with OMFShared.IOMFListing/IOMFLiquidity.
// - From v0.0.12: Updated UpdateType to OMFShared.UpdateType.
// - From v0.0.12: Removed normalize/denormalize functions, used OMFShared.normalize/denormalize.
// - From v0.0.10: Added normalize/denormalize functions (now in OMFShared).
// - From v0.0.10: Added performTransactionAndAdjust to denormalize amounts, check actual received, and adjust UpdateType.value.
// - From v0.0.10: Updated executeBuyLiquid to use performTransactionAndAdjust and set UpdateType.value to actualReceived.
// - From v0.0.10: Updated executeSellLiquid to use performTransactionAndAdjust and set UpdateType.value to actualReceived.
// - From v0.0.8: Removed listingId from all functions to align with OMFListingTemplate.
// - From v0.0.8: Fixed UpdateType scoping to OMFShared.UpdateType.
// - From v0.0.8: Fixed stack-too-deep in prepBuyLiquid/prepSellLiquid with PrepState struct and helpers.
// - From v0.0.7: Updated inlined IOMFListing calls: Changed liquidityAddresses() to liquidityAddress().
// - From v0.0.7: Renamed tokenA to token0, tokenB to baseToken (Token-0 to Token-1).
// - From v0.0.7: Adjusted settlement to use transact from listing, removed direct deposit/withdraw.
// - From v0.0.7: Fully inlined all interfaces (now explicit via OMFShared).
// - Side effects: Ensures tax-on-transfer adjustments are reflected in state updates; supports non-18 decimal tokens.

import "./OMF-Shared.sol";

abstract contract OMFLiquidLibrary {
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
        uint256 rawAmount = OMFShared.denormalize(amount, decimals);
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
        actualReceived = OMFShared.normalize(postBalance - preBalance, decimals);
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