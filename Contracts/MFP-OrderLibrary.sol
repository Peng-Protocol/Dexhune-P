// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.10 (Updated)
// Changes:
// - From v0.0.9: Updated executeBuyOrder and executeSellOrder to handle tax-on-transfer tokens by using post-tax receivedPrincipal and receivedFee (new in v0.0.10).
// - From v0.0.9: Removed reverts for receivedPrincipal < prep.principal and receivedFee < prep.fee; store receivedPrincipal in updates and use receivedFee in addFees (new in v0.0.10).
// - From v0.0.9: Side effect: Prevents reverts for tax-on-transfer tokens; ensures actual received amounts are stored and used.
// - From v0.0.9: Updated clearSingleOrder to restrict cancellation to order maker (msg.sender).
// - From v0.0.9: Updated clearOrders to clear only caller's orders using makerPendingOrdersView.
// - From v0.0.9: Changed clearOrders signature to include caller parameter and use proxy instead of bracket.
// - From v0.0.9: Side effect: Enhances security by preventing unauthorized order cancellations.
// - From v0.0.8: Added denormalize function to handle non-18 decimal tokens.
// - From v0.0.8: Updated clearSingleOrder to denormalize refundAmount before transact.
// - From v0.0.8: Updated clearOrders to denormalize pending amounts before transact.
// - From v0.0.8: Side effects: Corrects refund amounts for tokens with non-18 decimals (e.g., USDC); aligns with MFP-SettlementLibrary’s processOrder.
// - No changes to prepBuyOrder, prepSellOrder.
// - Retains alignment with MFPListingTemplate’s stored listingId (from v0.0.7).

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
    function buyOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 maxPrice, uint256 minPrice,
        uint256 pending, uint256 filled, uint8 status
    );
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddresses() external view returns (address);
    function volumeBalances() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices() external view returns (uint256);
    function pendingBuyOrders() external view returns (uint256[] memory);
    function pendingSellOrders() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
}

interface IMFPLiquidity {
    function addFees(address caller, bool isX, uint256 fee) external;
}

