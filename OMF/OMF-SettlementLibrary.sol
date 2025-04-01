// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4
// Changes:
// - Fixed E7: Added tax-on-transfer checks in executeBuyOrders/executeSellOrders.
// - Fixed E1: Inverted price for buy orders (tokenBAmount = tokenAAmount / price).
// - Fixed E2: Removed redundant decimal conversion, relying on OMFListingTemplate.getPrice().

import "./imports/SafeERC20.sol";

library OMFSettlementLibrary {
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
        address tokenA;
        address tokenB;
    }

    function prepBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        IOMFListing listing = IOMFListing(listingAddress);
        uint256[] memory pendingOrders = orderIds.length > 0 ? orderIds : listing.pendingBuyOrdersView();
        SettlementData memory data;
        data.orderIds = pendingOrders;
        data.updates = new PreparedUpdate[](pendingOrders.length);
        data.tokenA = listing.tokenA();
        data.tokenB = listing.tokenB();
        uint256 price = listing.getPrice(); // Normalized to 18 decimals

        for (uint256 i = 0; i < pendingOrders.length; i++) {
            (, , , , uint256 pending, , uint256 maxPrice, uint256 minPrice, uint8 status) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && price >= minPrice && price <= maxPrice) {
                data.updates[data.orderCount] = PreparedUpdate(pendingOrders[i], pending, address(0));
                data.orderCount++;
            }
        }
        assembly { mstore(data.updates, mstore(data.orderIds, data.orderCount)) }
        return data;
    }

    function executeBuyOrders(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](data.orderCount);
        uint256 totalTokenA;
        uint256 totalTokenB;
        uint256 price = listing.getPrice(); // Normalized to 18 decimals

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            (, address recipient, , , uint256 pending, , , , ) = listing.buyOrders(update.orderId);
            uint256 tokenAAmount = pending; // TokenA to spend (baseToken)
            uint256 tokenBAmount = (tokenAAmount * 1e18) / price; // E1: TokenB = TokenA / price
            totalTokenA += tokenAAmount;
            totalTokenB += tokenBAmount;
            uint256 preBalance = IERC20(data.tokenB).balanceOf(recipient);
            listing.transact(proxy, data.tokenB, tokenBAmount, recipient);
            uint256 postBalance = IERC20(data.tokenB).balanceOf(recipient);
            uint256 actualReceived = postBalance - preBalance;
            uint256 adjustedValue = (actualReceived * price) / 1e18; // E7: Adjust TokenA spent
            updates[i] = IOMFListing.UpdateType(
                1, update.orderId, pending > adjustedValue ? pending - adjustedValue : 0, address(0), recipient, 0, 0
            );
        }

        if (data.orderCount > 0) listing.update(proxy, updates);
    }

    function prepSellOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory) {
        IOMFListing listing = IOMFListing(listingAddress);
        uint256[] memory pendingOrders = orderIds.length > 0 ? orderIds : listing.pendingSellOrdersView();
        SettlementData memory data;
        data.orderIds = pendingOrders;
        data.updates = new PreparedUpdate[](pendingOrders.length);
        data.tokenA = listing.tokenA();
        data.tokenB = listing.tokenB();
        uint256 price = listing.getPrice();

        for (uint256 i = 0; i < pendingOrders.length; i++) {
            (, , , , uint256 pending, , uint256 maxPrice, uint256 minPrice, uint8 status) = listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && price >= minPrice && price <= maxPrice) {
                data.updates[data.orderCount] = PreparedUpdate(pendingOrders[i], pending, address(0));
                data.orderCount++;
            }
        }
        assembly { mstore(data.updates, mstore(data.orderIds, data.orderCount)) }
        return data;
    }

    function executeSellOrders(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listing = IOMFListing(listingAddress);
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](data.orderCount + 1);
        uint256 totalTokenA;
        uint256 totalTokenB;
        uint256 price = listing.getPrice();

        for (uint256 i = 0; i < data.orderCount; i++) {
            PreparedUpdate memory update = data.updates[i];
            (, address recipient, , , uint256 pending, , , , ) = listing.sellOrders(update.orderId);
            uint256 tokenAAmount = pending; // TokenA to send (Token-1)
            uint256 tokenBAmount = (tokenAAmount * price) / 1e18; // TokenB to receive
            totalTokenA += tokenAAmount;
            totalTokenB += tokenBAmount;
            uint256 preBalance = IERC20(data.tokenB).balanceOf(recipient);
            listing.transact(proxy, data.tokenB, tokenBAmount, recipient);
            uint256 postBalance = IERC20(data.tokenB).balanceOf(recipient);
            uint256 actualReceived = postBalance - preBalance;
            uint256 adjustedValue = (actualReceived * 1e18) / price; // E7: Adjust TokenA sent
            updates[i] = IOMFListing.UpdateType(
                2, update.orderId, pending > adjustedValue ? pending - adjustedValue : 0, address(0), recipient, 0, 0
            );
        }

        updates[data.orderCount] = IOMFListing.UpdateType(0, 0, totalTokenB, data.tokenB, address(0), 0, 0);
        if (data.orderCount > 0) listing.update(proxy, updates);
    }
}

interface IOMFListing {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function getPrice() external view returns (uint256);
    function oracleDecimals() external view returns (uint8);
    function buyOrders(uint256 orderId) external view returns (
        address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint8
    );
    function sellOrders(uint256 orderId) external view returns (
        address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint8
    );
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
}
