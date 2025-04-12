// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.25 (Updated)
// Changes:
// - Removed listingId from pendingBuyOrders, pendingSellOrders, volumeBalances, prices calls; uses updated IMFPListing interface (new in v0.0.25).
// - Updated prepBuyOrders, prepSellOrders, executeBuyOrders, executeSellOrders to remove listingId parameters (new in v0.0.25).
// - Updated IMFPListing interface to remove listingId parameters (new in v0.0.25).
// - Side effects: Aligns with MFPListingTemplate’s stored listingId; maintains settlement logic.

import "./imports/SafeERC20.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IMFPListing {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function volumeBalances() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices() external view returns (uint256);
    function buyOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address makerAddress,
        address recipientAddress,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 pending,
        uint256 filled,
        uint8 status
    );
    function pendingBuyOrders() external view returns (uint256[] memory);
    function pendingSellOrders() external view returns (uint256[] memory);
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

    struct SettlementData {
        uint256 totalAmount;
        uint256 xBalance;
        uint256 yBalance;
        uint256 impactPrice;
    }

    function calculateImpactPrice(uint256 xBalance, uint256 yBalance, uint256 totalAmount, bool isBuy) internal pure returns (uint256) {
        uint256 newXBalance;
        uint256 newYBalance;
        if (isBuy) {
            newXBalance = xBalance - totalAmount;
            newYBalance = yBalance + totalAmount;
        } else {
            newXBalance = xBalance + totalAmount;
            newYBalance = yBalance - totalAmount;
        }
        require(newXBalance > 0 && newYBalance > 0, "Invalid post-settlement balances");
        return (newXBalance * 1e18) / newYBalance;
    }

    function prepBuyOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingBuyOrders();
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        SettlementData memory data;
        uint256 currentPrice = listing.prices();

        // Populate SettlementData and calculate total amount
        (data.xBalance, data.yBalance, , ) = listing.volumeBalances();
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (
                address makerAddress,
                address recipient,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                ,
                uint8 status
            ) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                uint256 available = data.yBalance > pending ? pending : data.yBalance;
                if (available > 0) {
                    data.totalAmount += available;
                    updates[updateCount] = PreparedUpdate(pendingOrders[i], true, available, recipient);
                    updateCount++;
                }
            }
        }

        // Adjust amounts with impact price
        if (updateCount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, true);
            for (uint256 i = 0; i < updateCount; i++) {
                (
                    address makerAddress,
                    address recipient,
                    uint256 maxPrice,
                    uint256 minPrice,
                    uint256 pending,
                    ,
                    uint8 status
                ) = listing.buyOrders(updates[i].orderId);
                if (data.impactPrice >= minPrice && data.impactPrice <= maxPrice) {
                    updates[i].amount = pending;
                } else if (data.impactPrice < minPrice) {
                    updates[i].amount = 0;
                } else {
                    uint256 maxAmount = (data.xBalance * maxPrice) / 1e18 - data.yBalance;
                    updates[i].amount = maxAmount < pending ? maxAmount : pending;
                }
            }
        }

        assembly { mstore(updates, updateCount) }
        return updates;
    }

    function prepSellOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingSellOrders();
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        SettlementData memory data;
        uint256 currentPrice = listing.prices();

        // Populate SettlementData and calculate total amount
        (data.xBalance, data.yBalance, , ) = listing.volumeBalances();
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (
                address makerAddress,
                address recipient,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                ,
                uint8 status
            ) = listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                uint256 available = data.xBalance > pending ? pending : data.xBalance;
                if (available > 0) {
                    data.totalAmount += available;
                    updates[updateCount] = PreparedUpdate(pendingOrders[i], false, available, recipient);
                    updateCount++;
                }
            }
        }

        // Adjust amounts with impact price
        if (updateCount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, false);
            for (uint256 i = 0; i < updateCount; i++) {
                (
                    address makerAddress,
                    address recipient,
                    uint256 maxPrice,
                    uint256 minPrice,
                    uint256 pending,
                    ,
                    uint8 status
                ) = listing.sellOrders(updates[i].orderId);
                if (data.impactPrice >= minPrice && data.impactPrice <= maxPrice) {
                    updates[i].amount = pending;
                } else if (data.impactPrice > maxPrice) {
                    updates[i].amount = 0;
                } else {
                    uint256 maxAmount = data.yBalance - (data.xBalance * minPrice) / 1e18;
                    updates[i].amount = maxAmount < pending ? maxAmount : pending;
                }
            }
        }

        assembly { mstore(updates, updateCount) }
        return updates;
    }

    function processOrder(
        IMFPListing listing,
        address proxy,
        PreparedUpdate memory update,
        address token,
        bool isBuy
    ) internal returns (IMFPListing.UpdateType memory) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 rawAmount = denormalize(update.amount, decimals);
        uint256 preBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);
        listing.transact(proxy, token, rawAmount, update.recipient);
        uint256 postBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);
        uint256 actualReceived = postBalance - preBalance;
        uint256 adjustedAmount = actualReceived < rawAmount ? normalize(actualReceived, decimals) : update.amount;

        return IMFPListing.UpdateType(
            isBuy ? 1 : 2, // 1 for buy, 2 for sell
            update.orderId,
            adjustedAmount,
            address(0),
            update.recipient,
            0,
            0
        );
    }

    function executeBuyOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length + 1);
        uint256 updateCount = 0;
        SettlementData memory data;

        // Populate SettlementData
        (data.xBalance, data.yBalance, , ) = listing.volumeBalances();
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                data.totalAmount += preparedUpdates[i].amount;
            }
        }

        // Execute with impact price
        if (data.totalAmount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, true);
            address token = listing.tokenA();

            for (uint256 i = 0; i < preparedUpdates.length; i++) {
                if (preparedUpdates[i].amount > 0) {
                    updates[updateCount] = processOrder(listing, proxy, preparedUpdates[i], token, true);
                    updateCount++;
                }
            }

            updates[updateCount] = IMFPListing.UpdateType(
                0,
                2,
                data.impactPrice,
                address(0),
                address(0),
                0,
                0
            );
            updateCount++;
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }

    function executeSellOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length + 1);
        uint256 updateCount = 0;
        SettlementData memory data;

        // Populate SettlementData
        (data.xBalance, data.yBalance, , ) = listing.volumeBalances();
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                data.totalAmount += preparedUpdates[i].amount;
            }
        }

        // Execute with impact price
        if (data.totalAmount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, false);
            address token = listing.tokenB();

            for (uint256 i = 0; i < preparedUpdates.length; i++) {
                if (preparedUpdates[i].amount > 0) {
                    updates[updateCount] = processOrder(listing, proxy, preparedUpdates[i], token, false);
                    updateCount++;
                }
            }

            updates[updateCount] = IMFPListing.UpdateType(
                0,
                2,
                data.impactPrice,
                address(0),
                address(0),
                0,
                0
            );
            updateCount++;
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