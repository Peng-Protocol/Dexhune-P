// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.6
// Changes:
// - Added tax-on-transfer adjustment via adjustOrder function.
// - Replaced block.timestamp with order counter via IOMFListing.nextOrderId().
// - Fixed adjustOrder to overwrite original orderId.
// - Updated prep$Order to return orderId for tax adjustment.

library OMFOrderLibrary {
    struct OrderData {
        bool isBuy;
        uint256 amount;
        uint256 orderId;
        uint256 maxPrice;
        uint256 minPrice;
        address recipient;
    }

    function prep$Order(
        address listing,
        bool isBuy,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external returns (uint256 principal, uint256 fee, uint256 orderId) {
        require(amount > 0, "Invalid amount");
        uint256 feeRate = 5; // 0.05% = 5 basis points
        fee = (amount * feeRate) / 10000;
        principal = amount - fee;
        orderId = IOMFListing(listing).nextOrderId(); // Use counter
        OrderData memory data = OrderData(isBuy, principal, orderId, maxPrice, minPrice, recipient);
        execute$Order(listing, data);
        return (principal, fee, orderId);
    }

    function execute$Order(address listing, OrderData memory data) internal {
        IOMFListing listingContract = IOMFListing(listing);
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](1);
        updates[0] = IOMFListing.UpdateType(
            data.isBuy ? 1 : 2,
            data.orderId,
            data.amount,
            msg.sender,
            data.recipient,
            data.maxPrice,
            data.minPrice
        );
        listingContract.update(msg.sender, updates);
    }

    function adjustOrder(
        address listing,
        bool isBuy,
        uint256 actualAmount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        OrderData memory data = OrderData(isBuy, actualAmount, orderId, maxPrice, minPrice, recipient);
        execute$Order(listing, data);
    }

    function clearSingleOrder(
        address listing,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listingContract = IOMFListing(listing);
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](1);
        updates[0] = IOMFListing.UpdateType(
            isBuy ? 1 : 2,
            orderId,
            0,
            address(0),
            address(0),
            0,
            0
        );
        listingContract.update(proxy, updates);
    }

    function clearOrders(
        address listing,
        address listingAgent,
        address proxy
    ) external {
        IOMFListing listingContract = IOMFListing(listing);
        uint256[] memory buyIds = listingContract.pendingBuyOrdersView();
        uint256[] memory sellIds = listingContract.pendingSellOrdersView();
        IOMFListing.UpdateType[] memory updates = new IOMFListing.UpdateType[](buyIds.length + sellIds.length);
        uint256 i;
        for (i = 0; i < buyIds.length; i++) {
            updates[i] = IOMFListing.UpdateType(1, buyIds[i], 0, address(0), address(0), 0, 0);
        }
        for (uint256 j = 0; j < sellIds.length; j++) {
            updates[i + j] = IOMFListing.UpdateType(2, sellIds[j], 0, address(0), address(0), 0, 0);
        }
        listingContract.update(proxy, updates);
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
    function nextOrderId() external returns (uint256);
    function update(address caller, UpdateType[] memory updates) external;
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function liquidityAddresses(uint256 listingId) external view returns (address);
}