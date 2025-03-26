// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.5

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
}

contract MFPRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public listingAgent;
    mapping(uint256 => uint256) public liquidityIndexCount;

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
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);

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

    function createBuyOrder(address listingAddress, BuyOrderDetails memory details) external payable nonReentrant {
    require(listingAgent != address(0), "Agent not set");
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);

    address tokenA = listing.tokenA();
    uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
    uint256 preBalance = tokenA == address(0) ? listingAddress.balance : IERC20(tokenA).balanceOf(listingAddress);

    if (tokenA == address(0)) {
        require(msg.value == details.amount, "Incorrect ETH amount");
        (bool success, ) = listingAddress.call{value: details.amount}("");
        require(success, "ETH transfer failed");
    } else {
        IERC20(tokenA).safeTransferFrom(msg.sender, listingAddress, details.amount);
    }

    uint256 postBalance = tokenA == address(0) ? listingAddress.balance : IERC20(tokenA).balanceOf(listingAddress);
    uint256 receivedAmount = postBalance - preBalance;
    uint256 normalizedAmount = normalize(receivedAmount, decimals);
    uint256 fee = (normalizedAmount * 5) / 10000;
    uint256 principal = normalizedAmount - fee;

    uint256 orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, details.amount)));
    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](2);
    updates[0] = IMFPListing.UpdateType(1, orderId, principal, msg.sender, details.recipient, details.maxPrice, details.minPrice);
    updates[1] = IMFPListing.UpdateType(0, 0, normalizedAmount, address(0), address(0), 0, 0); // Historical xVolume
    listing.update(listingId, updates);

    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    IMFPLiquidity.UpdateType[] memory feeUpdates = new IMFPLiquidity.UpdateType[](1);
    feeUpdates[0] = IMFPLiquidity.UpdateType(1, 0, fee, address(0), address(0));
    liquidity.update(listingId, feeUpdates);

    emit OrderCreated(orderId, true, msg.sender);
}

    function createSellOrder(address listingAddress, SellOrderDetails memory details) external payable nonReentrant {
    require(listingAgent != address(0), "Agent not set");
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);

    address tokenB = listing.tokenB();
    uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
    uint256 preBalance = tokenB == address(0) ? listingAddress.balance : IERC20(tokenB).balanceOf(listingAddress);

    if (tokenB == address(0)) {
        require(msg.value == details.amount, "Incorrect ETH amount");
        (bool success, ) = listingAddress.call{value: details.amount}("");
        require(success, "ETH transfer failed");
    } else {
        IERC20(tokenB).safeTransferFrom(msg.sender, listingAddress, details.amount);
    }

    uint256 postBalance = tokenB == address(0) ? listingAddress.balance : IERC20(tokenB).balanceOf(listingAddress);
    uint256 receivedAmount = postBalance - preBalance;
    uint256 normalizedAmount = normalize(receivedAmount, decimals);
    uint256 fee = (normalizedAmount * 5) / 10000;
    uint256 principal = normalizedAmount - fee;

    uint256 orderId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, details.amount)));
    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](2);
    updates[0] = IMFPListing.UpdateType(2, orderId, principal, msg.sender, details.recipient, details.maxPrice, details.minPrice);
    updates[1] = IMFPListing.UpdateType(0, 1, normalizedAmount, address(0), address(0), 0, 0); // Historical yVolume
    listing.update(listingId, updates);

    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    IMFPLiquidity.UpdateType[] memory feeUpdates = new IMFPLiquidity.UpdateType[](1);
    feeUpdates[0] = IMFPLiquidity.UpdateType(1, 1, fee, address(0), address(0));
    liquidity.update(listingId, feeUpdates);

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

    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](1);
    updates[0] = IMFPListing.UpdateType(isBuy ? 1 : 2, orderId, 0, address(0), address(0), 0, 0);
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
            updates[updateCount] = IMFPListing.UpdateType(1, buyOrders[i], 0, address(0), address(0), 0, 0);
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
            updates[updateCount] = IMFPListing.UpdateType(2, sellOrders[i], 0, address(0), address(0), 0, 0);
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
    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, uint256 maxPrice, , uint256 pending, , , , uint8 status) = listing.buyOrders(pendingOrders[i]);
        if (status == 1 && pending > 0) {
            uint256 available = yBalance > pending ? pending : yBalance;
            if (currentPrice <= maxPrice && available > 0) {
                updates[updateCount] = IMFPListing.UpdateType(1, pendingOrders[i], available, recipient, address(0), 0, 0);
                yBalance -= available;
                updateCount++;
            }
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0); // Historical price
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);

        uint8 decimals = listing.tokenB() == address(0) ? 18 : IERC20(listing.tokenB()).decimals();
        for (uint256 i = 0; i < updateCount - 1; i++) {
            listing.transact(listingId, listing.tokenB(), denormalize(updates[i].value, decimals), updates[i].addr);
        }
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
    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, uint256 maxPrice, uint256 minPrice, uint256 pending, , , , uint8 status) = listing.sellOrders(pendingOrders[i]);
        if (status == 1 && pending > 0) {
            uint256 available = xBalance > pending ? pending : xBalance;
            if (currentPrice >= minPrice && currentPrice <= maxPrice && available > 0) {
                updates[updateCount] = IMFPListing.UpdateType(2, pendingOrders[i], available, recipient, address(0), 0, 0);
                xBalance -= available;
                updateCount++;
            }
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0); // Historical price
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);

        uint8 decimals = listing.tokenA() == address(0) ? 18 : IERC20(listing.tokenA()).decimals();
        for (uint256 i = 0; i < updateCount - 1; i++) {
            listing.transact(listingId, listing.tokenA(), denormalize(updates[i].value, decimals), updates[i].addr);
        }
    }
}

    function settleBuyLiquid(address listingAddress) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (uint256 xLiquid, , , ) = liquidity.liquidityDetails(listingId);

    uint256[] memory pendingOrders = listing.pendingSellOrders(listingId);
    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
    uint256 updateCount = 0;
    uint256 currentPrice = listing.prices(listingId);
    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, , , uint256 pending, , , , uint8 status) = listing.sellOrders(pendingOrders[i]);
        if (status == 1 && pending <= xLiquid) {
            updates[updateCount] = IMFPListing.UpdateType(2, pendingOrders[i], pending, recipient, address(0), 0, 0);
            xLiquid -= pending;
            updateCount++;
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0); // Historical price
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);

        uint8 decimals = listing.tokenA() == address(0) ? 18 : IERC20(listing.tokenA()).decimals();
        for (uint256 i = 0; i < updateCount - 1; i++) {
            listing.transact(listingId, listing.tokenA(), denormalize(updates[i].value, decimals), updates[i].addr);
        }
    }
}

    function settleSellLiquid(address listingAddress) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (, uint256 yLiquid, , ) = liquidity.liquidityDetails(listingId);

    uint256[] memory pendingOrders = listing.pendingBuyOrders(listingId);
    IMFPListing.UpdateType[] memory updates = new IMFPListing.UpdateType[](pendingOrders.length < 100 ? pendingOrders.length : 100);
    uint256 updateCount = 0;
    uint256 currentPrice = listing.prices(listingId);
    for (uint256 i = 0; i < pendingOrders.length && i < 100; i++) {
        (, address recipient, , , uint256 pending, , , , uint8 status) = listing.buyOrders(pendingOrders[i]);
        if (status == 1 && pending <= yLiquid) {
            updates[updateCount] = IMFPListing.UpdateType(1, pendingOrders[i], pending, recipient, address(0), 0, 0);
            yLiquid -= pending;
            updateCount++;
        }
    }
    if (updateCount > 0) {
        assembly { mstore(updates, updateCount) }
        updates[updateCount] = IMFPListing.UpdateType(0, 2, currentPrice, address(0), address(0), 0, 0); // Historical price
        updateCount++;
        assembly { mstore(updates, updateCount) }
        listing.update(listingId, updates);

        uint8 decimals = listing.tokenB() == address(0) ? 18 : IERC20(listing.tokenB()).decimals();
        for (uint256 i = 0; i < updateCount - 1; i++) {
            listing.transact(listingId, listing.tokenB(), denormalize(updates[i].value, decimals), updates[i].addr);
        }
    }
}

    function xDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    address tokenA = listing.tokenA();
    uint8 decimals = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
    uint256 normalizedAmount = normalize(amount, decimals);

    if (tokenA == address(0)) {
        require(msg.value == amount, "Incorrect ETH amount");
        (bool success, ) = address(liquidity).call{value: amount}("");
        require(success, "ETH transfer failed");
    } else {
        IERC20(tokenA).safeTransferFrom(msg.sender, address(liquidity), amount);
    }

    uint256 index = liquidityIndexCount[listingId];
    IMFPLiquidity.UpdateType[] memory updates = new IMFPLiquidity.UpdateType[](1);
    updates[0] = IMFPLiquidity.UpdateType(2, index, normalizedAmount, msg.sender, address(0));
    liquidity.update(listingId, updates);
    liquidityIndexCount[listingId]++;
}

    function yDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    address tokenB = listing.tokenB();
    uint8 decimals = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
    uint256 normalizedAmount = normalize(amount, decimals);

    if (tokenB == address(0)) {
        require(msg.value == amount, "Incorrect ETH amount");
        (bool success, ) = address(liquidity).call{value: amount}("");
        require(success, "ETH transfer failed");
    } else {
        IERC20(tokenB).safeTransferFrom(msg.sender, address(liquidity), amount);
    }

    uint256 index = liquidityIndexCount[listingId];
    IMFPLiquidity.UpdateType[] memory updates = new IMFPLiquidity.UpdateType[](1);
    updates[0] = IMFPLiquidity.UpdateType(3, index, normalizedAmount, msg.sender, address(0));
    liquidity.update(listingId, updates);
    liquidityIndexCount[listingId]++;
}

    function xWithdraw(address listingAddress, uint256 amount, uint256 index) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (address depositor, , uint256 xAllocation, , ) = liquidity.xLiquiditySlots(listingId, index);
    
    require(depositor == msg.sender, "Not depositor");
    uint256 withdrawAmount = xAllocation < amount ? xAllocation : amount;

    IMFPLiquidity.UpdateType[] memory updates = new IMFPLiquidity.UpdateType[](1);
    updates[0] = IMFPLiquidity.UpdateType(2, index, xAllocation - withdrawAmount, msg.sender, address(0));
    liquidity.update(listingId, updates);

    liquidity.transact(listingId, listing.tokenA(), withdrawAmount, msg.sender);
}

