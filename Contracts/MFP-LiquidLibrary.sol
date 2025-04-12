// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.14 (Updated)
// Changes:
// - Added getListingIdFromLiquidity to fetch listingId from IMFPLiquidity (new in v0.0.14).
// - Updated prepBuyLiquid, prepSellLiquid to use listing.getListingId() instead of 0 for prices, volumeBalances (new in v0.0.14).
// - Updated executeBuyLiquid, executeSellLiquid to fetch listingId for volumeBalances (new in v0.0.14).
// - Modified xClaimFees, yClaimFees to accept listingAddress, fetch listingId from IMFPLiquidity, validate listingAddress (new in v0.0.14).
// - Updated IMFPListing interface: added getListingId (new in v0.0.14).
// - Updated IMFPLiquidity interface: claimFees accepts listingAddress; added getListingId (new in v0.0.14).
// - Side effects: Ensures correct listingId usage; aligns with MFPLiquidityTemplate’s claimFees; prevents mismatches.

import "./imports/SafeERC20.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
    function listingValidationByIndex(uint256 listingId) external view returns (address listingAddress, uint256 index);
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
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
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
    function pendingBuyOrders(uint256 listingId) external view returns (uint256[] memory);
    function pendingSellOrders(uint256 listingId) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function getListingId() external view returns (uint256);
}

interface IMFPLiquidity {
    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dVolume;
        uint256 timestamp;
    }
    function deposit(address caller, address token, uint256 amount) external payable;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (MFPLiquidLibrary.PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (MFPLiquidLibrary.PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, MFPLiquidLibrary.PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, MFPLiquidLibrary.PreparedWithdrawal memory withdrawal) external;
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
    function getListingId() external view returns (uint256);
}

