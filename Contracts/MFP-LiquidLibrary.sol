// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.10

import "./imports/SafeERC20.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
    function listingValidationByIndex(uint256 listingId) external view returns (address listingAddress, uint256 index);
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
    function claimFees(address caller, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (MFPLiquidLibrary.PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (MFPLiquidLibrary.PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, MFPLiquidLibrary.PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, MFPLiquidLibrary.PreparedWithdrawal memory withdrawal) external;
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
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

    function prepBuyLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingSellOrders(0);
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        uint256 currentPrice = listing.prices(0);

        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                ,
                ,
                ,
                uint8 status
            ) = listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                updates[updateCount] = PreparedUpdate(pendingOrders[i], true, pending, recipientAddress);
                updateCount++;
            }
        }
        assembly { mstore(updates, updateCount) }
        return updates;
    }

    function prepSellLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory pendingOrders = listing.pendingBuyOrders(0);
        PreparedUpdate[] memory updates = new PreparedUpdate[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;
        uint256 currentPrice = listing.prices(0);

        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                ,
                ,
                ,
                uint8 status
            ) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0 && currentPrice >= minPrice && currentPrice <= maxPrice) {
                updates[updateCount] = PreparedUpdate(pendingOrders[i], false, pending, recipientAddress);
                updateCount++;
            }
        }
        assembly { mstore(updates, updateCount) }
        return updates;
    }

    function executeBuyLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length);
        uint256 updateCount = 0;
        uint256 currentPrice = listing.prices(0);

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                address token = listing.tokenA();
                uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
                uint256 rawAmount = denormalize(preparedUpdates[i].amount, decimals);
                uint256 preBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                liquidity.updateLiquidity(proxy, true, preparedUpdates[i].amount);
                listing.transact(proxy, token, rawAmount, preparedUpdates[i].recipient);
                uint256 postBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                uint256 actualReceived = postBalance - preBalance;
                uint256 adjustedAmount = actualReceived < rawAmount ? normalize(actualReceived, decimals) : preparedUpdates[i].amount;
                updates[updateCount] = IMFPListing.UpdateType(2, preparedUpdates[i].orderId, adjustedAmount, preparedUpdates[i].recipient, address(0), 0, 0);
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
            assembly { mstore(updates, add(updateCount, 1)) }
            listing.update(proxy, updates);

            IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
            (uint256 xBal, uint256 yBal, uint256 xVol, uint256 yVol) = listing.volumeBalances(0);
            historicalUpdate[0] = IMFPListing.UpdateType(3, 0, currentPrice, address(0), address(0), xBal << 128 | yBal, xVol << 128 | yVol);
            listing.update(proxy, historicalUpdate);
        }
    }

    function executeSellLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external {
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](preparedUpdates.length);
        uint256 updateCount = 0;
        uint256 currentPrice = listing.prices(0);

        for (uint256 i = 0; i < preparedUpdates.length; i++) {
            if (preparedUpdates[i].amount > 0) {
                address token = listing.tokenB();
                uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
                uint256 rawAmount = denormalize(preparedUpdates[i].amount, decimals);
                uint256 preBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                liquidity.updateLiquidity(proxy, false, preparedUpdates[i].amount);
                listing.transact(proxy, token, rawAmount, preparedUpdates[i].recipient);
                uint256 postBalance = token == address(0) ? preparedUpdates[i].recipient.balance : IERC20(token).balanceOf(preparedUpdates[i].recipient);
                uint256 actualReceived = postBalance - preBalance;
                uint256 adjustedAmount = actualReceived < rawAmount ? normalize(actualReceived, decimals) : preparedUpdates[i].amount;
                updates[updateCount] = IMFPListing.UpdateType(1, preparedUpdates[i].orderId, adjustedAmount, preparedUpdates[i].recipient, address(0), 0, 0);
                updateCount++;
            }
        }
        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
            assembly { mstore(updates, add(updateCount, 1)) }
            listing.update(proxy, updates);

            IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
            (uint256 xBal, uint256 yBal, uint256 xVol, uint256 yVol) = listing.volumeBalances(0);
            historicalUpdate[0] = IMFPListing.UpdateType(3, 0, currentPrice, address(0), address(0), xBal << 128 | yBal, xVol << 128 | yVol);
            listing.update(proxy, historicalUpdate);
        }
    }

    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        if (listing.tokenA() != address(0)) {
            IERC20(listing.tokenA()).safeTransferFrom(msg.sender, address(liquidity), amount);
        }
        liquidity.deposit(proxy, listing.tokenA(), amount);
    }

    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        if (listing.tokenB() != address(0)) {
            IERC20(listing.tokenB()).safeTransferFrom(msg.sender, address(liquidity), amount);
        }
        liquidity.deposit(proxy, listing.tokenB(), amount);
    }

    function xClaimFees(uint256 listingId, uint256 liquidityIndex, address listingAgent, address proxy) external {
        (address listingAddress, ) = IMFP(listingAgent).listingValidationByIndex(listingId);
        require(listingAddress != address(0), "Invalid listing ID");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        (, , uint256 xVolume, ) = listing.volumeBalances(0);
        liquidity.claimFees(proxy, liquidityIndex, true, xVolume);
    }

    function yClaimFees(uint256 listingId, uint256 liquidityIndex, address listingAgent, address proxy) external {
        (address listingAddress, ) = IMFP(listingAgent).listingValidationByIndex(listingId);
        require(listingAddress != address(0), "Invalid listing ID");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        (, , , uint256 yVolume) = listing.volumeBalances(0);
        liquidity.claimFees(proxy, liquidityIndex, false, yVolume);
    }

    function xWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        
        IMFPLiquidity.Slot memory slot = liquidity.getXSlotView(index);
        require(slot.depositor == msg.sender, "Not depositor");

        PreparedWithdrawal memory preparedWithdrawal = liquidity.xPrepOut(proxy, amount, index);
        liquidity.xExecuteOut(proxy, index, preparedWithdrawal);
        
        return preparedWithdrawal;
    }

    function yWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory) {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        
        IMFPLiquidity.Slot memory slot = liquidity.getYSlotView(index);
        require(slot.depositor == msg.sender, "Not depositor");

        PreparedWithdrawal memory preparedWithdrawal = liquidity.yPrepOut(proxy, amount, index);
        liquidity.yExecuteOut(proxy, index, preparedWithdrawal);
        
        return preparedWithdrawal;
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