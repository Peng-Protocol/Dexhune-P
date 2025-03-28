// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.7

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

interface IMFPOrderLibrary {
    function buyOrder(address listingAddress, address listingAgent, address proxy, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external payable;
    function sellOrder(address listingAddress, address listingAgent, address proxy, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external payable;
}

interface MFPSettlementLibrary {
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

interface MFPLiquidLibrary {
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
    function xClaimFees(uint256 listingId, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function yClaimFees(uint256 listingId, uint256 liquidityIndex, address listingAgent, address proxy) external;
    function xWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory);
    function yWithdraw(address listingAddress, uint256 amount, uint256 index, address listingAgent, address proxy) external returns (PreparedWithdrawal memory);
}

interface IMFPListing {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddresses(uint256 listingId) external view returns (address);
}

interface IMFPLiquidity {
    function deposit(address caller, address token, uint256 amount) external payable;
}

contract MFPProxyRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public orderLibrary;
    address public settlementLibrary;
    address public liquidLibrary;
    address public listingAgent;

    event OrderLibrarySet(address indexed orderLibrary);
    event SettlementLibrarySet(address indexed settlementLibrary);
    event LiquidLibrarySet(address indexed liquidLibrary);
    event ListingAgentSet(address indexed listingAgent);
    event WithdrawalProcessed(address indexed user, address listingAddress, uint256 index, uint256 amountA, uint256 amountB);

    constructor(address _listingAgent) {
        listingAgent = _listingAgent;
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        require(_orderLibrary != address(0), "Invalid address");
        orderLibrary = _orderLibrary;
        emit OrderLibrarySet(_orderLibrary);
    }

    function setSettlementLibrary(address _settlementLibrary) external onlyOwner {
        require(_settlementLibrary != address(0), "Invalid address");
        settlementLibrary = _settlementLibrary;
        emit SettlementLibrarySet(_settlementLibrary);
    }

    function setLiquidLibrary(address _liquidLibrary) external onlyOwner {
        require(_liquidLibrary != address(0), "Invalid address");
        liquidLibrary = _liquidLibrary;
        emit LiquidLibrarySet(_liquidLibrary);
    }

    function setListingAgent(address _listingAgent) external onlyOwner {
        require(_listingAgent != address(0), "Invalid address");
        listingAgent = _listingAgent;
        emit ListingAgentSet(_listingAgent);
    }

    function buyOrder(address listingAddress, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external payable nonReentrant {
        require(orderLibrary != address(0), "Order library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPOrderLibrary(orderLibrary).buyOrder{value: msg.value}(listingAddress, listingAgent, address(this), amount, maxPrice, minPrice, recipient);
    }

    function sellOrder(address listingAddress, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external payable nonReentrant {
        require(orderLibrary != address(0), "Order library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPOrderLibrary(orderLibrary).sellOrder{value: msg.value}(listingAddress, listingAgent, address(this), amount, maxPrice, minPrice, recipient);
    }

    function settleBuyOrders(address listingAddress) external nonReentrant {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPSettlementLibrary.PreparedUpdate[] memory preparedUpdates = MFPSettlementLibrary(settlementLibrary).prepBuyOrders(listingAddress, listingAgent);
        MFPSettlementLibrary(settlementLibrary).executeBuyOrders(listingAddress, address(this), preparedUpdates);
    }

    function settleSellOrders(address listingAddress) external nonReentrant {
        require(settlementLibrary != address(0), "Settlement library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPSettlementLibrary.PreparedUpdate[] memory preparedUpdates = MFPSettlementLibrary(settlementLibrary).prepSellOrders(listingAddress, listingAgent);
        MFPSettlementLibrary(settlementLibrary).executeSellOrders(listingAddress, address(this), preparedUpdates);
    }

    function settleBuyLiquid(address listingAddress) external nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPLiquidLibrary.PreparedUpdate[] memory preparedUpdates = MFPLiquidLibrary(liquidLibrary).prepBuyLiquid(listingAddress, listingAgent);
        MFPLiquidLibrary(liquidLibrary).executeBuyLiquid(listingAddress, listingAgent, address(this), preparedUpdates);
    }

    function settleSellLiquid(address listingAddress) external nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPLiquidLibrary.PreparedUpdate[] memory preparedUpdates = MFPLiquidLibrary(liquidLibrary).prepSellLiquid(listingAddress, listingAgent);
        MFPLiquidLibrary(liquidLibrary).executeSellLiquid(listingAddress, listingAgent, address(this), preparedUpdates);
    }

    function xDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        if (listing.tokenA() == address(0)) {
            liquidity.deposit{value: msg.value}(address(this), listing.tokenA(), amount);
        } else {
            MFPLiquidLibrary(liquidLibrary).xDeposit(listingAddress, amount, listingAgent, address(this));
        }
    }

    function yDeposit(address listingAddress, uint256 amount) external payable nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        IMFPListing listing = IMFPListing(listingAddress);
        IMFPLiquidity liquidity = IMFPLiquidity(listing.liquidityAddresses(0));
        if (listing.tokenB() == address(0)) {
            liquidity.deposit{value: msg.value}(address(this), listing.tokenB(), amount);
        } else {
            MFPLiquidLibrary(liquidLibrary).yDeposit(listingAddress, amount, listingAgent, address(this));
        }
    }

    function xClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPLiquidLibrary(liquidLibrary).xClaimFees(listingId, liquidityIndex, listingAgent, address(this));
    }

    function yClaimFees(uint256 listingId, uint256 liquidityIndex) external nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPLiquidLibrary(liquidLibrary).yClaimFees(listingId, liquidityIndex, listingAgent, address(this));
    }

    function xWithdraw(address listingAddress, uint256 amount, uint256 index) external nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPLiquidLibrary.PreparedWithdrawal memory preparedWithdrawal = MFPLiquidLibrary(liquidLibrary).xWithdraw(
            listingAddress,
            amount,
            index,
            listingAgent,
            address(this)
        );
        emit WithdrawalProcessed(msg.sender, listingAddress, index, preparedWithdrawal.amountA, preparedWithdrawal.amountB);
    }

    function yWithdraw(address listingAddress, uint256 amount, uint256 index) external nonReentrant {
        require(liquidLibrary != address(0), "Liquid library not set");
        require(listingAgent != address(0), "Listing agent not set");
        MFPLiquidLibrary.PreparedWithdrawal memory preparedWithdrawal = MFPLiquidLibrary(liquidLibrary).yWithdraw(
            listingAddress,
            amount,
            index,
            listingAgent,
            address(this)
        );
        emit WithdrawalProcessed(msg.sender, listingAddress, index, preparedWithdrawal.amountA, preparedWithdrawal.amountB);
    }
}