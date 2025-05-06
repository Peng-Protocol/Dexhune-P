// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.17 (Updated)
// Changes:
// - Added import for OMFSharedUtils.sol to use denormalize function.
// - Updated _transferToken to use OMFSharedUtils.denormalize (line 273).
// - From v0.0.16: Removed IOMFListing/IOMFLiquidity interfaces, retained in OMF-Shared.sol.
// - From v0.0.16: Removed direct SafeERC20 import, used OMFShared.SafeERC20.
// - From v0.0.16: Updated to use OMFShared.IOMFListing/IOMFLiquidity.
// - From v0.0.14: Replaced inline assembly in _clearOrders with Solidity array resizing.
// - From v0.0.12: Updated _transferToken to handle tax-on-transfer tokens.
// - From v0.0.10: Removed listingId, aligned with OMFListingTemplate.
// - From v0.0.10: Renamed tokenA to token0, tokenB to baseToken.
// - From v0.0.8: Fixed stack-too-deep in buy/sell using helpers.

import "./imports/Ownable.sol";
import "./utils/OMF-Shared.sol";
import "./utils/OMFSharedUtils.sol";
import "./utils/OMF-OrderAbstract.sol";
import "./utils/OMF-SettlementAbstract.sol";
import "./utils/OMF-LiquidAbstract.sol";

interface IOMFAgent {
    function isValidListing(address listingAddress) external view returns (bool);
}

