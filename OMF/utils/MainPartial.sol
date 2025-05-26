// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.2;

// Version: 0.1.5
// Most Recent Changes:
// - From v0.1.4: Added OrderProcessingFailed event to IOMF interface for graceful degradation.
// - Preserved settleBuyOrders, settleSellOrders, settleBuyLiquid, and settleSellLiquid in IOMF interface.
// - Maintained agent, setAgent, and helper functions for OrderPartial and OMFRouter.
// - Kept OrderUpdate struct fix (removed duplicate historicalPrice, corrected typo).
// - Verified helper functions (transferToken, normalizeAndFee, etc.) are available for OrderPartial and OMFRouter.

import "../imports/Ownable.sol";
import "../imports/SafeERC20.sol";

interface IOMF {
    function validateListing(address listingAddress) external view returns (bool, address, address, address);
    function settleBuyOrders(address listingAddress) external;
    function settleSellOrders(address listingAddress) external;
    function settleBuyLiquid(address listingAddress) external;
    function settleSellLiquid(address listingAddress) external;
}

interface IOMFListing {
    function volumeBalances() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getPrice() external view returns (uint256);
    function nextOrderId() external returns (uint256);
    function update(UpdateType[] memory updates) external;
    function transact(address token, uint256 amount, address recipient) external;
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function isOrderCompleteView(uint256 orderId, bool isBuy) external view returns (bool);
    function liquidityAddress() external view returns (address);
    function token0() external view returns (address);
    function baseToken() external view returns (address);
}

interface IOMFLiquidity {
    function deposit(address caller, bool isX, uint256 amount) external;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function claimFees(address caller, bool isX, uint256 slotIndex, uint256 volume) external;
    function userIndexView(address user) external view returns (uint256[] memory);
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
    function token0() external view returns (address);
    function baseToken() external view returns (address);
    function activeXLiquiditySlotsView() external view returns (uint256[] memory);
    function activeYLiquiditySlotsView() external view returns (uint256[] memory);
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external;
}

struct UpdateType {
    uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
    uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts (for updateType 1, 2)
    uint256 index;    // orderId or slot index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume for type 0)
    uint256 value;    // principal or amount (normalized) or price (for historical)
    address addr;     // makerAddress
    address recipient;// recipientAddress
    uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
    uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
}

struct OrderUpdate {
    uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
    uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts
    uint256 orderId;
    uint256 value;
    uint256 historicalPrice;
    address recipient;
}

struct PrimaryOrderUpdate {
    uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order
    uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts
    uint256 orderId;
    uint256 pendingValue; // Pending amount or balance
    address recipient;
    uint256 maxPrice; // For Pricing struct
    uint256 minPrice; // For Pricing struct
}

struct SecondaryOrderUpdate {
    uint8 updateType; // 0 = balance, 3 = historical
    uint8 structId;   // 0 = Core, 1 = Pricing, 2 = Amounts
    uint256 orderId;
    uint256 filledValue; // Filled amount or price
    uint256 historicalPrice; // For historical updates
}

struct BuyOrderDetails {
    address recipient;
    uint256 amount;
    uint256 maxPrice;
    uint256 minPrice;
}

struct SellOrderDetails {
    address recipient;
    uint256 amount;
    uint256 maxPrice;
    uint256 minPrice;
}

struct OrderState {
    address maker;
    address recipient;
    uint256 pending;
    uint8 status;
    address token;
}

struct TempOrderUpdate {
    uint256 orderId;
    uint256 value;
    address recipient;
    bool isBuy;
}

struct PreparedWithdrawal {
    uint256 amount0;
    uint256 amount1;
}

struct Slot {
    address depositor;
    uint256 allocation;
    uint256 dVolume;
    uint256 timestamp;
}

struct LiquidExecutionState {
    address token0;
    address baseToken;
    uint8 token0Decimals;
    uint8 baseTokenDecimals;
    uint256 price;
}

contract MainPartial is Ownable {
    using SafeERC20 for IERC20;

    address public agent;

    event OrderCreated(uint256 orderId, bool isBuy);
    event OrderCancelled(uint256 orderId, bool isBuy);
    event OrderProcessingFailed(address indexed listingAddress, uint256 indexed orderId, bool isBuy, string reason);

    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
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

    function computeOrderAmounts(
        uint256 price,
        uint256 pending,
        bool isBuy,
        uint8 token0Decimals,
        uint8 baseTokenDecimals
    ) internal pure returns (uint256 baseTokenAmount, uint256 token0Amount) {
        uint256 normalizedPending = normalize(pending, isBuy ? baseTokenDecimals : token0Decimals);
        if (isBuy) {
            baseTokenAmount = normalizedPending;
            token0Amount = (normalizedPending * 1e18) / price;
            token0Amount = denormalize(token0Amount, token0Decimals);
        } else {
            token0Amount = normalizedPending;
            baseTokenAmount = (normalizedPending * price) / 1e18;
            baseTokenAmount = denormalize(baseTokenAmount, baseTokenDecimals);
        }
        return (baseTokenAmount, token0Amount);
    }

    function performTransactionAndAdjust(
        address listingAddress,
        address token,
        uint256 amount,
        address recipient,
        uint8 decimals
    ) internal returns (uint256) {
        uint256 preBalance = IERC20(token).balanceOf(recipient);
        IOMFListing(listingAddress).transact(token, amount, recipient);
        uint256 postBalance = IERC20(token).balanceOf(recipient);
        return normalize(postBalance - preBalance, decimals);
    }

    function transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = IERC20(token).balanceOf(target);
        IERC20(token).safeTransferFrom(msg.sender, target, amount);
        uint256 postBalance = IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    function normalizeAndFee(address token, uint256 amount) internal view returns (uint256 normalized, uint256 fee, uint256 principal) {
        normalized = normalize(amount, IERC20(token).decimals());
        fee = (normalized * 5) / 10000; // 0.05% fee
        principal = normalized - fee;
    }

    function transferAndPrepareOrder(
        address token,
        address listingAddress,
        uint256 amount
    ) internal returns (uint256 orderId, uint256 principal, uint256 fee) {
        uint256 actualReceived = transferToken(token, listingAddress, amount);
        (uint256 normalized, uint256 feeAmount, uint256 principalAmount) = normalizeAndFee(token, actualReceived);
        orderId = IOMFListing(listingAddress).nextOrderId();
        return (orderId, principalAmount, feeAmount);
    }

    function getLiquidityAddressInternal(address listingAddress) internal view returns (address) {
        return IOMFListing(listingAddress).liquidityAddress();
    }

    function getUserSlotIndex(address liquidityAddress, address user, bool isX) internal view returns (uint256) {
        uint256[] memory userSlots = IOMFLiquidity(liquidityAddress).userIndexView(user);
        for (uint256 i = 0; i < userSlots.length; i++) {
            Slot memory slot = isX ? IOMFLiquidity(liquidityAddress).getXSlotView(userSlots[i]) : IOMFLiquidity(liquidityAddress).getYSlotView(userSlots[i]);
            if (slot.depositor == user) return userSlots[i];
        }
        return isX ? IOMFLiquidity(liquidityAddress).activeXLiquiditySlotsView().length : IOMFLiquidity(liquidityAddress).activeYLiquiditySlotsView().length;
    }
}