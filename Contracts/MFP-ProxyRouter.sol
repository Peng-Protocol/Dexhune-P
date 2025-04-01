// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4
// Changes:
// - Updated to use IMFPOrderLibrary.BuyOrderDetails/SellOrderDetails from latest MFPOrderLibrary.
// - Libraries (MFPOrderLibrary, MFPSettlementLibrary, MFPLiquidLibrary) treated as standalone contracts via interfaces.
// - Maintained ETH splitting in buyOrder/sellOrder for principal and fee transfers.

import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

interface IMFP {
    function listingAgent() external view returns (address);
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
        address maker, address recipient, uint256 createdAt, uint256 lastFillAt,
        uint256 pending, uint256 filled, uint256 maxPrice, uint256 minPrice, uint8 status
    );
    function sellOrders(uint256 orderId) external view returns (
        address maker, address recipient, uint256 createdAt, uint256 lastFillAt,
        uint256 pending, uint256 filled, uint256 maxPrice, uint256 minPrice, uint8 status
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
}

interface IMFPLiquidity {
    function addFees(address caller, bool isX, uint256 fee) external;
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
        address proxy
    ) external view returns (OrderPrep memory);
    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy
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
        address proxy
    ) external;
}

interface IMFPSettlementLibrary {
    struct SettlementData {
        uint256 orderCount;
        uint256[] orderIds;
        PreparedUpdate[] updates;
        address tokenA;
        address tokenB;
    }
    struct PreparedUpdate {
        uint256 orderId;
        uint256 value;
        address recipient;
    }
    function prepBuyOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory);
    function executeBuyOrders(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external;
    function prepSellOrders(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory);
    function executeSellOrders(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external;
}

interface IMFPLiquidLibrary {
    struct SettlementData {
        uint256 orderCount;
        uint256[] orderIds;
        PreparedUpdate[] updates;
        address tokenA;
        address tokenB;
    }
    struct PreparedUpdate {
        uint256 orderId;
        uint256 value;
        address recipient;
    }
    function prepBuyLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory);
    function executeBuyLiquid(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external;
    function prepSellLiquid(
        address listingAddress,
        uint256[] memory orderIds,
        address listingAgent,
        address proxy
    ) external view returns (SettlementData memory);
    function executeSellLiquid(
        address listingAddress,
        SettlementData memory data,
        address listingAgent,
        address proxy
    ) external;
    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
}

contract MFPProxyRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IMFP public immutable controller;

    constructor(address _controller) {
        require(_controller != address(0), "Controller not set");
        controller = IMFP(_controller);
    }

    event ListingUpdated(address indexed listingAddress);

    function buyOrder(
        address listingAddress,
        IMFPOrderLibrary.BuyOrderDetails memory details
    ) external payable nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPOrderLibrary orderLibrary = IMFPOrderLibrary(listingAgent);

        IMFPOrderLibrary.OrderPrep memory prep = orderLibrary.prepBuyOrder(
            listingAddress, details, listingAgent, address(this)
        );

        uint256 totalValue = prep.principal + prep.fee;
        if (prep.token == address(0)) {
            require(msg.value >= totalValue, "Insufficient ETH value");
        }

        orderLibrary.executeBuyOrder(listingAddress, prep, listingAgent, address(this));

        if (msg.value > totalValue) {
            (bool success, ) = msg.sender.call{value: msg.value - totalValue}("");
            require(success, "ETH refund failed");
        }
    }

    function sellOrder(
        address listingAddress,
        IMFPOrderLibrary.SellOrderDetails memory details
    ) external payable nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPOrderLibrary orderLibrary = IMFPOrderLibrary(listingAgent);

        IMFPOrderLibrary.OrderPrep memory prep = orderLibrary.prepSellOrder(
            listingAddress, details, listingAgent, address(this)
        );

        uint256 totalValue = prep.principal + prep.fee;
        if (prep.token == address(0)) {
            require(msg.value >= totalValue, "Insufficient ETH value");
        }

        orderLibrary.executeSellOrder(listingAddress, prep, listingAgent, address(this));

        if (msg.value > totalValue) {
            (bool success, ) = msg.sender.call{value: msg.value - totalValue}("");
            require(success, "ETH refund failed");
        }
    }

    function settleBuyOrders(
        address listingAddress,
        uint256[] memory orderIds
    ) external nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPSettlementLibrary settlementLibrary = IMFPSettlementLibrary(listingAgent);
        IMFPSettlementLibrary.SettlementData memory data = settlementLibrary.prepBuyOrders(
            listingAddress, orderIds, listingAgent, address(this)
        );
        if (data.orderCount > 0) {
            settlementLibrary.executeBuyOrders(listingAddress, data, listingAgent, address(this));
            emit ListingUpdated(listingAddress);
        }
    }

    function settleSellOrders(
        address listingAddress,
        uint256[] memory orderIds
    ) external nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPSettlementLibrary settlementLibrary = IMFPSettlementLibrary(listingAgent);
        IMFPSettlementLibrary.SettlementData memory data = settlementLibrary.prepSellOrders(
            listingAddress, orderIds, listingAgent, address(this)
        );
        if (data.orderCount > 0) {
            settlementLibrary.executeSellOrders(listingAddress, data, listingAgent, address(this));
            emit ListingUpdated(listingAddress);
        }
    }

    function settleBuyLiquid(
        address listingAddress,
        uint256[] memory orderIds
    ) external nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPLiquidLibrary liquidLibrary = IMFPLiquidLibrary(listingAgent);
        IMFPLiquidLibrary.SettlementData memory data = liquidLibrary.prepBuyLiquid(
            listingAddress, orderIds, listingAgent, address(this)
        );
        if (data.orderCount > 0) {
            liquidLibrary.executeBuyLiquid(listingAddress, data, listingAgent, address(this));
            emit ListingUpdated(listingAddress);
        }
    }

    function settleSellLiquid(
        address listingAddress,
        uint256[] memory orderIds
    ) external nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPLiquidLibrary liquidLibrary = IMFPLiquidLibrary(listingAgent);
        IMFPLiquidLibrary.SettlementData memory data = liquidLibrary.prepSellLiquid(
            listingAddress, orderIds, listingAgent, address(this)
        );
        if (data.orderCount > 0) {
            liquidLibrary.executeSellLiquid(listingAddress, data, listingAgent, address(this));
            emit ListingUpdated(listingAddress);
        }
    }

    function xDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPLiquidLibrary liquidLibrary = IMFPLiquidLibrary(listingAgent);
        IMFPListing listing = IMFPListing(listingAddress);
        address token = listing.tokenA();
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient ETH deposit");
        }
        liquidLibrary.xDeposit(listingAddress, amount, listingAgent, address(this));
        emit ListingUpdated(listingAddress);
    }

    function yDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPLiquidLibrary liquidLibrary = IMFPLiquidLibrary(listingAgent);
        IMFPListing listing = IMFPListing(listingAddress);
        address token = listing.tokenB();
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient ETH deposit");
        }
        liquidLibrary.yDeposit(listingAddress, amount, listingAgent, address(this));
        emit ListingUpdated(listingAddress);
    }

    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy
    ) external nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPOrderLibrary orderLibrary = IMFPOrderLibrary(listingAgent);
        orderLibrary.clearSingleOrder(listingAddress, orderId, isBuy, listingAgent, address(this));
        emit ListingUpdated(listingAddress);
    }

    function clearOrders(address listingAddress) external nonReentrant {
        address listingAgent = controller.listingAgent();
        IMFPOrderLibrary orderLibrary = IMFPOrderLibrary(listingAgent);
        orderLibrary.clearOrders(listingAddress, listingAgent, address(this));
        emit ListingUpdated(listingAddress);
    }

    receive() external payable {}
}