contract OMFRouter is Ownable {
    using OMFShared.SafeERC20 for IERC20;

    address public agent;

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Agent cannot be zero address");
        agent = _agent;
    }

    function getLiquidityAddress(address listingAddress) external view returns (address) {
        require(IOMFAgent(agent).isValidListing(listingAddress), "Invalid listing");
        return OMFShared.IOMFListing(listingAddress).liquidityAddress();
    }

    function buy(
        address listingAddress,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        IOMFOrderAbstract.BuyOrderDetails memory details = IOMFOrderAbstract.BuyOrderDetails(recipient, amount, maxPrice, minPrice);
        IOMFOrderAbstract.OrderPrep memory prep = OMFOrderAbstract.prepBuyOrder(listingAddress, details, agent, address(this));
        OMFOrderAbstract.executeBuyOrder(listingAddress, prep, agent, address(this));
        OMFSettlementAbstract.settleBuyOrders(listingAddress, new uint256[](0), agent, address(this));
    }

    function sell(
        address listingAddress,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        IOMFOrderAbstract.SellOrderDetails memory details = IOMFOrderAbstract.SellOrderDetails(recipient, amount, maxPrice, minPrice);
        IOMFOrderAbstract.OrderPrep memory prep = OMFOrderAbstract.prepSellOrder(listingAddress, details, agent, address(this));
        OMFOrderAbstract.executeSellOrder(listingAddress, prep, agent, address(this));
        OMFSettlementAbstract.settleSellOrders(listingAddress, new uint256[](0), agent, address(this));
    }

    function deposit(address listingAddress, bool isX, uint256 amount) external {
        require(IOMFAgent(agent).isValidListing(listingAddress), "Invalid listing");
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        address token = isX ? listing.token0() : listing.baseToken();
        uint8 decimals = IERC20(token).decimals();
        uint256 rawAmount = OMFSharedUtils.denormalize(amount, decimals);
        _transferToken(token, address(listing), rawAmount);
        OMFShared.IOMFLiquidity(listing.liquidityAddress()).deposit(address(this), isX, amount);
    }

    function withdrawLiquidity(
        address listingAddress,
        bool isX,
        uint256 amount,
        uint256 index
    ) external {
        require(IOMFAgent(agent).isValidListing(listingAddress), "Invalid listing");
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        OMFShared.IOMFLiquidity liquidity = OMFShared.IOMFLiquidity(listing.liquidityAddress());
        OMFShared.IOMFLiquidity.PreparedWithdrawal memory withdrawal = isX
            ? liquidity.xPrepOut(address(this), amount, index)
            : liquidity.yPrepOut(address(this), amount, index);
        isX
            ? liquidity.xExecuteOut(address(this), index, withdrawal)
            : liquidity.yExecuteOut(address(this), index, withdrawal);
    }

    function claimFees(address listingAddress, bool isX, uint256 volume) external {
        OMFLiquidAbstract.claimFees(listingAddress, isX, volume);
    }

    function executeOrder(
        address listingAddress,
        bool isBuy,
        uint256 amount,
        uint256 orderId,
        uint256 maxPrice,
        uint256 minPrice,
        address recipient
    ) external {
        require(IOMFAgent(agent).isValidListing(listingAddress), "Invalid listing");
        OMFOrderAbstract.adjustOrder(listingAddress, isBuy, amount, orderId, maxPrice, minPrice, recipient);
        isBuy
            ? OMFSettlementAbstract.settleBuyOrders(listingAddress, new uint256[](0), agent, address(this))
            : OMFSettlementAbstract.settleSellOrders(listingAddress, new uint256[](0), agent, address(this));
    }

    function clearOrders(address listingAddress) external {
        require(IOMFAgent(agent).isValidListing(listingAddress), "Invalid listing");
        _clearOrders(listingAddress, agent, address(this), msg.sender);
    }

    function _clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address user
    ) internal {
        OMFShared.IOMFListing listing = OMFShared.IOMFListing(listingAddress);
        (bool success, bytes memory returnData) = listingAddress.staticcall(
            abi.encodeWithSignature("makerPendingOrdersView(address)", user)
        );
        require(success, "Failed to fetch user orders");
        uint256[] memory userOrders = abi.decode(returnData, (uint256[]));

        if (userOrders.length == 0) return;

        OMFShared.UpdateType[] memory updates = new OMFShared.UpdateType[](userOrders.length);
        uint256 updateCount = 0;

        for (uint256 i = 0; i < userOrders.length; i++) {
            bool isValid;
            ClearOrderState memory orderState;

            // Try buy order
            (orderState, isValid) = validateAndPrepareRefund(listing, userOrders[i], true, user);
            if (isValid) {
                executeRefundAndUpdate(listing, proxy, orderState, updates, updateCount, true, userOrders[i]);
                updateCount++;
                continue;
            }

            // Try sell order
            (orderState, isValid) = validateAndPrepareRefund(listing, userOrders[i], false, user);
            if (isValid) {
                executeRefundAndUpdate(listing, proxy, orderState, updates, updateCount, false, userOrders[i]);
                updateCount++;
            }
        }

        if (updateCount > 0) {
            if (updateCount < updates.length) {
                OMFShared.UpdateType[] memory resized = new OMFShared.UpdateType[](updateCount);
                for (uint256 i = 0; i < updateCount; i++) {
                    resized[i] = updates[i];
                }
                updates = resized;
            }
            listing.update(proxy, updates);
        }
    }

    function _transferToken(address token, address target, uint256 amount) internal returns (uint256) {
        uint256 preBalance = IERC20(token).balanceOf(target);
        IERC20(token).safeTransferFrom(msg.sender, target, amount);
        uint256 postBalance = IERC20(token).balanceOf(target);
        return postBalance - preBalance;
    }

    // Structs and helpers for _clearOrders
    struct ClearOrderState {
        address makerAddress;
        address recipientAddress;
        uint256 pending;
        uint8 status;
        address refundTo;
        uint256 refundAmount;
        address token;
    }

    function validateAndPrepareRefund(
        OMFShared.IOMFListing listing,
        uint256 orderId,
        bool isBuy,
        address user
    ) internal view returns (ClearOrderState memory orderState, bool isValid) {
        orderState = ClearOrderState({
            makerAddress: address(0),
            recipientAddress: address(0),
            pending: 0,
            status: 0,
            refundTo: address(0),
            refundAmount: 0,
            token: address(0)
        });

        if (isBuy) {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = listing.buyOrders(orderId);
            if (status == 1 || status == 2) {
                if (makerAddress != user) return (orderState, false);
                orderState.makerAddress = makerAddress;
                orderState.recipientAddress = recipientAddress;
                orderState.pending = pending;
                orderState.status = status;
                orderState.refundTo = recipientAddress != address(0) ? recipientAddress : makerAddress;
                orderState.refundAmount = pending;
                orderState.token = listing.token0();
                return (orderState, true);
            }
        } else {
            (
                address makerAddress,
                address recipientAddress,
                uint256 maxPrice,
                uint256 minPrice,
                uint256 pending,
                uint256 filled,
                uint8 status
            ) = listing.sellOrders(orderId);
            if (status == 1 || status == 2) {
                if (makerAddress != user) return (orderState, false);
                orderState.makerAddress = makerAddress;
                orderState.recipientAddress = recipientAddress;
                orderState.pending = pending;
                orderState.status = status;
                orderState.refundTo = recipientAddress != address(0) ? recipientAddress : makerAddress;
                orderState.refundAmount = pending;
                orderState.token = listing.baseToken();
                return (orderState, true);
            }
        }
        return (orderState, false);
    }

    function executeRefundAndUpdate(
        OMFShared.IOMFListing listing,
        address proxy,
        ClearOrderState memory orderState,
        OMFShared.UpdateType[] memory updates,
        uint256 updateIndex,
        bool isBuy,
        uint256 orderId
    ) internal {
        if (orderState.refundAmount > 0) {
            uint8 decimals = IERC20(orderState.token).decimals();
            uint256 rawAmount = OMFSharedUtils.denormalize(orderState.refundAmount, decimals);
            listing.transact(proxy, orderState.token, rawAmount, orderState.refundTo);
        }
        updates[updateIndex] = OMFShared.UpdateType(
            isBuy ? 1 : 2,
            orderId,
            0,
            address(0),
            address(0),
            0,
            0
        );
    }
}