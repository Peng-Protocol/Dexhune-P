// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.24
// Changes:
// - Revised calculateImpactPrice to account only for tokens moved out of the listing during settlement.
// - For buy orders: Only reduce xBalance (tokenA out), keep yBalance unchanged.
// - For sell orders: Only reduce yBalance (tokenB out), keep xBalance unchanged.
// - Preserved all prior changes from v0.0.23.

import "../imports/SafeERC20.sol";
import "../imports/Ownable.sol";
import "../imports/ReentrancyGuard.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IMFPAgent {
    function globalizeLiquidity(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit) external;
    function getListing(address tokenA, address tokenB) external view returns (address);
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

interface IMFPListing {
    struct ListingUpdateType {
        uint8 orderType; // 0 = balance, 1 = buy order, 2 = sell order
        uint8 structId; // 0 = core, 1 = pricing, 2 = amounts
        uint256 orderId;
        uint256 value;
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function getListingId() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function buyOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    function sellOrderPricingView(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled);
    function update(ListingUpdateType[] memory updates) external;
    function transact(address token, uint256 amount, address recipient) external;
    function nextOrderId() external view returns (uint256);
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function liquidityAddress() external view returns (address);
}

interface IMFPLiquidityTemplate {
    function deposit(address caller, address token, uint256 amount) external payable;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function addFees(address caller, bool isX, uint256 fee) external;
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (IMFPListing.PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (IMFPListing.PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, IMFPListing.PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, IMFPListing.PreparedWithdrawal memory withdrawal) external;
}

contract MFPMainPartial is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct VolumeBalance {
        uint256 xBalance;
        uint256 yBalance;
        uint256 xVolume;
        uint256 yVolume;
    }

    struct BuyOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }

    struct BuyOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct BuyOrderAmounts {
        uint256 pending;
        uint256 filled;
    }

    struct SellOrderCore {
        address makerAddress;
        address recipientAddress;
        uint8 status;
    }

    struct SellOrderPricing {
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct SellOrderAmounts {
        uint256 pending;
        uint256 filled;
    }

    struct HistoricalData {
        uint256 timestamp;
        uint256 volume;
        uint256 price;
    }

    struct LiquidityDetails {
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 xFees;
        uint256 yFees;
    }

    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dVolume;
        uint256 timestamp;
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }

    struct OrderPrep {
        uint256 listingId;
        uint256 amount;
        address token;
        address maker;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct BuyOrderDetails {
        address listingAddress;
        uint256 listingId;
        uint256 orderId;
        address maker;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 principal;
        uint256 actualReceived;
    }

    struct SellOrderDetails {
        address listingAddress;
        uint256 listingId;
        uint256 orderId;
        address maker;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 principal;
        uint256 actualReceived;
    }

    struct PreparedUpdate {
        uint256 listingId;
        uint256 orderId;
        uint256 amount;
        uint256 principal;
    }

    struct SettlementData {
        uint256 listingId;
        uint256 amount;
        uint256 principal;
        bool isBuy;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure virtual returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (18 - decimals);
        else return amount / 10 ** (decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (18 - decimals);
        else return amount * 10 ** (decimals - 18);
    }

    function calculateImpactPrice(
        uint256 amount,
        uint256 xBalance,
        uint256 yBalance,
        bool isBuy
    ) internal pure returns (uint256) {
        require(yBalance > 0, "Zero yBalance");
        uint256 currentPrice = (xBalance * 1e18) / yBalance;
        uint256 amountOut = isBuy ? (amount * currentPrice) / 1e18 : (amount * 1e18) / currentPrice;
        uint256 newXBalance = xBalance;
        uint256 newYBalance = yBalance;

        if (isBuy) {
            // Buy: Only tokenA (x) moves out
            require(xBalance >= amountOut, "Insufficient xBalance");
            newXBalance = xBalance - amountOut;
        } else {
            // Sell: Only tokenB (y) moves out
            require(yBalance >= amountOut, "Insufficient yBalance");
            newYBalance = yBalance - amountOut;
        }

        require(newYBalance > 0, "Zero new yBalance");
        return (newXBalance * 1e18) / newYBalance;
    }

    function _transferToken(address token, address from, address to, uint256 amount) internal virtual {
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            if (to != address(this)) {
                (bool success, ) = to.call{value: amount}("");
                require(success, "ETH transfer failed");
            }
        } else {
            IERC20(token).safeTransferFrom(from, to, amount);
        }
    }

    function _normalizeAndFee(address token, uint256 amount, bool isBuy) internal view returns (uint256 normalized, uint256 fee) {
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        normalized = normalize(amount, decimals);
        fee = (normalized * 5) / 10000; // 0.05% fee
    }

    function _createOrderUpdate(
        uint256 listingId,
        uint256 orderId,
        uint256 amount,
        address maker,
        address recipient,
        uint256 maxPrice,
        uint256 minPrice,
        bool isBuy
    ) internal pure returns (IMFPListing.ListingUpdateType[] memory) {
        IMFPListing.ListingUpdateType[] memory updates = new IMFPListing.ListingUpdateType[](3);
        updates[0] = IMFPListing.ListingUpdateType(isBuy ? 1 : 2, 0, orderId, 0, maker, recipient, 0, 0);
        updates[1] = IMFPListing.ListingUpdateType(isBuy ? 1 : 2, 1, orderId, 0, address(0), address(0), maxPrice, minPrice);
        updates[2] = IMFPListing.ListingUpdateType(isBuy ? 1 : 2, 2, orderId, amount, address(0), address(0), 0, 0);
        return updates;
    }
}