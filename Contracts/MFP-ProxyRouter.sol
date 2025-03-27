// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
    function getListingId(address listingAddress) external view returns (uint256);
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
    function deposit(address caller, address token, uint256 amount) external payable;
    function addFees(address caller, bool isX, uint256 fee) external;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function claimFees(address caller, uint256 liquidityIndex, bool isX, uint256 volume) external;
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
    function createBuyOrder(address listingAddress, BuyOrderDetails memory details, address listingAgent, address proxy) external;
    function createSellOrder(address listingAddress, SellOrderDetails memory details, address listingAgent, address proxy) external;
    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy, address listingAgent, address proxy) external;
    function clearOrders(address listingAddress, address listingAgent, address proxy) external;
}

interface IMFPSettlementLibrary {
    function settleBuyOrders(address listingAddress, address listingAgent, address proxy) external;
    function settleSellOrders(address listingAddress, address listingAgent, address proxy) external;
}

interface IMFPLiquidLibrary {
    function settleBuyLiquid(address listingAddress, address listingAgent, address proxy) external;
    function settleSellLiquid(address listingAddress, address listingAgent, address proxy) external;
    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external;
    function xClaimFees(uint256 listingId, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function yClaimFees(uint256 listingId, uint256 liquidityIndex, address listingAgent, address proxy) external;
}

contract MFPProxyRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public orderLibrary;
    address public settlementLibrary;
    address public liquidLibrary;
    address public listingAgent;

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

    constructor() {
        _transferOwnership(msg.sender);
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        require(_orderLibrary != address(0), "Invalid library address");
        orderLibrary = _orderLibrary;
    }

    function setSettlementLibrary(address _settlementLibrary) external onlyOwner {
        require(_settlementLibrary != address(0), "Invalid library address");
        settlementLibrary = _settlementLibrary;
    }

    function setLiquidLibrary(address _liquidLibrary) external onlyOwner {
        require(_liquidLibrary != address(0), "Invalid library address");
        liquidLibrary = _liquidLibrary;
    }

    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent address");
        listingAgent = _agent;
    }

    function createBuyOrder(address listingAddress, BuyOrderDetails memory details) external payable nonReentrant {
        IMFPOrderLibrary(orderLibrary).createBuyOrder(listingAddress, details, listingAgent, address(this));
    }

    function createSellOrder(address listingAddress, SellOrderDetails memory details) external payable nonReentrant {
        IMFPOrderLibrary(orderLibrary).createSellOrder(listingAddress, details, listingAgent, address(this));
    }

    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) external nonReentrant {
        IMFPOrderLibrary(orderLibrary).clearSingleOrder(listingAddress, orderId, isBuy, listingAgent, address(this));
    }

    function clearOrders(address listingAddress) external nonReentrant {
        IMFPOrderLibrary(orderLibrary).clearOrders(listingAddress, listingAgent, address(this));
    }

    function settleBuyOrders(address listingAddress) external nonReentrant {
        IMFPSettlementLibrary(settlementLibrary).settleBuyOrders(listingAddress, listingAgent, address(this));
    }

    function settleSellOrders(address listingAddress) external nonReentrant {
        IMFPSettlementLibrary(settlementLibrary).settleSellOrders(listingAddress, listingAgent, address(this));
    }

    function settleBuyLiquid(address listingAddress) external nonReentrant {
        IMFPLiquidLibrary(liquidLibrary).settleBuyLiquid(listingAddress, listingAgent, address(this));
    }

    function settleSellLiquid(address listingAddress) external nonReentrant {
        IMFPLiquidLibrary(liquidLibrary).settleSellLiquid(listingAddress, listingAgent, address(this));
    }

    function xDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        IMFPLiquidLibrary(liquidLibrary).xDeposit(listingAddress, amount, listingAgent, address(this));
    }

    function yDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        IMFPLiquidLibrary(liquidLibrary).yDeposit(listingAddress, amount, listingAgent, address(this));
    }

    function xClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        IMFPLiquidLibrary(liquidLibrary).xClaimFees(listingId, liquidityIndex, listingAgent, address(this));
    }

    function yClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        IMFPLiquidLibrary(liquidLibrary).yClaimFees(listingId, liquidityIndex, listingAgent, address(this));
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