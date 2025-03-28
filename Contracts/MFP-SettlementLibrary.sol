// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.20

import "./imports/SafeERC20.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IMFPListing {
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
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function buyOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint256 timestamp,
        uint256 blockNumber,
        uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint256 timestamp,
        uint256 blockNumber,
        uint8 status
    );
    function pendingBuyOrders(uint256 listingId) external view returns (uint256[] memory);
    function pendingSellOrders(uint256 listingId) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
}

library MFPSettlementLibrary {
    using SafeERC20 for IERC20;

    struct PreparedUpdate {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
        address recipient;
    }

    function prepBuyOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingBuyOrders(0);
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (
                address makerAddress,
                address recipient,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                ,
                ,
                ,
                uint8 status
            ) = listing.buyOrders(pendingOrders[i]);
            uint256 currentPrice = listing.prices(0);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(0);
                uint256 available = yBalance > pending ? pending : yBalance;
                if (available > 0) {
                    updates[updateCount] = PreparedUpdate(pendingOrders[i], true, available, recipient);
                    updateCount++;
                }
            }
        }
        assembly { mstore(updates, updateCount) }
        return updates;
    }

    function prepSellOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingSellOrders(0);
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (
                address makerAddress,
                address recipient,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                ,
                ,
                ,
                uint8 status
            ) = listing.sellOrders(pendingOrders[i]);
            uint256 currentPrice = listing.prices(0);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                (uint256 xBalance, , , ) = listing.volumeBalances(0);
                uint256 available = xBalance > pending ? pending : xBalance;
                if (available > 0) {
                    updates[updateCount] = PreparedUpdate(pendingOrders[i], false, available, recipient);
                    updateCount++;
                }
            }
        }
        assembly { mstore(updates, updateCount) }
        return updates;
    }

    function executeBuyOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                address token = listing.tokenA();
                uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
                uint256 rawAmount = denormalize(preparedUpdates[i].amount, decimals);
                uint256 preBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                listing.transact(proxy, token, rawAmount, preparedUpdates[i].recipient);
                uint256 postBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                uint256 actualReceived = postBalance - preBalance;
                uint256 adjustedAmount = actualReceived < rawAmount ? normalize(actualReceived, decimals) : preparedUpdates[i].amount;
                updates[updateCount] = IMFPListing.UpdateType(1, preparedUpdates[i].orderId, adjustedAmount, address(0), preparedUpdates[i].recipient, 0, 0);
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }

    function executeSellOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                address token = listing.tokenB();
                uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
                uint256 rawAmount = denormalize(preparedUpdates[i].amount, decimals);
                uint256 preBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                listing.transact(proxy, token, rawAmount, preparedUpdates[i].recipient);
                uint256 postBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                uint256 actualReceived = postBalance - preBalance;
                uint256 adjustedAmount = actualReceived < rawAmount ? normalize(actualReceived, decimals) : preparedUpdates[i].amount;
                updates[updateCount] = IMFPListing.UpdateType(2, preparedUpdates[i].orderId, adjustedAmount, address(0), preparedUpdates[i].recipient, 0, 0);
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10**(18 - decimals);
        else return amount / 10**(decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - decimals);
        else return amount * 10**(decimals - 18);
    }
}