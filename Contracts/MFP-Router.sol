// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.6

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

struct ListingValidation {
    address listingAddress;
    uint256 index;
}

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
    function getListingId(address listingAddress) external view returns (uint256);
    function listingValidationByIndex(uint256 listingId) external view returns (ListingValidation memory);
    function writeValidationSlot(
        uint256 listingId,
        address listingAddress,
        address tokenA,
        address tokenB,
        uint256 xBalance,
        uint256 yBalance,
        uint256 xLiquid,
        uint256 yLiquid
    ) external;
}

interface IMFPListing {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order
        uint256 index;    // orderId or slot index
        uint256 value;    // principal or amount (normalized)
        address addr;     // makerAddress
        address recipient;// recipientAddress
        uint256 maxPrice; // for buy orders
        uint256 minPrice; // for sell orders
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
    function makerPendingOrders(address maker) external view returns (uint256[] memory);
    function update(uint256 listingId, UpdateType[] memory updates) external;
    function transact(uint256 listingId, address token, uint256 amount, address recipient) external;
}

interface IMFPLiquidity {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;    // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value;    // amount or allocation (normalized)
        address addr;     // depositor
        address recipient;// not used
    }
    function liquidityDetails(uint256 listingId) external view returns (
        uint256 xLiquid,
        uint256 yLiquid,
        uint256 xFees,
        uint256 yFees
    );
    function xLiquiditySlots(uint256 listingId, uint256 index) external view returns (
        address depositor,
        address recipient,
        uint256 xAllocation,
        uint256 dVolume,
        uint256 timestamp
    );
    function yLiquiditySlots(uint256 listingId, uint256 index) external view returns (
        address depositor,
        address recipient,
        uint256 yAllocation,
        uint256 dVolume,
        uint256 timestamp
    );
    function update(uint256 listingId, UpdateType[] memory updates) external;
    function transact(uint256 listingId, address token, uint256 amount, address recipient) external;
    function deposit(uint256 listingId, address token, uint256 amount) external payable;
    function addFees(uint256 listingId, bool isX, uint256 fee) external;
    function updateLiquidity(uint256 listingId, bool isX, uint256 amount) external;
    function claimFees(uint256 listingId, uint256 liquidityIndex, bool isX, uint256 volume) external; // Added
}

