// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.15 (Updated)
// Changes:
// - Updated claimFees to pass listingAddress instead of listingId (new in v0.0.15).
// - Updated IMFPLiquidLibrary interface: xClaimFees, yClaimFees accept listingAddress (new in v0.0.15).
// - Side effects: Aligns with MFPLiquidLibrary’s updated claimFees; prevents listingId mismatches.

import "./imports/SafeERC20.sol";
import "./imports/Ownable.sol";

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
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function pendingBuyOrders(uint256 listingId) external view returns (uint256[] memory);
    function pendingSellOrders(uint256 listingId) external view returns (uint256[] memory);
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function getNextOrderId(uint256 listingId) external view returns (uint256);
}

interface IMFPOrderLibrary {
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
    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IMFPListing.UpdateType[] updates;
        address token;
        address recipient;
    }
    function prepBuyOrder(address listingAddress, BuyOrderDetails memory details, address listingAgent, address proxy, uint256 orderId) external view returns (OrderPrep memory);
    function prepSellOrder(address listingAddress, SellOrderDetails memory details, address listingAgent, address proxy, uint256 orderId) external view returns (OrderPrep memory);
    function executeBuyOrder(address listingAddress, OrderPrep memory prep, address listingAgent, address proxy) external;
    function executeSellOrder(address listingAddress, OrderPrep memory prep, address listingAgent, address proxy) external;
    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy, address listingAgent, address proxy) external;
    function clearOrders(address listingAddress, address listingAgent, address proxy) external;
}

interface IMFPLiquidLibrary {
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
    function prepBuyLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function prepSellLiquid(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function executeBuyLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function executeSellLiquid(address listingAddress, address listingAgent, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function xClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function yClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function xWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory);
    function yWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory);
}

interface IMFPSettlementLibrary {
    struct PreparedUpdate {
        uint256 orderId;
        bool isBuy;
        uint256 amount;
        address recipient;
    }
    function prepBuyOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function prepSellOrders(address listingAddress, address listingAgent) external view returns (PreparedUpdate[] memory);
    function executeBuyOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external;
    function executeSellOrders(address listingAddress, address proxy, PreparedUpdate[] memory preparedUpdates) external;
}

contract MFPProxyRouter is Ownable {
    using SafeERC20 for IERC20;

    address public listingAgent;
    address public orderLibrary;
    address public liquidLibrary;
    address public settlementLibrary;

    function setListingAgent(address _listingAgent) external onlyOwner {
        require(_listingAgent != address(0), "Invalid listing agent address");
        listingAgent = _listingAgent;
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        require(_orderLibrary != address(0), "Invalid order library address");
        orderLibrary = _orderLibrary;
    }

    function setLiquidLibrary(address _liquidLibrary) external onlyOwner {
        require(_liquidLibrary != address(0), "Invalid liquid library address");
        liquidLibrary = _liquidLibrary;
    }

    function setSettlementLibrary(address _settlementLibrary) external onlyOwner {
        require(_settlementLibrary != address(0), "Invalid settlement library address");
        settlementLibrary = _settlementLibrary;
    }

    function buyOrder(address listingAddress, IMFPOrderLibrary.BuyOrderDetails memory details) external payable {
        require(orderLibrary != address(0), "Order library not set");
        require(listingAgent != address(0), "Listing agent not set");
        uint256 orderId = IMFPListing(listingAddress).getNextOrderId(0);
        IMFPOrderLibrary.OrderPrep memory prep = IMFPOrderLibrary(orderLibrary).prepBuyOrder(listingAddress, details, listingAgent, address(this), orderId);
        IMFPOrderLibrary(orderLibrary).executeBuyOrder(listingAddress, prep, listingAgent, address(this));
    }

    function sellOrder(address listingAddress, IMFPOrderLibrary.SellOrderDetails memory details) external payable {
        require(orderLibrary != address(0), "Order library not set");
        require(listingAgent != address(0), "Listing agent not set");
        uint256 orderId = IMFPListing(listingAddress).getNextOrderId(0);
        IMFPOrderLibrary.OrderPrep memory prep = IMFPOrderLibrary(orderLibrary).prepSellOrder(listingAddress, details, listingAgent, address(this), orderId);
        IMFPOrderLibrary(orderLibrary).executeSellOrder(listingAddress, prep, listingAgent, address(this));
    }

    function buyLiquid(address listingAddress) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPLiquidLibrary.PreparedUpdate[] memory updates = IMFPLiquidLibrary(liquidLibrary).prepBuyLiquid(listingAddress, listingAgent);
        IMFPLiquidLibrary(liquidLibrary).executeBuyLiquid(listingAddress, listingAgent, address(this), updates);
    }

    function sellLiquid(address listingAddress) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPLiquidLibrary.PreparedUpdate[] memory updates = IMFPLiquidLibrary(liquidLibrary).prepSellLiquid(listingAddress, listingAgent);
        IMFPLiquidLibrary(liquidLibrary).executeSellLiquid(listingAddress, listingAgent, address(this), updates);
    }

    function settleBuy(address listingAddress) external {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPSettlementLibrary.PreparedUpdate[] memory updates = IMFPSettlementLibrary(settlementLibrary).prepBuyOrders(listingAddress, listingAgent);
        IMFPSettlementLibrary(settlementLibrary).executeBuyOrders(listingAddress, address(this), updates);
    }

    function settleSell(address listingAddress) external {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPSettlementLibrary.PreparedUpdate[] memory updates = IMFPSettlementLibrary(settlementLibrary).prepSellOrders(listingAddress, listingAgent);
        IMFPSettlementLibrary(settlementLibrary).executeSellOrders(listingAddress, address(this), updates);
    }

    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) external {
        require(orderLibrary != address(0), "Order library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPOrderLibrary(orderLibrary).clearSingleOrder(listingAddress, orderId, isBuy, listingAgent, address(this));
    }

    function clearOrders(address listingAddress) external {
        require(orderLibrary != address(0), "Order library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPOrderLibrary(orderLibrary).clearOrders(listingAddress, listingAgent, address(this));
    }

    function deposit(address listingAddress, bool isX, uint256 amount) external payable {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        if (isX) {
            IMFPLiquidLibrary(liquidLibrary).xDeposit(listingAddress, amount, listingAgent, address(this));
        } else {
            IMFPLiquidLibrary(liquidLibrary).yDeposit(listingAddress, amount, listingAgent, address(this));
        }
    }

    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        if (isX) {
            IMFPLiquidLibrary(liquidLibrary).xClaimFees(listingAddress, liquidityIndex, listingAgent, address(this));
        } else {
            IMFPLiquidLibrary(liquidLibrary).yClaimFees(listingAddress, liquidityIndex, listingAgent, address(this));
        }
    }

    function withdraw(address listingAddress, bool isX, uint256 amount, uint256 index) external {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        if (isX) {
            IMFPLiquidLibrary(liquidLibrary).xWithdraw(listingAddress, amount, index, listingAgent, address(this));
        } else {
            IMFPLiquidLibrary(liquidLibrary).yWithdraw(listingAddress, amount, index, listingAgent, address(this));
        }
    }

    receive() external payable {}
}