library MFPLiquidLibrary {
    using SafeERC20 for IERC20;

    struct PreparedUpdate {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
        address recipient;
    }

    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    struct SettlementData {
        uint256 totalAmount;
        uint256 xBalance;
        uint256 yBalance;
        uint256 impactPrice;
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

    function getListingIdFromLiquidity(address liquidityAddress, address listingAgent) internal view returns (uint256) {
        require(IMFP(listingAgent).isValidListing(liquidityAddress), "Invalid listing");
        return IMFPLiquidity(liquidityAddress).getListingId();
    }

    function prepBuyLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256 listingId = listing.getListingId();
        uint256[] memory pendingOrders = listing.pendingSellOrders(listingId);
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        SettlementData memory data;
        uint256 currentPrice = listing.prices(listingId);

        (data.xBalance, data.yBalance, , ) = listing.volumeBalances(listingId);
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            address makerAddress;
            address recipientAddress;
            uint256 maxPrice;
            uint256 minPrice;
            uint256 pending;
            uint8 status;
            (makerAddress, recipientAddress, maxPrice, minPrice, pending, , status) = listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                uint256 available = data.xBalance > pending ? pending : data.xBalance;
                if (available > 0) {
                    data.totalAmount += available;
                    updates[updateCount] = PreparedUpdate(pendingOrders[i], true, available, recipientAddress);
                    updateCount++;
                }
            }
        }

        if (updateCount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, true);
            for (uint256 i = 0; i < updateCount; i++) {
                address makerAddress;
                address recipient;
                uint256 maxPrice;
                uint256 minPrice;
                uint256 pending;
                uint8 status;
                (makerAddress, recipient, maxPrice, minPrice, pending, , status) = listing.sellOrders(updates[i].orderId);
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

    function prepSellLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256 listingId = listing.getListingId();
        uint256[] memory pendingOrders = listing.pendingBuyOrders(listingId);
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        SettlementData memory data;
        uint256 currentPrice = listing.prices(listingId);

        (data.xBalance, data.yBalance, , ) = listing.volumeBalances(listingId);
        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            address makerAddress;
            address recipientAddress;
            uint256 maxPrice;
            uint256 minPrice;
            uint256 pending;
            uint8 status;
            (makerAddress, recipientAddress, maxPrice, minPrice, pending, , status) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                uint256 available = data.yBalance > pending ? pending : data.yBalance;
                if (available > 0) {
                    data.totalAmount += available;
                    updates[updateCount] = PreparedUpdate(pendingOrders[i], false, available, recipientAddress);
                    updateCount++;
                }
            }
        }

        if (updateCount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, false);
            for (uint256 i = 0; i < updateCount; i++) {
                address makerAddress;
                address recipient;
                uint256 maxPrice;
                uint256 minPrice;
                uint256 pending;
                uint8 status;
                (makerAddress, recipient, maxPrice, minPrice, pending, , status) = listing.buyOrders(updates[i].orderId);
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

    function processOrder(
        IMFPListing listing,
        IMFPLiquidity liquidity,
        address proxy,
        PreparedUpdate memory update,
        address token,
        bool isBuy
    ) internal returns (IMFPListing.UpdateType memory) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 rawAmount = denormalize(update.amount, decimals);
        uint256 preBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);
        liquidity.updateLiquidity(proxy, isBuy, update.amount);
        listing.transact(proxy, token, rawAmount, update.recipient);
        uint256 postBalance = token == address(0) ? update.recipient.balance : IERC20(token).balanceOf(update.recipient);
        uint256 actualReceived = postBalance - preBalance;
        uint256 adjustedAmount = actualReceived < rawAmount ? normalize(actualReceived, decimals) : update.amount;

        return IMFPListing.UpdateType(
            isBuy ? 2 : 1, // 2 for buy (sell order), 1 for sell (buy order)
            update.orderId,
            adjustedAmount,
            update.recipient,
            address(0),
            0,
            0
        );
    }

    function executeBuyLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256 listingId = listing.getListingId();
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length + 2);
        uint256 updateCount = 0;
        SettlementData memory data;

        (data.xBalance, data.yBalance, , ) = listing.volumeBalances(listingId);
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                data.totalAmount += preparedUpdates[i].amount;
            }
        }

        if (data.totalAmount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, true);
            address token = listing.tokenA();

            for (uint256 i = 0; i < preparedUpdates.length; i++) {
                if (preparedUpdates[i].amount > 0) {
                    updates[updateCount] = processOrder(listing, liquidity, proxy, preparedUpdates[i], token, true);
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

            uint256 newXBal;
            uint256 newYBal;
            uint256 xVol;
            uint256 yVol;
            (newXBal, newYBal, xVol, yVol) = listing.volumeBalances(listingId);
            updates[updateCount] = IMFPListing.UpdateType(
                3,
                0,
                data.impactPrice,
                address(0),
                address(0),
                newXBal << 128 | newYBal,
                xVol << 128 | yVol
            );
            updateCount++;
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }

    function executeSellLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256 listingId = listing.getListingId();
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length + 2);
        uint256 updateCount = 0;
        SettlementData memory data;

        (data.xBalance, data.yBalance, , ) = listing.volumeBalances(listingId);
        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                data.totalAmount += preparedUpdates[i].amount;
            }
        }

        if (data.totalAmount > 0) {
            data.impactPrice = calculateImpactPrice(data.xBalance, data.yBalance, data.totalAmount, false);
            address token = listing.tokenB();

            for (uint256 i = 0; i < preparedUpdates.length; i++) {
                if (preparedUpdates[i].amount > 0) {
                    updates[updateCount] = processOrder(listing, liquidity, proxy, preparedUpdates[i], token, false);
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

            uint256 newXBal;
            uint256 newYBal;
            uint256 xVol;
            uint256 yVol;
            (newXBal, newYBal, xVol, yVol) = listing.volumeBalances(listingId);
            updates[updateCount] = IMFPListing.UpdateType(
                3,
                0,
                data.impactPrice,
                address(0),
                address(0),
                newXBal << 128 | newYBal,
                xVol << 128 | yVol
            );
            updateCount++;
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }

    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listing.getListingId()));
        if (listing.tokenA() != address(0)) {
            IERC20(listing.tokenA()).safeTransferFrom(msg.sender, address(liquidity), amount);
        }
        liquidity.deposit(proxy, listing.tokenA(), amount);
    }

    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listing.getListingId()));
        if (listing.tokenB() != address(0)) {
            IERC20(listing.tokenB()).safeTransferFrom(msg.sender, address(liquidity), amount);
        }
        liquidity.deposit(proxy, listing.tokenB(), amount);
    }

    function xClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256 listingId = listing.getListingId();
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        uint256 xVolume;
        (, , xVolume, ) = listing.volumeBalances(listingId);
        liquidity.claimFees(proxy, listingAddress, liquidityIndex, true, xVolume);
    }

    function yClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256 listingId = listing.getListingId();
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        uint256 yVolume;
        (, , , yVolume) = listing.volumeBalances(listingId);
        liquidity.claimFees(proxy, listingAddress, liquidityIndex, false, yVolume);
    }

    function xWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listing.getListingId()));
        
        IMFPLiquidity.Slot memory slot = liquidity.getXSlotView(index);
        require(slot.depositor == msg.sender, "Not depositor");

        PreparedWithdrawal memory preparedWithdrawal = liquidity.xPrepOut(proxy, amount, index);
        liquidity.xExecuteOut(proxy, index, preparedWithdrawal);
        
        return preparedWithdrawal;
    }

    function yWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listing.getListingId()));
        
        IMFPLiquidity.Slot memory slot = liquidity.getYSlotView(index);
        require(slot.depositor == msg.sender, "Not depositor");

        PreparedWithdrawal memory preparedWithdrawal = liquidity.yPrepOut(proxy, amount, index);
        liquidity.yExecuteOut(proxy, index, preparedWithdrawal);
        
        return preparedWithdrawal;
    }
}