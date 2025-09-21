// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// Version: 0.1.5
// Changes:
// - v0.1.5: Updated ICCListing interface to replace UpdateType with BuyOrderUpdate, SellOrderUpdate, BalanceUpdate, HistoricalUpdate structs and modified ccUpdate function signature to accept these structs. 
// - v0.1.5: Added historical data interfaces.
// - v0.1.4: Updated ICCListing interface to move payout-related structs and functions aligning with CCListingTemplate.sol v0.3.5 where payout functionality was moved to CCLiquidityTemplate.sol v0.1.9. 
// - v0.1.3: Updated ICCLiquidity interface to rename update to ccUpdate, reflecting changes in CCLiquidityTemplate.sol.
// - v0.1.2: Updated ICCListing interface to include new PayoutUpdate struct with orderId and added activeLongPayoutsView, activeShortPayoutsView, activeUserPayoutIDsView functions per CCListingTemplatePatch.txt v0.3.2.
// - v0.1.1: Updated `ICCListing.PayoutUpdate` struct to include `filled` and `amountSent` fields, aligning with CCListingTemplate.sol v0.3.0 to fix TypeError in CCOrderPartial.sol.
// - v0.1.0: Bumped version
// - v0.0.14: Updated onlyValidListing modifier to use try-catch for ICCAgent.isValidListing, explicitly destructure ListingDetails, and validate non-zero addresses. Added detailed revert reason for debugging. Updated compatibility comments.
// - v0.0.13: Added nextXSlotIDView and nextYSlotIDView to ICCLiquidity interface for CCLiquidityTemplate.sol v0.1.1 compatibility.
// - v0.0.12: Added userXIndexView and userYIndexView to ICCLiquidity interface.
// - v0.0.11: Modified onlyValidListing modifier to use CCAgent.isValidListing.
// Compatible with CCListingTemplate.sol (v0.1.0), CCOrderRouter.sol (v0.0.11), CCUniPartial.sol (v0.0.7), ICCLiquidity.sol (v0.0.5), CCLiquidityRouter.sol (v0.0.27), CCAgent.sol (v0.1.2), CCLiquidityTemplate.sol (v0.1.1).

import "../imports/IERC20.sol";
import "../imports/ReentrancyGuard.sol"; // Our ReentrancyGuard imports Ownable 

interface ICCListing {
        struct BuyOrderUpdate {
            uint8 structId; // 0: Core, 1: Pricing, 2: Amounts
            uint256 orderId; // Order ID
            address makerAddress; // Maker address
            address recipientAddress; // Recipient address
            uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
            uint256 maxPrice; // Max price for Pricing
            uint256 minPrice; // Min price for Pricing
            uint256 pending; // Pending amount for Amounts
            uint256 filled; // Filled amount for Amounts
            uint256 amountSent; // Amount sent for Amounts
        }

        struct SellOrderUpdate {
            uint8 structId; // 0: Core, 1: Pricing, 2: Amounts
            uint256 orderId; // Order ID
            address makerAddress; // Maker address
            address recipientAddress; // Recipient address
            uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
            uint256 maxPrice; // Max price for Pricing
            uint256 minPrice; // Min price for Pricing
            uint256 pending; // Pending amount for Amounts
            uint256 filled; // Filled amount for Amounts
            uint256 amountSent; // Amount sent for Amounts
        }

        struct BalanceUpdate {
            uint256 xBalance; // Normalized xBalance
            uint256 yBalance; // Normalized yBalance
        }

        struct HistoricalUpdate {
            uint256 price; // Current price
            uint256 xBalance; // xBalance
            uint256 yBalance; // yBalance
            uint256 xVolume; // xVolume
            uint256 yVolume; // yVolume
            uint256 timestamp; // Timestamp
        }

        struct HistoricalData {
            uint256 price;
            uint256 xBalance;
            uint256 yBalance;
            uint256 xVolume;
            uint256 yVolume;
            uint256 timestamp;
        }

        function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance);
        function prices(uint256 _listingId) external view returns (uint256);
        function liquidityAddressView() external view returns (address);
        function tokenA() external view returns (address);
        function tokenB() external view returns (address);
        function decimalsA() external view returns (uint8);
        function decimalsB() external view returns (uint8);
        function getNextOrderId() external view returns (uint256);
        function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory data);
        function historicalDataLengthView() external view returns (uint256 length);
        function pendingBuyOrdersView() external view returns (uint256[] memory);
        function pendingSellOrdersView() external view returns (uint256[] memory);
        function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
        function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
        function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
        function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
        function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
        function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
        function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
        function transactToken(address token, uint256 amount, address recipient) external;
        function transactNative(uint256 amount, address recipient) external payable;
        function uniswapV2PairView() external view returns (address);
        function setUniswapV2Pair(address _uniswapV2Pair) external;
        function setRouters(address[] memory _routers) external;
        function setListingId(uint256 _listingId) external;
        function setLiquidityAddress(address _liquidityAddress) external;
        function setTokens(address _tokenA, address _tokenB) external;
        function setAgent(address _agent) external;
        function setRegistry(address _registryAddress) external;
        function ccUpdate(
            BuyOrderUpdate[] calldata buyUpdates,
            SellOrderUpdate[] calldata sellUpdates,
            BalanceUpdate[] calldata balanceUpdates,
            HistoricalUpdate[] calldata historicalUpdates
        ) external;
        function agentView() external view returns (address);
    }