contract MFPRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public listingAgent;

    struct SellOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;   // raw amount
        uint256 maxPrice; // TokenA/TokenB, 18 decimals
        uint256 minPrice; // TokenA/TokenB, 18 decimals
    }

    event OrderCreated(uint256 orderId, bool isBuy, address maker);
    event OrderCancelled(uint256 orderId);

    constructor() {
        _transferOwnership(msg.sender);
    }

    function setAgent(address _agent) external onlyOwner {
        listingAgent = _agent;
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

    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
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
        normalized = normalize(amount, decimals);
        fee = (normalized * 5) / 10000;
        principal = normalized - fee;
    }

    function _createOrderUpdate(
        uint8 updateType, // 1 for buy, 2 for sell
        uint256 orderId,
        uint256 principal,
        address maker,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 volumeIndex, // 0 for xVolume, 1 for yVolume
        uint256 normalizedAmount
    ) internal pure returns (IMFPListing.UpdateType[] memory) {
        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](2);
        updates[0] = IMFPListing.UpdateType(updateType, orderId, principal, maker, recipient, maxPrice, minPrice);
        updates[1] = IMFPListing.UpdateType(0, volumeIndex, normalizedAmount, address(0), address(0), 0, 0);
        return updates;
    }

    function _prepareOrder(
        address listingAddress,
        uint256 listingId,
        address token,
        uint256 amount,
        uint8 updateType,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice,
        uint256 volumeIndex
    ) internal returns (uint256 orderId, IMFPListing.UpdateType[] memory updates, uint256 fee) {
        uint256 receivedAmount = _transferToken(token, listingAddress, amount);
        (uint256 normalizedAmount, uint256 fee_, uint256 principal) = _normalizeAndFee(token, receivedAmount);
        orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, amount)));
        updates = _createOrderUpdate(updateType, orderId, principal, msg.sender, recipient, maxPrice, minPrice, volumeIndex, normalizedAmount);
        return (orderId, updates, fee_);
    }

        function createBuyOrder(address listingAddress, BuyOrderDetails memory details) external payable nonReentrant {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);

        address tokenA = listing.tokenA();
        (uint256 orderId, IMFPListing.UpdateType[] memory updates, uint256 fee) = _prepareOrder(listingAddress, listingId, tokenA, details.amount, 1, details.recipient, details.maxPrice, details.minPrice, 0);
        listing.update(listingId, updates);

        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        liquidity.addFees(listingId, true, fee);

        emit OrderCreated(orderId, true, msg.sender);
    }

        function createSellOrder(address listingAddress, SellOrderDetails memory details) external payable nonReentrant {
        require(listingAgent != address(0), "Agent not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);

        address tokenB = listing.tokenB();
        (uint256 orderId, IMFPListing.UpdateType[] memory updates, uint256 fee) = _prepareOrder(listingAddress, listingId, tokenB, details.amount, 2, details.recipient, details.maxPrice, details.minPrice, 1);
        listing.update(listingId, updates);

        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        liquidity.addFees(listingId, false, fee);

        emit OrderCreated(orderId, false, msg.sender);
    }

    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);

        address refundTo;
        uint256 refundAmount;
        address token;
        if (isBuy) {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenA();
        } else {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(orderId);
            require(status == 1 || status == 2, "Order not active");
            refundTo = recipient != address(0) ? recipient : maker;
            refundAmount = pending;
            token = listing.tokenB();
        }

        if (refundAmount > 0) {
            listing.transact(listingId, token, refundAmount, refundTo);
        }

        IMFPListing.UpdateType[] memory updates = _createOrderUpdate(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0, 0, 0);
        listing.update(listingId, updates);
    }

    function clearOrders(address listingAddress) external nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        uint256[] memory buyOrders = listing.pendingBuyOrders(listingId);
        uint256[] memory sellOrders = listing.pendingSellOrders(listingId);

        uint256 totalOrders = buyOrders.length + sellOrders.length;
        if (totalOrders == 0) return;

        IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](totalOrders);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < buyOrders.length; i++) {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(buyOrders[i]);
            if (status == 1 || status == 2) {
                address refundTo = recipient != address(0) ? recipient : maker;
                if (pending > 0) {
                    listing.transact(listingId, listing.tokenA(), pending, refundTo);
                }
                updates[updateCount] = _createOrderUpdate(1, buyOrders[i], 0, address(0), address(0), 0, 0, 0, 0)[0];
                updateCount++;
            }
        }

        for (uint256 i = 0; i < sellOrders.length; i++) {
            (address maker, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(sellOrders[i]);
            if (status == 1 || status == 2) {
                address refundTo = recipient != address(0) ? recipient : maker;
                if (pending > 0) {
                    listing.transact(listingId, listing.tokenB(), pending, refundTo);
                }
                updates[updateCount] = _createOrderUpdate(2, sellOrders[i], 0, address(0), address(0), 0, 0, 0, 0)[0];
                updateCount++;
            }
        }

        if (updateCount > 0) {
            assembly { mstore(updates, updateCount) }
            listing.update(listingId, updates);
        }
    }

    function settleBuyOrders(address listingAddress) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    uint256[] memory pendingOrders = listing.pendingBuyOrders(listingId);
    (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);

    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
    uint256 updateCount = 0;
    uint256 currentPrice = listing.prices(listingId);
    address tokenB = listing.tokenB();
    uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();

    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, uint256 maxPrice, , uint256 pending, , , , uint8 status) = listing.buyOrders(pendingOrders[i]);
        if (status == 1 && pending > 0) {
            uint256 available = yBalance > pending ? pending : yBalance;
            if (currentPrice <= maxPrice && available > 0) {
                uint256 rawAmount = denormalize(available, decimals);
                uint256 preBalance = tokenB == address(0) ? recipient.balance : IERC20(tokenB).balanceOf(recipient);
                updates[updateCount] = IMFPListing.UpdateType(1, pendingOrders[i], available, recipient, address(0), 0, 0);
                yBalance -= available;
                updateCount++;
                listing.transact(listingId, tokenB, rawAmount, recipient);
                uint256 postBalance = tokenB == address(0) ? recipient.balance : IERC20(tokenB).balanceOf(recipient);
                uint256 actualReceived = postBalance - preBalance;
                if (actualReceived < rawAmount) {
                    updates[updateCount - 1].value = normalize(actualReceived, decimals); // Adjust filled amount
                }
            }
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);
    }
}

    function settleSellOrders(address listingAddress) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    uint256[] memory pendingOrders = listing.pendingSellOrders(listingId);
    (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(listingId);

    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
    uint256 updateCount = 0;
    uint256 currentPrice = listing.prices(listingId);
    address tokenA = listing.tokenA();
    uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();

    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, uint256 maxPrice, uint256 minPrice, uint256 pending, , , , uint8 status) = listing.sellOrders(pendingOrders[i]);
        if (status == 1 && pending > 0) {
            uint256 available = xBalance > pending ? pending : xBalance;
            if (currentPrice >= minPrice && currentPrice <= maxPrice && available > 0) {
                uint256 rawAmount = denormalize(available, decimals);
                uint256 preBalance = tokenA == address(0) ? recipient.balance : IERC20(tokenA).balanceOf(recipient);
                updates[updateCount] = IMFPListing.UpdateType(2, pendingOrders[i], available, recipient, address(0), 0, 0);
                xBalance -= available;
                updateCount++;
                listing.transact(listingId, tokenA, rawAmount, recipient);
                uint256 postBalance = tokenA == address(0) ? recipient.balance : IERC20(tokenA).balanceOf(recipient);
                uint256 actualReceived = postBalance - preBalance;
                if (actualReceived < rawAmount) {
                    updates[updateCount - 1].value = normalize(actualReceived, decimals); // Adjust filled amount
                }
            }
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);
    }
}

    function settleBuyLiquid(address listingAddress) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));

    uint256[] memory pendingOrders = listing.pendingSellOrders(listingId);
    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
    uint256 updateCount = 0;
    uint256 currentPrice = listing.prices(listingId);
    address tokenA = listing.tokenA();
    uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();

    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(pendingOrders[i]);
        if (status == 1 && pending > 0) {
            uint256 rawAmount = denormalize(pending, decimals);
            uint256 preBalance = tokenA == address(0) ? recipient.balance : IERC20(tokenA).balanceOf(recipient);
            updates[updateCount] = IMFPListing.UpdateType(2, pendingOrders[i], pending, recipient, address(0), 0, 0);
            liquidity.updateLiquidity(listingId, true, pending);
            updateCount++;
            listing.transact(listingId, tokenA, rawAmount, recipient);
            uint256 postBalance = tokenA == address(0) ? recipient.balance : IERC20(tokenA).balanceOf(recipient);
            uint256 actualReceived = postBalance - preBalance;
            if (actualReceived < rawAmount) {
                updates[updateCount - 1].value = normalize(actualReceived, decimals); // Adjust filled amount
            }
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);
    }
}

    function settleSellLiquid(address listingAddress) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));

    uint256[] memory pendingOrders = listing.pendingBuyOrders(listingId);
    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
    uint256 updateCount = 0;
    uint256 currentPrice = listing.prices(listingId);
    address tokenB = listing.tokenB();
    uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();

    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(pendingOrders[i]);
        if (status == 1 && pending > 0) {
            uint256 rawAmount = denormalize(pending, decimals);
            uint256 preBalance = tokenB == address(0) ? recipient.balance : IERC20(tokenB).balanceOf(recipient);
            updates[updateCount] = IMFPListing.UpdateType(1, pendingOrders[i], pending, recipient, address(0), 0, 0);
            liquidity.updateLiquidity(listingId, false, pending);
            updateCount++;
            listing.transact(listingId, tokenB, rawAmount, recipient);
            uint256 postBalance = tokenB == address(0) ? recipient.balance : IERC20(tokenB).balanceOf(recipient);
            uint256 actualReceived = postBalance - preBalance;
            if (actualReceived < rawAmount) {
                updates[updateCount - 1].value = normalize(actualReceived, decimals); // Adjust filled amount
            }
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0);
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);
    }
}

    function xDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        liquidity.deposit{value: msg.value}(listingId, listing.tokenA(), amount);
    }

    function yDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
        uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        liquidity.deposit{value: msg.value}(listingId, listing.tokenB(), amount);
    }

    function xClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        (, , uint256 xVolume, ) = listing.volumeBalances(listingId);
        liquidity.claimFees(listingId, liquidityIndex, true, xVolume);
    }

    function yClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
        (, , , uint256 yVolume) = listing.volumeBalances(listingId);
        liquidity.claimFees(listingId, liquidityIndex, false, yVolume);
    }
}