library MFPOrderLibrary {
    using SafeERC20 for IERC20;

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IMFPListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    struct PrepData {
        uint256 normalized;
        uint256 fee;
        uint256 principal;
        uint256 orderId;
        IMFPListing.UpdateType[] updates;
        address token;
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    // Helper functions
    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient ETH amount");
            (bool success, ) = target.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, target, amount);
        }
        uint256 postBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function _normalizeAndFee(address token, uint256 amount) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        normalized = amount;
        if (decimals != 18) {
            if (decimals < 18) normalized = amount * (10 ** (uint256(18) - uint256(decimals)));
            else normalized = amount / (10 ** (uint256(decimals) - uint256(18)));
        }
        fee = (normalized * 5) / 10000; // 0.05% fee
        principal = normalized - fee;
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10**(18 - decimals);
        else return amount * 10**(decimals - 18);
    }

    function _createOrderUpdate(
        uint8 updateType,
        uint256 orderId,
        uint256 principal,
        address maker,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice
    ) internal pure returns (IMFPListing.UpdateType[] memory) {
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](1);
        updates[0] = IMFPListing.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        return updates;
    }

    // Prep functions
    function prepBuyOrder(
        address listingAddress,
        IMFPOrderLibrary.BuyOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.tokenA();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = orderId;
        prepData.updates = _createOrderUpdate(
            1, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    function prepSellOrder(
        address listingAddress,
        IMFPOrderLibrary.SellOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory) {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        PrepData memory prepData;
        prepData.token = listing.tokenB();
        (prepData.normalized, prepData.fee, prepData.principal) = _normalizeAndFee(prepData.token, details.amount);
        prepData.orderId = orderId;
        prepData.updates = _createOrderUpdate(
            2, prepData.orderId, prepData.principal, msg.sender, details.recipient, details.maxPrice, details.minPrice
        );

        return OrderPrep(prepData.orderId, prepData.principal, prepData.fee, prepData.updates, prepData.token, details.recipient);
    }

    // Execute functions
    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IMFPListing listing = IMFPListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses();
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);

        uint256 receivedPrincipal = _transferToken(prep.token, listingAddress, prep.principal);
        require(receivedPrincipal > 0, "No principal received");

        uint256 receivedFee = _transferToken(prep.token, liquidityAddress, prep.fee);

        // Update principal in updates to reflect post-tax amount
        prep.updates[0].value = receivedPrincipal;

        listing.update(proxy, prep.updates);
        liquidity.addFees(proxy, true, receivedFee);

        IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        (xBalance, yBalance, xVolume, yVolume) = listing.volumeBalances();
        historicalUpdate[0] = IMFPListing.UpdateType(
            3, 0, listing.prices(),
            address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, true, msg.sender);
    }

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external {
        IMFPListing listing = IMFPListing(listingAddress);
        address liquidityAddress = listing.liquidityAddresses();
        IMFPLiquidity liquidity = IMFPLiquidity(liquidityAddress);

        uint256 receivedPrincipal = _transferToken(prep.token, listingAddress, prep.principal);
        require(receivedPrincipal > 0, "No principal received");

        uint256 receivedFee = _transferToken(prep.token, liquidityAddress, prep.fee);

        // Update principal in updates to reflect post-tax amount
        prep.updates[0].value = receivedPrincipal;

        listing.update(proxy, prep.updates);
        liquidity.addFees(proxy, false, receivedFee);

        IMFPListing.UpdateType[] memory historicalUpdate = new IMFPListing.UpdateType[](1);
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
        (xBalance, yBalance, xVolume, yVolume) = listing.volumeBalances();
        historicalUpdate[0] = IMFPListing.UpdateType(
            3, 0, listing.prices(),
            address(0), address(0),
            xBalance << 128 | yBalance, xVolume << 128 | yVolume
        );
        listing.update(proxy, historicalUpdate);

        emit OrderCreated(prep.orderId, false, msg.sender);
    }

    // Clear functions
    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);

        address refundTo;
        uint256 refundAmount;
        address token;
        if (isBuy) {
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            (maker, recipient, , , pending, , status) = listing.buyOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            require(maker == msg.sender, "Not order maker");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenA();
        } else {
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            (maker, recipient, , , pending, , status) = listing.sellOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            require(maker == msg.sender, "Not order maker");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenB();
        }

        if (refundAmount > 0) {
            uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
            uint256 rawAmount = denormalize(refundAmount, decimals);
            listing.transact(proxy, token, rawAmount, refundTo);
        }

        IMFPListing.UpdateType[] memory updates = _createOrderUpdate(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0);
        listing.update(proxy, updates);
        emit OrderCancelled(orderId);
    }

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address caller
    ) external {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory userOrders = listing.makerPendingOrdersView(caller);

        if (userOrders.length == 0) return;

        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](userOrders.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < userOrders.length; i++) {
            uint256 orderId = userOrders[i];
            bool isBuy;
            address maker;
            address recipient;
            uint256 pending;
            uint8 status;
            address token;

            // Try buy order
            (maker, recipient, , , pending, , status) = listing.buyOrders(orderId);
            if (status == 1 || status == 2 && maker == caller) {
                isBuy = true;
                token = listing.tokenA();
            } else {
                // Try sell order
                (maker, recipient, , , pending, , status) = listing.sellOrders(orderId);
                if (status == 1 || status == 2 && maker == caller) {
                    isBuy = false;
                    token = listing.tokenB();
                } else {
                    continue;
                }
            }

            address refundTo = recipient != address(0) ? recipient : maker;
            if (pending > 0) {
                uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
                uint256 rawAmount = denormalize(pending, decimals);
                listing.transact(proxy, token, rawAmount, refundTo);
            }

            updates[updateCount] = _createOrderUpdate(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0)[0];
            updateCount++;
            emit OrderCancelled(orderId);
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(proxy, updates);
        }
    }
}

interface IMFPOrderLibrary {
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    struct SellOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IMFPListing.UpdateType[] updates;
        address token;
        address recipient;
    }

    function prepBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory);

    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory);

    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;

    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;

    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external;

    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address caller
    ) external;
}