interface ICCLiquidity {
    struct UpdateType {
        uint8 updateType; // 0=balance, 1=fees, 2=xSlot, 3=ySlot
        uint256 index; // 0=xFees/xLiquid, 1=yFees/yLiquid, or slot index
        uint256 value; // Normalized amount or allocation
        address addr; // Depositor address
        address recipient; // Unused recipient address
    }

    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dFeesAcc;
        uint256 timestamp;
    }

    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    struct LongPayoutStruct {
        address makerAddress; // Payout creator
        address recipientAddress; // Payout recipient
        uint256 required; // Amount required
        uint256 filled; // Amount filled
        uint256 amountSent; // Amount of opposite token sent
        uint256 orderId; // Payout order ID
        uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
    }

    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount; // Amount required
        uint256 filled; // Amount filled
        uint256 amountSent; // Amount of opposite token sent
        uint256 orderId; // Payout order ID
        uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
    }

    struct PayoutUpdate {
        uint8 payoutType; // 0: Long, 1: Short
        address recipient; // Payout recipient
        uint256 orderId; // Explicit orderId for targeting
        uint256 required; // Amount required for payout
        uint256 filled; // Amount filled during settlement
        uint256 amountSent; // Amount of opposite token sent
    }

    function routerAddressesView() external view returns (address[] memory);
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setAgent(address _agent) external;
    function ccUpdate(address depositor, UpdateType[] memory updates) external;
    function transactToken(address depositor, address token, uint256 amount, address recipient) external;
    function transactNative(address depositor, uint256 amount, address recipient) external;
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc);
    function userXIndexView(address user) external view returns (uint256[] memory);
    function userYIndexView(address user) external view returns (uint256[] memory);
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
    function getActiveXLiquiditySlots() external view returns (uint256[] memory slots);
    function getActiveYLiquiditySlots() external view returns (uint256[] memory slots);
    function ssUpdate(PayoutUpdate[] calldata updates) external;
    function longPayoutByIndexView() external view returns (uint256[] memory);
    function shortPayoutByIndexView() external view returns (uint256[] memory);
    function userPayoutIDsView(address user) external view returns (uint256[] memory);
    function activeLongPayoutsView() external view returns (uint256[] memory);
    function activeShortPayoutsView() external view returns (uint256[] memory);
    function activeUserPayoutIDsView(address user) external view returns (uint256[] memory);
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory);
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory);
}

interface ICCAgent {
    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }
    function getListing(address tokenA, address tokenB) external view returns (address);
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

contract CCMainPartial is ReentrancyGuard {
    address internal agent;
    address internal uniswapV2Router;

    struct BuyOrderDetails {
        uint256 orderId;
        address maker;
        address receiver;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct SellOrderDetails {
        uint256 orderId;
        address maker;
        address receiver;
        uint256 pending;
        uint256 filled;
        uint256 maxPrice;
        uint256 minPrice;
        uint8 status;
    }

    struct OrderClearData {
        uint256 id;
        bool isBuy;
        uint256 amount;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Normalizes amount to 18 decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Denormalizes amount from 18 decimals to token decimals
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function checkValidListing(address listing) private view {
        // Validates listing against agent registry using contract's own agent
        ICCListing listingTemplate = ICCListing(listing);
        address tokenAAddress = listingTemplate.tokenA();
        address tokenBAddress = listingTemplate.tokenB();
        require(agent != address(0), "Contract agent not set");
        require(ICCAgent(agent).getListing(tokenAAddress, tokenBAddress) == listing, "Invalid listing");
    }

    modifier onlyValidListing(address listing) {
        // Validates listing using ICCAgent.isValidListing with try-catch and detailed validation
        require(agent != address(0), "Contract agent not set");
        bool isValid;
        ICCAgent.ListingDetails memory details;
        try ICCAgent(agent).isValidListing(listing) returns (bool _isValid, ICCAgent.ListingDetails memory _details) {
            isValid = _isValid;
            details = _details;
        } catch (bytes memory reason) {
            revert(string(abi.encodePacked("Listing validation failed: ", reason)));
        }
        require(isValid, "Listing not found in agent registry");
        require(details.listingAddress == listing, "Listing address mismatch");
        require(details.liquidityAddress != address(0), "Invalid liquidity address");
        require(details.tokenA != details.tokenB, "Identical tokens in pair");
        _;
    }

    function setAgent(address newAgent) external onlyOwner {
        // Sets new agent address
        require(newAgent != address(0), "Invalid agent address");
        agent = newAgent;
    }

    function setUniswapV2Router(address newRouter) external onlyOwner {
        // Sets Uniswap V2 router address
        require(newRouter != address(0), "Invalid router address");
        uniswapV2Router = newRouter;
    }

    function agentView() external view returns (address) {
        // Returns current agent address
        return agent;
    }

    function uniswapV2RouterView() external view returns (address) {
        // Returns Uniswap V2 router address
        return uniswapV2Router;
    }
}