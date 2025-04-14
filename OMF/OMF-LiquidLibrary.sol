// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.9 (Updated)
// Changes:
// - From v0.0.8: Removed listingId from all functions to align with implicit listingId in OMFListingTemplate.
// - Updated inlined IOMFListing calls: Changed liquidityAddresses() to liquidityAddress().
// - Renamed tokenA to token0, tokenB to baseToken (Token-0 to Token-1) (from v0.0.7).
// - Adjusted settlement to use transact from listing, removed direct deposit/withdraw (from v0.0.7).
// - Fully inlined all interfaces (IOMFListing, IOMFLiquidity) within functions (from v0.0.7).
// - Fixed UpdateType scoping to OMFLiquidLibrary.UpdateType (from v0.0.8).
// - Aligned order decoding to 7-element struct (from v0.0.8).
// - Fixed stack-too-deep in prepBuyLiquid/prepSellLiquid: Added PrepState struct and helper functions (from v0.0.8).

import "./imports/SafeERC20.sol";

library OMFLiquidLibrary {
    using SafeERC20 for IERC20;

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

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct PrepState {
        address token0;
        address baseToken;
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
            (bool success0, bytes memory data0) = listingAddress.staticcall(abi.encodeWithSignature("token0()"));
            (bool success1, bytes memory data1) = listingAddress.staticcall(abi.encodeWithSignature("baseToken()"));
            require(success0 && success1, "Token fetch failed");
            state.token0 = abi.decode(data0, (address));
            state.baseToken = abi.decode(data1, (address));
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
            (bool success, bytes memory returnData) = listingAddress.staticcall(
                abi.encodeWithSignature("buyOrders(uint256)", orderIds[i])
            );
            require(success, "Buy order fetch failed");
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = abi.decode(returnData, (address, address, uint256, uint256, uint256, uint256, uint8));
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
            (bool success0, bytes memory data0) = listingAddress.staticcall(abi.encodeWithSignature("token0()"));
            (bool success1, bytes memory data1) = listingAddress.staticcall(abi.encodeWithSignature("baseToken()"));
            require(success0 && success1, "Token fetch failed");
            state.token0 = abi.decode(data0, (address));
            state.baseToken = abi.decode(data1, (address));
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
            (bool success, bytes memory returnData) = listingAddress.staticcall(
                abi.encodeWithSignature("sellOrders(uint256)", orderIds[i])
            );
            require(success, "Sell order fetch failed");
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = abi.decode(returnData, (address, address, uint256, uint256, uint256, uint256, uint8));
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
        uint256 price;
        {
            (bool success, bytes memory returnData) = listingAddress.staticcall(abi.encodeWithSignature("getPrice()"));
            require(success, "Price fetch failed");
            price = abi.decode(returnData, (uint256));
        }

        OMFLiquidLibrary.UpdateType[] memory updates = new OMFLiquidLibrary.UpdateType[](data.orderCount);
        uint256 totalToken0;

        for (uint256 i = 0; i < data.orderCount; i++) {
            uint256 token0Amount = data.updates[i].value;
            uint256 token1Amount = (token0Amount * 1e18) / price;
            totalToken0 += token0Amount;

            (bool success, ) = listingAddress.call(
                abi.encodeWithSignature(
                    "transact(address,address,uint256,address)",
                    proxy,
                    data.baseToken,
                    token1Amount,
                    data.updates[i].recipient
                )
            );
            require(success, "Transact failed");

            updates[i] = OMFLiquidLibrary.UpdateType(1, data.updates[i].orderId, 0, address(0), data.updates[i].recipient, 0, 0);
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
        uint256 price;
        {
            (bool success, bytes memory returnData) = listingAddress.staticcall(abi.encodeWithSignature("getPrice()"));
            require(success, "Price fetch failed");
            price = abi.decode(returnData, (uint256));
        }

        OMFLiquidLibrary.UpdateType[] memory updates = new OMFLiquidLibrary.UpdateType[](data.orderCount + 1);
        uint256 totalToken0;

        for (uint256 i = 0; i < data.orderCount; i++) {
            uint256 token0Amount = data.updates[i].value;
            uint256 token1Amount = (token0Amount * price) / 1e18;
            totalToken0 += token0Amount;

            (bool success, ) = listingAddress.call(
                abi.encodeWithSignature(
                    "transact(address,address,uint256,address)",
                    proxy,
                    data.baseToken,
                    token1Amount,
                    data.updates[i].recipient
                )
            );
            require(success, "Transact failed");

            updates[i] = OMFLiquidLibrary.UpdateType(2, data.updates[i].orderId, 0, address(0), data.updates[i].recipient, 0, 0);
        }

        updates[data.orderCount] = OMFLiquidLibrary.UpdateType(0, 0, totalToken0, data.token0, address(0), 0, 0);
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
        address liquidity;
        {
            (bool success, bytes memory returnData) = listingAddress.staticcall(
                abi.encodeWithSignature("liquidityAddress()")
            );
            require(success, "Liquidity address fetch failed");
            liquidity = abi.decode(returnData, (address));
        }

        (bool success, ) = liquidity.call(
            abi.encodeWithSignature("claimFees(address,bool,uint256,uint256)", msg.sender, isX, 0, volume)
        );
        require(success, "Claim fees failed");
    }
}