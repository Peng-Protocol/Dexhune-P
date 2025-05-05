// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.13 (Updated)
// Changes:
// - Renamed OMF-ProxyRouter to OMFRouter.
// - Imported OMF-OrderLibrary, OMF-SettlementLibrary, and OMF-LiquidLibrary from ./utils/... instead of external contracts.
// - Updated buy, sell, clearSingleOrder, clearUserOrders, settleBuy, settleSell, settleBuyLiquid, settleSellLiquid to use internal library functions.
// - Removed orderLibrary, settlementLibrary, liquidLibrary state variables and their setters.
// - Removed clearSingleOrder and clearOrders from IOMFSettlementLibrary interface.
// - From v0.0.12: Renamed clearOrders to clearUserOrders and updated to call OMFOrderLibrary.clearOrders with msg.sender.
// - From v0.0.11: Removed listingId from all functions to align with implicit listingId in OMFListingTemplate.
// - Updated IOMFListing interface: Changed liquidityAddresses() to liquidityAddress().
// - Updated tokenA to token0, using baseToken from OMFAgent (from v0.0.8).
// - Added volume updates to OMFListingTemplate, added withdrawLiquidity (from v0.0.8).
// - Inlined interfaces for OMFAgent, IOMFLiquidity (from v0.0.8).
// - Replaced updateVolume with update calls, updated withdrawLiquidity to prep/execute (from v0.0.9).
// - Aligned with OMFListingTemplate v0.0.7, removed constructor args, streamlined functions, added claimFees (from previous revision).
// - Updated claimFees to include slotIndex for OMFLiquidityTemplate compatibility (from previous revision).
// - Removed redundant UpdateType struct to fix DeclarationError conflict with IOMFOrderLibrary (from previous revision).

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";
import "./utils/OMF-OrderLibrary.sol";
import "./utils/OMF-SettlementLibrary.sol";
import "./utils/OMF-LiquidLibrary.sol";

interface IOMFListing {
    function token0() external view returns (address);
    function liquidityAddress() external view returns (address);
    function update(address caller, OMFOrderLibrary.UpdateType[] memory updates) external;
}

interface IOMFAgent {
    function getListing(address token0, address baseToken) external view returns (address);
    function baseToken() external view returns (address);
}

interface IOMFSettlementLibrary {
    function settleBuyOrders(address listingAddress, uint256[] memory orderIds, address listingAgent, address proxy) external;
    function settleSellOrders(address listingAddress, uint256[] memory orderIds, address listingAgent, address proxy) external;
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

contract OMFRouter is Ownable {
    using SafeERC20 for IERC20;

    address public agent;

    event BuyOrderPlaced(uint256 orderId, address maker);
    event SellOrderPlaced(uint256 orderId, address maker);
    event OrderCleared(uint256 orderId, bool isBuy);
    event FeesClaimed(address token0, bool isX, uint256 slotIndex, uint256 volume, address claimant);

    function setAgent(address _agent) external onlyOwner {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid address");
        agent = _agent;
    }

    function buy(address token0, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external {
        address listing = getListing(token0);
        OMFOrderLibrary.OrderPrep memory prep = OMFOrderLibrary.prepBuyOrder(
            listing, OMFOrderLibrary.BuyOrderDetails(recipient, amount, maxPrice, minPrice), agent, address(this)
        );
        executeOrder(listing, prep, true);
        emit BuyOrderPlaced(prep.orderId, msg.sender);
    }

    function sell(address token0, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external {
        address listing = getListing(token0);
        OMFOrderLibrary.OrderPrep memory prep = OMFOrderLibrary.prepSellOrder(
            listing, OMFOrderLibrary.SellOrderDetails(recipient, amount, maxPrice, minPrice), agent, address(this)
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
        OMFSettlementLibrary.settleBuyOrders(listing, orderIds, agent, address(this));
    }

    function settleSell(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        OMFSettlementLibrary.settleSellOrders(listing, orderIds, agent, address(this));
    }

    function settleBuyLiquid(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        OMFLiquidLibrary.SettlementData memory data = OMFLiquidLibrary.prepBuyLiquid(listing, orderIds, agent, address(this));
        OMFLiquidLibrary.executeBuyLiquid(listing, data, agent, address(this));
    }

    function settleSellLiquid(address token0, uint256[] memory orderIds) external {
        address listing = getListing(token0);
        OMFLiquidLibrary.SettlementData memory data = OMFLiquidLibrary.prepSellLiquid(listing, orderIds, agent, address(this));
        OMFLiquidLibrary.executeSellLiquid(listing, data, agent, address(this));
    }

    function clearSingleOrder(address token0, uint256 orderId, bool isBuy) external {
        address listing = getListing(token0);
        OMFOrderLibrary.clearSingleOrder(listing, orderId, isBuy, agent, address(this));
        emit OrderCleared(orderId, isBuy);
    }

    function clearUserOrders(address token0) external {
        address listing = getListing(token0);
        OMFOrderLibrary.clearOrders(listing, agent, address(this), msg.sender);
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
        (bool success, bytes memory returnData) = listing.staticcall(abi.encodeWithSignature("liquidityAddress()"));
        require(success, "Liquidity address fetch failed");
        return abi.decode(returnData, (address));
    }

    function executeOrder(address listing, OMFOrderLibrary.OrderPrep memory prep, bool isBuy) internal {
        address liquidity = getLiquidityAddress(listing);
        address token0 = IOMFListing(listing).token0();
        address token = prep.token;
        uint256 preBalance = IERC20(token).balanceOf(listing);
        IERC20(token).safeTransferFrom(msg.sender, listing, prep.principal);
        uint256 actualReceived = IERC20(token).balanceOf(listing) - preBalance;
        if (actualReceived < prep.principal) {
            OMFOrderLibrary.UpdateType[] memory updates = new OMFOrderLibrary.UpdateType[](1);
            updates[0] = OMFOrderLibrary.UpdateType(
                0, token == token0 ? 2 : 3, prep.principal - actualReceived, address(0), address(0), 0, 0
            );
            (bool success, ) = listing.call(abi.encodeWithSignature("update(address,(uint8,uint256,uint256,address,address,uint256,uint256)[])", address(this), updates));
            require(success, "Update volume failed");
        }
        if (prep.fee > 0) IERC20(token).safeTransferFrom(msg.sender, liquidity, prep.fee);
        OMFOrderLibrary.ExecutionState memory state = OMFOrderLibrary.ExecutionState(
            IOMFListing(listing), IOMFLiquidity(liquidity), liquidity
        );
        if (isBuy) {
            OMFOrderLibrary.processExecuteBuyOrder(prep, state, address(this));
        } else {
            OMFOrderLibrary.processExecuteSellOrder(prep, state, address(this));
        }
    }

    function baseToken() public view returns (address) {
        require(agent != address(0), "Agent not set");
        return IOMFAgent(agent).baseToken();
    }
}