function yWithdraw(address listingAddress, uint256 amount, uint256 index) external nonReentrant {
    require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");
    uint256 listingId = IMFP(listingAgent).getListingId(listingAddress);
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (address depositor, , uint256 yAllocation, , ) = liquidity.yLiquiditySlots(listingId, index);
    
    require(depositor == msg.sender, "Not depositor");
    uint256 withdrawAmount = yAllocation < amount ? yAllocation : amount;

    IMFPLiquidity.UpdateType[] memory updates = new IMFPLiquidity.UpdateType[](1);
    updates[0] = IMFPLiquidity.UpdateType(3, index, yAllocation - withdrawAmount, msg.sender, address(0));
    liquidity.update(listingId, updates);

    liquidity.transact(listingId, listing.tokenB(), withdrawAmount, msg.sender);
}

function _claimFeeShare(
    uint256 volume,
    uint256 dVolume,
    uint256 liquid,
    uint256 allocation,
    uint256 fees
) private pure returns (uint256 feeShare, IMFPLiquidity.UpdateType[] memory updates) {
    updates = new IMFPLiquidity.UpdateType[](2);
    uint256 contributedVolume = volume > dVolume ? volume - dVolume : 0;
    uint256 feesAccrued = (contributedVolume * 5) / 10000;
    uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
    feeShare = (feesAccrued * liquidityContribution) / 1e18;
    feeShare = feeShare > fees ? fees : feeShare;
    return (feeShare, updates);
}

    function xClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
    address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (uint256 xLiquid, , uint256 xFees, ) = liquidity.liquidityDetails(listingId);
    (address xDepositor, , uint256 xAllocation, uint256 xDVolume, ) = liquidity.xLiquiditySlots(listingId, liquidityIndex);
    (, , uint256 xVolume, ) = listing.volumeBalances(listingId);

    require(xDepositor == msg.sender, "Not depositor");

    (uint256 xFeeShare, IMFPLiquidity.UpdateType[] memory updates) = _claimFeeShare(
        xVolume, xDVolume, xLiquid, xAllocation, xFees
    );

    if (xFeeShare > 0) {
        updates[0] = IMFPLiquidity.UpdateType(1, 0, xFees - xFeeShare, address(0), address(0));
        updates[1] = IMFPLiquidity.UpdateType(2, liquidityIndex, xAllocation, xDepositor, address(0));
        liquidity.update(listingId, updates);

        liquidity.transact(listingId, listing.tokenA(), xFeeShare, msg.sender);
        emit FeesClaimed(listingId, liquidityIndex, xFeeShare, 0);
    }
}

function yClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
    address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (, uint256 yLiquid, , uint256 yFees) = liquidity.liquidityDetails(listingId);
    (address yDepositor, , uint256 yAllocation, uint256 yDVolume, ) = liquidity.yLiquiditySlots(listingId, liquidityIndex);
    (, , , uint256 yVolume) = listing.volumeBalances(listingId);

    require(yDepositor == msg.sender, "Not depositor");

    (uint256 yFeeShare, IMFPLiquidity.UpdateType[] memory updates) = _claimFeeShare(
        yVolume, yDVolume, yLiquid, yAllocation, yFees
    );

    if (yFeeShare > 0) {
        updates[0] = IMFPLiquidity.UpdateType(1, 1, yFees - yFeeShare, address(0), address(0));
        updates[1] = IMFPLiquidity.UpdateType(3, liquidityIndex, yAllocation, yDepositor, address(0));
        liquidity.update(listingId, updates);

        liquidity.transact(listingId, listing.tokenB(), yFeeShare, msg.sender);
        emit FeesClaimed(listingId, liquidityIndex, 0, yFeeShare);
    }
}

    function transferLiquidity(uint256 listingId, uint256 liquidityIndex, address newDepositor) external nonReentrant {
    address listingAddress = IMFP(listingAgent).listingValidationByIndex(listingId).listingAddress;
    IMFPListing listing = IMFPListing(listingAddress);
    IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(listingId));
    (address xDepositor, , uint256 xAllocation, , ) = liquidity.xLiquiditySlots(listingId, liquidityIndex);

    require(xDepositor == msg.sender, "Not depositor");

    IMFPLiquidity.UpdateType[] memory updates = new IMFPLiquidity.UpdateType[](2);
    updates[0] = IMFPLiquidity.UpdateType(2, liquidityIndex, xAllocation, newDepositor, address(0));
    updates[1] = IMFPLiquidity.UpdateType(3, liquidityIndex, xAllocation, newDepositor, address(0));
    liquidity.update(listingId, updates);
}
}