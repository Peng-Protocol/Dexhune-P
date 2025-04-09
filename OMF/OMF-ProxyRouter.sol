// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.10 (Updated)
// Changes:
// - Updated tokenA to token0, using baseToken from OMFAgent (from v0.0.8).
// - Added volume updates to OMFListingTemplate, added withdrawLiquidity (from v0.0.8).
// - Inlined interfaces for OMFAgent, IOMFOrderLibrary, IOMFSettlementLibrary, IOMFLiquidLibrary, IOMFLiquidity (from v0.0.8).
// - Replaced updateVolume with update calls, updated withdrawLiquidity to prep/execute (from v0.0.9).
// - Aligned with OMFListingTemplate v0.0.7, removed constructor args, streamlined functions, added claimFees (from last revision).
// - Moved IOMFListing to top with other interfaces (from last revision).
// - Updated claimFees to include slotIndex for OMFLiquidityTemplate compatibility (previous revision).
// - Removed redundant UpdateType struct to fix DeclarationError conflict with IOMFOrderLibrary (this revision).

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

interface IOMFListing {
    function token0() external view returns (address);
    function liquidityAddresses(uint256 index) external view returns (address);
    function update(address caller, IOMFOrderLibrary.UpdateType[] memory updates) external;
}

interface IOMFAgent {
    function getListing(address token0, address baseToken) external view returns (address);
    function baseToken() external view returns (address);
}

interface IOMFOrderLibrary {
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct BuyOrderDetails { address recipient; uint256 amount; uint256 maxPrice; uint256 minPrice; }
    struct SellOrderDetails { address recipient; uint256 amount; uint256 maxPrice; uint256 minPrice; }
    struct OrderPrep { uint256 orderId; uint256 principal; uint256 fee; UpdateType[] updates; address token; address recipient; }
    function prepBuyOrder(address listingAddress, BuyOrderDetails memory details, address listingAgent, address proxy) external returns (OrderPrep memory);
    function prepSellOrder(address listingAddress, SellOrderDetails memory details, address listingAgent, address proxy) external returns (OrderPrep memory);
    function executeBuyOrder(address listingAddress, OrderPrep memory prep, address listingAgent, address proxy) external;
    function executeSellOrder(address listingAddress, OrderPrep memory prep, address listingAgent, address proxy) external;
    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy, address listingAgent, address proxy) external;
    function clearOrders(address listingAddress, address listingAgent, address proxy) external;
}

interface IOMFSettlementLibrary {
    function settleBuyOrders(address listingAddress, uint256[] memory orderIds, address listingAgent, address proxy) external;
    function settleSellOrders(address listingAddress, uint256[] memory orderIds, address listingAgent, address proxy) external;
    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy, address listingAgent, address proxy) external;
    function clearOrders(address listingAddress, address listingAgent, address proxy) external;
}

interface IOMFLiquidLibrary {
    struct SettlementData { uint256 orderCount; uint256[] orderIds; PreparedUpdate[] updates; address token0; address baseToken; }
    struct PreparedUpdate { uint256 orderId; uint256 value; address recipient; }
    function prepBuyLiquid(address listingAddress, uint256[] memory orderIds, address listingAgent, address proxy) external view returns (SettlementData memory);
    function prepSellLiquid(address listingAddress, uint256[] memory orderIds, address listingAgent, address proxy) external view returns (SettlementData memory);
    function executeBuyLiquid(address listingAddress, SettlementData memory data, address listingAgent, address proxy) external;
    function executeSellLiquid(address listingAddress, SettlementData memory data, address listingAgent, address proxy) external;
    function claimFees(address listingAddress, bool isX, uint256 volume) external; // Assumed signature; may need slotIndex if updated
}

interface IOMFLiquidity {
    struct PreparedWithdrawal { uint256 amount0; uint256 amount1; }
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function deposit(address caller, bool isX, uint256 amount) external;
    function claimFees(address caller, bool isX, uint256 slotIndex, uint256 volume) external;
}

