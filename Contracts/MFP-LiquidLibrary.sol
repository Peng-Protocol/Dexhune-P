// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1

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
    function deposit(address caller, address token, uint256 amount) external payable;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function claimFees(address caller, uint256 liquidityIndex, bool isX, uint256 volume) external;
}

library MFPLiquidLibrary {
    using SafeERC20 for IERC20;

    function settleBuyLiquid(
        address listingAddress,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        uint256[] memory pendingOrders = listing.pendingSellOrders(0);
        uint256 currentPrice = listing.prices(0);

        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(pendingOrders[i]);
            if (status == 1 && pending > 0) {
                updates[updateCount] = processLiquidOrder(
                    listingAddress, pendingOrders[i], false, pending,
                    listing.tokenA(), listing.tokenA() == address(0) ? 18 : IERC20(listing.tokenA()).decimals(), liquidity, proxy
                );
                updateCount++;
            }
        }
        if (updateCount > 0) {
            finalizeLiquidUpdates(listingAddress, updates, updateCount, currentPrice, proxy);
            IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
            (uint256 xBal, uint256 yBal, uint256 xVol, uint256 yVol) = listing.volumeBalances(0);
            historicalUpdate[0] = IMFPListing.UpdateType(
                3, 0, currentPrice, address(0), address(0),
                xBal << 128 | yBal, xVol << 128 | yVol
            );
            listing.update(proxy, historicalUpdate);
        }
    }

    function settleSellLiquid(
        address listingAddress,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        uint256[] memory pendingOrders = listing.pendingBuyOrders(0);
        uint256 currentPrice = listing.prices(0);

        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
            (, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(pendingOrders[i]);
            if (status == 1 && pending > 0) {
                updates[updateCount] = processLiquidOrder(
                    listingAddress, pendingOrders[i], true, pending,
                    listing.tokenB(), listing.tokenB() == address(0) ? 18 : IERC20(listing.tokenB()).decimals(), liquidity, proxy
                );
                updateCount++;
            }
        }
        if (updateCount > 0) {
            finalizeLiquidUpdates(listingAddress, updates, updateCount, currentPrice, proxy);
            IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
            (uint256 xBal, uint256 yBal, uint256 xVol, uint256 yVol) = listing.volumeBalances(0);
            historicalUpdate[0] = IMFPListing.UpdateType(
                3, 0, currentPrice, address(0), address(0),
                xBal << 128 | yBal, xVol << 128 | yVol
            );
            listing.update(proxy, historicalUpdate);
        }
    }

    function xDeposit(
        address listingAddress,
        uint256 amount,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        if (listing.tokenA() == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(listing.tokenA()).safeTransferFrom(msg.sender, address(liquidity), amount);
        }
        liquidity.deposit{value: msg.value}(proxy, listing.tokenA(), amount);
    }

    function yDeposit(
        address listingAddress,
        uint256 amount,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        if (listing.tokenB() == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(listing.tokenB()).safeTransferFrom(msg.sender, address(liquidity), amount);
        }
        liquidity.deposit{value: msg.value}(proxy, listing.tokenB(), amount);
    }

    function xClaimFees(
        uint256 listingId,
        uint256 liquidityIndex,
        address listingAgent,
        address proxy
    ) external {
        (address listingAddress, ) = IMFP(listingAgent).listingValidationByIndex(listingId);
        require(listingAddress != address(0), "Invalid listing ID");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        (, , uint256 xVolume, ) = listing.volumeBalances(0);
        liquidity.claimFees(proxy, liquidityIndex, true, xVolume);
    }

    function yClaimFees(
        uint256 listingId,
        uint256 liquidityIndex,
        address listingAgent,
        address proxy
    ) external {
        (address listingAddress, ) = IMFP(listingAgent).listingValidationByIndex(listingId);
        require(listingAddress != address(0), "Invalid listing ID");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        (, , , uint256 yVolume) = listing.volumeBalances(0);
        liquidity.claimFees(proxy, liquidityIndex, false, yVolume);
    }

    function processLiquidOrder(
        address listing,
        uint256 orderId,
        bool isBuy,
        uint256 pending,
        address token,
        uint8 decimals,
        IMFPLiquidity liquidity,
        address proxy
    ) internal returns (IMFPListing.UpdateType memory) {
        IMFPListing listingContract = IMFPListing(listing);
        uint256 rawAmount = denormalize(pending, decimals);
        address recipient = isBuy ? listingContract.buyOrders(orderId).recipient : listingContract.sellOrders(orderId).recipient;
        uint256 preBalance = token == address(0) ? recipient.balance : IERC20(token).balanceOf(recipient);
        IMFPListing.UpdateType memory update = IMFPListing.UpdateType(isBuy ? 1 : 2, orderId, pending, recipient, address(0), 0, 0);
        liquidity.updateLiquidity(proxy, isBuy, pending);
        listingContract.transact(proxy, token, rawAmount, recipient);
        uint256 postBalance = token == address(0) ? recipient.balance : IERC20(token).balanceOf(recipient);
        uint256 actualReceived = postBalance - preBalance;
        if (actualReceived < rawAmount) {
            update.value = normalize(actualReceived, decimals);
        }
        return update;
    }

    function finalizeLiquidUpdates(
        address listing,
        IMFPListing.UpdateType[] memory updates,
        uint256 updateCount,
        uint256 currentPrice,
        address proxy
    ) internal {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
        assembly { mstore(updates, add(updateCount, 1)) }
        IMFPListing(listing).update(proxy, updates);
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