contract OMFProxyRouter is Ownable {
    using SafeERC20 for IERC20;

    address public agent;
    address public orderLibrary;
    address public settlementLibrary;
    address public liquidLibrary;

    event BuyOrderPlaced(uint256 orderId, address maker);
    event SellOrderPlaced(uint256 orderId, address maker);
    event OrderCleared(uint256 orderId, bool isBuy);
    event FeesClaimed(address token0, bool isX, uint256 slotIndex, uint256 volume, address claimant);

    function setAgent(address _agent) external onlyOwner {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid address");
        agent = _agent;
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        require(_orderLibrary != address(0), "Invalid address");
        orderLibrary = _orderLibrary;
    }

    function setSettlementLibrary(address _settlementLibrary) external onlyOwner {
        require(_settlementLibrary != address(0), "Invalid address");
        settlementLibrary = _settlementLibrary;
    }

    function setLiquidLibrary(address _liquidLibrary) external onlyOwner {
        require(_liquidLibrary != address(0), "Invalid address");
        liquidLibrary = _liquidLibrary;
    }

    function buy(address token0, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external {
        address listing = getListing(token0);
        IOMFOrderLibrary.OrderPrep memory prep = IOMFOrderLibrary(orderLibrary).prepBuyOrder(
            listing, IOMFOrderLibrary.BuyOrderDetails(recipient, amount, maxPrice, minPrice), agent, address(this)
        );
        executeOrder(listing, prep, true);
        emit BuyOrderPlaced(prep.orderId, msg.sender);
    }

    function sell(address token0, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external {
        address listing = getListing(token0);
        IOMFOrderLibrary.OrderPrep memory prep = IOMFOrderLibrary(orderLibrary).prepSellOrder(
            listing, IOMFOrderLibrary.SellOrderDetails(recipient, amount, maxPrice, minPrice), agent, address(this)
        );
        executeOrder(listing, prep, false);
        emit SellOrderPlaced(prep.orderId, msg.sender);
    }

    function deposit(address token0, bool isX, uint256 amount) external {
        address listing = getListing(token0);
        address token = isX ? token0 : baseToken();
        address liquidity = getLiquidityAddress(listing);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(liquidity, amount);
        (bool success, ) = liquidity.call(abi.encodeWithSignature("deposit(address,bool,uint256)", address(this), isX, amount));
        require(success, "Deposit failed");
    }

    function withdrawLiquidity(address token0, bool isX, uint256 slotIndex, uint256 amount) external {
        address listing = getListing(token0);
        address liquidity = getLiquidityAddress(listing);
        IOMFLiquidity.PreparedWithdrawal memory withdrawal = isX
            ? IOMFLiquidity(liquidity).xPrepOut(msg.sender, amount, slotIndex)
            : IOMFLiquidity(liquidity).yPrepOut(msg.sender, amount, slotIndex);
        (bool success, ) = liquidity.call(
            isX ? abi.encodeWithSignature("xExecuteOut(address,uint256,(uint256,uint256))", msg.sender, slotIndex, withdrawal)
                : abi.encodeWithSignature("yExecuteOut(address,uint256,(uint256,uint256))", msg.sender, slotIndex, withdrawal)
        );
        require(success, "Execute withdrawal failed");
    }

    function settleBuy(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        (bool success, ) = settlementLibrary.call(
            abi.encodeWithSignature("settleBuyOrders(address,uint256[],address,address)", listing, orderIds, agent, address(this))
        );
        require(success, "Settle buy failed");
    }

    function settleSell(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        (bool success, ) = settlementLibrary.call(
            abi.encodeWithSignature("settleSellOrders(address,uint256[],address,address)", listing, orderIds, agent, address(this))
        );
        require(success, "Settle sell failed");
    }

    function settleBuyLiquid(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        IOMFLiquidLibrary.SettlementData memory data = IOMFLiquidLibrary(liquidLibrary).prepBuyLiquid(listing, orderIds, agent, address(this));
        (bool success, ) = liquidLibrary.call(
            abi.encodeWithSignature("executeBuyLiquid(address,(uint256,uint256[],(uint256,uint256,address)[],address,address),address,address)", listing, data, agent, address(this))
        );
        require(success, "Execute buy liquid failed");
    }

    function settleSellLiquid(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        IOMFLiquidLibrary.SettlementData memory data = IOMFLiquidLibrary(liquidLibrary).prepSellLiquid(listing, orderIds, agent, address(this));
        (bool success, ) = liquidLibrary.call(
            abi.encodeWithSignature("executeSellLiquid(address,(uint256,uint256[],(uint256,uint256,address)[],address,address),address,address)", listing, data, agent, address(this))
        );
        require(success, "Execute sell liquid failed");
    }

    function clearSingleOrder(address token0, uint256 orderId, bool isBuy) external {
        address listing = getListing(token0);
        (bool success, ) = orderLibrary.call(
            abi.encodeWithSignature("clearSingleOrder(address,uint256,bool,address,address)", listing, orderId, isBuy, agent, address(this))
        );
        require(success, "Clear single order failed");
        emit OrderCleared(orderId, isBuy);
    }

    function clearOrders(address token0) external {
        address listing = getListing(token0);
        (bool success, ) = orderLibrary.call(
            abi.encodeWithSignature("clearOrders(address,address,address)", listing, agent, address(this))
        );
        require(success, "Clear orders failed");
    }

    function claimFees(address token0, bool isX, uint256 slotIndex, uint256 volume) external {
        address listing = getListing(token0);
        address liquidity = getLiquidityAddress(listing);
        (bool success, ) = liquidity.call(
            abi.encodeWithSignature("claimFees(address,bool,uint256,uint256)", msg.sender, isX, slotIndex, volume)
        );
        require(success, "Claim fees failed");
        emit FeesClaimed(token0, isX, slotIndex, volume, msg.sender);
    }

    function getListing(address token0) internal view returns (address) {
        require(agent != address(0), "Agent not set");
        address listing = IOMFAgent(agent).getListing(token0, baseToken());
        require(listing != address(0), "Invalid listing");
        return listing;
    }

    function getLiquidityAddress(address listing) internal view returns (address) {
        (bool success, bytes memory returnData) = listing.staticcall(abi.encodeWithSignature("liquidityAddresses(uint256)", 0));
        require(success, "Liquidity address fetch failed");
        return abi.decode(returnData, (address));
    }

    function executeOrder(address listing, IOMFOrderLibrary.OrderPrep memory prep, bool isBuy) internal {
        address liquidity = getLiquidityAddress(listing);
        address token = prep.token;
        uint256 preBalance = IERC20(token).balanceOf(listing);
        IERC20(token).safeTransferFrom(msg.sender, listing, prep.principal);
        uint256 actualReceived = IERC20(token).balanceOf(listing) - preBalance;
        if (actualReceived < prep.principal) {
            IOMFOrderLibrary.UpdateType[] memory updates = new IOMFOrderLibrary.UpdateType[](1);
            updates[0] = IOMFOrderLibrary.UpdateType(
                0, token == IOMFListing(listing).token0() ? 2 : 3, prep.principal - actualReceived, address(0), address(0), 0, 0
            );
            (bool success, ) = listing.call(abi.encodeWithSignature("update(address,(uint8,uint256,uint256,address,address,uint256,uint256)[])", address(this), updates));
            require(success, "Update volume failed");
        }
        if (prep.fee > 0) IERC20(token).safeTransferFrom(msg.sender, liquidity, prep.fee);
        (bool success, ) = orderLibrary.call(
            isBuy ? abi.encodeWithSignature("executeBuyOrder(address,(uint256,uint256,uint256,(uint8,uint256,uint256,address,address,uint256,uint256)[],address,address),address,address)", listing, prep, agent, address(this))
                  : abi.encodeWithSignature("executeSellOrder(address,(uint256,uint256,uint256,(uint8,uint256,uint256,address,address,uint256,uint256)[],address,address),address,address)", listing, prep, agent, address(this))
        );
        require(success, "Execute order failed");
    }

    function baseToken() public view returns (address) {
        require(agent != address(0), "Agent not set");
        return IOMFAgent(agent).baseToken();
    }
}