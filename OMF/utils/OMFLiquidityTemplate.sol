/*
SPDX-License-Identifier: BSD-3-Clause
*/

// Specifying Solidity version for compatibility
pragma solidity ^0.8.2;

// Version: 0.0.15
// Changes:
// - v0.0.15: Updated _processFeeClaim to reset Slot.dFeesAcc to latest yFeesAcc (xSlot) or xFeesAcc (ySlot) after fee claim to align with expected behavior. Ensured no changes to deposit function as it correctly sets dFeesAcc via update function.
// - v0.0.14: Aligned with SSLiquidityTemplate.sol v0.0.12. Added xFeesAcc and yFeesAcc to LiquidityDetails to track cumulative fee volume. Replaced Slot.dVolume with dFeesAcc to store yFeesAcc (xSlot) or xFeesAcc (ySlot) at deposit. Updated claimFees and _processFeeClaim to use contributedFees (fees - dFeesAcc), removing volume, dVolume, price from FeeClaimContext. Updated addFees to increment xFeesAcc or yFeesAcc. Modified update to set dFeesAcc instead of dVolume. Preserved ERC-20-only support, private state variables, view functions, and try-catch in claimFees.
// - v0.0.13: Fixed volumeBalances interface mismatch by updating IOMFListing.volumeBalances to return (uint256 xBalance, uint256 yBalance). Updated claimFees to use volumeBalanceView with try-catch for robustness.
// - v0.0.12: Fixed ParserError in setRouters by correcting syntax from '_routers[routers[i] = true;' to '_routers[routers[i]] = true;'.
// - v0.0.11: Added 'override' specifier to liquidityAmounts to fix TypeError for IOMFLiquidityTemplate interface.
// - v0.0.10: Updated IOMFListing interface to include getPrice() for consistency with OMFListingTemplate.sol.
// - v0.0.9: Updated claimFees and _processFeeClaim to convert fees using IOMFListing.getPrice(). Added price field to FeeClaimContext.
// - v0.0.8: Converted from SSLiquidityTemplate.sol. Restricted to ERC-20 tokens only. Aligned with OMF suite: updated ISSListing to IOMFListing, ISSAgent to IOMFAgent. Added private state variables with view functions. Updated setTokens to fetch ERC-20 decimals.
// - v0.0.7: Refactored claimFees to use FeeClaimContext struct to reduce stack usage.
// - v0.0.6: Removed transferLiquidity function. Updated caller handling in changeSlotDepositor, deposit, xPrepOut, xExecuteOut, yPrepOut, yExecuteOut, claimFees.
// - v0.0.5: Replaced safeTransferFrom with transferFrom in deposit. Added GlobalizeUpdateFailed and UpdateRegistryFailed events.
// - v0.0.4: Added changeSlotDepositor, liquidityAmounts, agent, globalizeUpdate, updateRegistry. Simplified mappings.
// - v0.0.3: Modified claimFees for fee-swapping (xSlots claim yFees, ySlots claim xFees).

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

// Defining interface for OMFListing
interface IOMFListing {
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function volumeBalanceView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getPrice() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
}

// Defining interface for OMFAgent
interface IOMFAgent {
    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
        address user,
        uint256 amount,
        bool isDeposit
    ) external;
}

// Defining interface for TokenRegistry
interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

// Defining interface for OMFLiquidityTemplate
interface IOMFLiquidityTemplate {
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
}

contract OMFLiquidityTemplate is ReentrancyGuard, IOMFLiquidityTemplate {
    using SafeERC20 for IERC20;

    // State variables (hidden, accessed via view functions)
    mapping(address => bool) private _routers; // Maps router addresses
    bool private _routersSet; // Flag for router initialization
    address private _listingAddress; // OMFListing address
    address private _tokenA; // Token-A (first token)
    address private _tokenB; // Token-B (second token)
    uint8 private _decimalA; // Token-A decimals
    uint8 private _decimalB; // Token-B decimals
    uint256 private _listingId; // Listing identifier
    address private _agent; // OMFAgent address
    LiquidityDetails private _liquidityDetail; // Liquidity and fee balances
    mapping(uint256 => Slot) private _xLiquiditySlots; // Token-A liquidity slots
    mapping(uint256 => Slot) private _yLiquiditySlots; // Token-B liquidity slots
    uint256[] private _activeXLiquiditySlots; // Active token-A slot indices
    uint256[] private _activeYLiquiditySlots; // Active token-B slot indices
    mapping(address => uint256[]) private _userIndex; // User address to slot indices

    // Structs for data management
    struct LiquidityDetails {
        uint256 xLiquid; // Token-A liquidity
        uint256 yLiquid; // Token-B liquidity
        uint256 xFees; // Token-A fees
        uint256 yFees; // Token-B fees
        uint256 xFeesAcc; // Cumulative fee volume for x-token
        uint256 yFeesAcc; // Cumulative fee volume for y-token
    }

    struct Slot {
        address depositor; // Slot owner
        address recipient; // Not used
        uint256 allocation; // Allocated liquidity
        uint256 dFeesAcc; // Cumulative fees at deposit (yFeesAcc for xSlot, xFeesAcc for ySlot)
        uint256 timestamp; // Deposit timestamp
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index; // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value; // Amount or allocation (normalized)
        address addr; // Depositor
        address recipient; // Not used
    }

    struct PreparedWithdrawal {
        uint256 amountA; // Token-A withdrawal amount
        uint256 amountB; // Token-B withdrawal amount
    }

    // Struct to reduce stack usage in claimFees
    struct FeeClaimContext {
        address caller; // User claiming fees
        bool isX; // Whether claiming xSlot fees
        uint256 liquid; // Total liquidity (x or y)
        uint256 allocation; // Slot allocation
        uint256 fees; // Available fees
        uint256 dFeesAcc; // Cumulative fees at deposit
        uint256 liquidityIndex; // Slot index
    }

    // Events for tracking actions
    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed caller, uint256 listingId, bool isX, uint256 amount);
    event UpdateRegistryFailed(address indexed caller, bool isX);

    // Constructor (empty, initialized via setters)
    constructor() {}

    // Modifier for router-only access
    modifier onlyRouter() {
        require(_routers[msg.sender], "Router only");
        _;
    }

    // View function for routers mapping
    function routersView(address router) external view returns (bool) {
        return _routers[router];
    }

    // View function for routersSet
    function routersSetView() external view returns (bool) {
        return _routersSet;
    }

    // View function for listingAddress
    function listingAddressView() external view returns (address) {
        return _listingAddress;
    }

    // View function for tokenA
    function tokenAView() external view returns (address) {
        return _tokenA;
    }

    // View function for tokenB
    function tokenBView() external view returns (address) {
        return _tokenB;
    }

    // View function for tokenA decimals
    function decimalAView() external view returns (uint8) {
        return _decimalA;
    }

    // View function for tokenB decimals
    function decimalBView() external view returns (uint8) {
        return _decimalB;
    }

    // View function for listingId
    function listingIdView() external view returns (uint256) {
        return _listingId;
    }

    // View function for agent
    function agentView() external view returns (address) {
        return _agent;
    }

    // View function for liquidityDetail
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) {
        LiquidityDetails memory details = _liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees, details.xFeesAcc, details.yFeesAcc);
    }

    // View function for activeXLiquiditySlots
    function activeXLiquiditySlotsView() external view returns (uint256[] memory) {
        return _activeXLiquiditySlots;
    }

    // View function for activeYLiquiditySlots
    function activeYLiquiditySlotsView() external view returns (uint256[] memory) {
        return _activeYLiquiditySlots;
    }

    // View function for userIndex
    function userIndexView(address user) external view returns (uint256[] memory) {
        return _userIndex[user];
    }

    // View function for xLiquiditySlots
    function getXSlotView(uint256 index) external view returns (Slot memory) {
        return _xLiquiditySlots[index];
    }

    // View function for yLiquiditySlots
    function getYSlotView(uint256 index) external view returns (Slot memory) {
        return _yLiquiditySlots[index];
    }

    // Sets router addresses
    function setRouters(address[] memory routers) external {
        require(!_routersSet, "Routers already set");
        require(routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < routers.length; i++) {
            require(routers[i] != address(0), "Invalid router address");
            _routers[routers[i]] = true;
        }
        _routersSet = true;
    }

    // Sets listing ID
    function setListingId(uint256 listingId) external {
        require(_listingId == 0, "Listing ID already set");
        _listingId = listingId;
    }

    // Sets listing address
    function setListingAddress(address listingAddress) external {
        require(_listingAddress == address(0), "Listing already set");
        require(listingAddress != address(0), "Invalid listing address");
        _listingAddress = listingAddress;
    }

    // Sets token addresses and decimals
    function setTokens(address tokenA, address tokenB) external {
        require(_tokenA == address(0) && _tokenB == address(0), "Tokens already set");
        require(tokenA != address(0) && tokenB != address(0), "Tokens must be ERC-20");
        require(tokenA != tokenB, "Tokens must be different");
        _tokenA = tokenA;
        _tokenB = tokenB;
        _decimalA = IERC20(tokenA).decimals();
        _decimalB = IERC20(tokenB).decimals();
    }

    // Sets agent address
    function setAgent(address agent) external {
        require(_agent == address(0), "Agent already set");
        require(agent != address(0), "Invalid agent address");
        _agent = agent;
    }

    // Normalizes amount to 18 decimals
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    // Denormalizes amount from 18 decimals to token decimals
    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    // Calculates fee share for a slot
    function _claimFeeShare(
        uint256 fees,
        uint256 dFeesAcc,
        uint256 liquid,
        uint256 allocation
    ) private pure returns (uint256 feeShare, UpdateType[] memory updates) {
        updates = new UpdateType[](2);
        uint256 contributedFees = fees > dFeesAcc ? fees - dFeesAcc : 0;
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        feeShare = (contributedFees * liquidityContribution) / 1e18;
        feeShare = feeShare > fees ? fees : feeShare; // Caps at available fees
        return (feeShare, updates);
    }

    // Processes fee claims using context to reduce stack depth
    function _processFeeClaim(FeeClaimContext memory context) internal {
        (uint256 feeShare, UpdateType[] memory updates) = _claimFeeShare(
            context.fees,
            context.dFeesAcc,
            context.liquid,
            context.allocation
        );
        if (feeShare > 0) {
            address transferToken = context.isX ? _tokenA : _tokenB;
            uint8 transferDecimals = context.isX ? _decimalA : _decimalB;
            updates[0] = UpdateType(1, context.isX ? 1 : 0, context.fees - feeShare, address(0), address(0)); // Update yFees or xFees
            updates[1] = UpdateType(context.isX ? 2 : 3, context.liquidityIndex, context.allocation, context.caller, address(0)); // Update xSlot or ySlot
            this.update(context.caller, updates);
            // Reset dFeesAcc to latest feesAcc value
            Slot storage slot = context.isX ? _xLiquiditySlots[context.liquidityIndex] : _yLiquiditySlots[context.liquidityIndex];
            slot.dFeesAcc = context.isX ? _liquidityDetail.yFeesAcc : _liquidityDetail.xFeesAcc;
            uint256 transferAmount = denormalize(feeShare, transferDecimals);
            IERC20(transferToken).safeTransfer(context.caller, transferAmount);
            emit FeesClaimed(_listingId, context.liquidityIndex, context.isX ? feeShare : 0, context.isX ? 0 : feeShare);
        }
    }

    // Updates liquidity balances, fees, or slots
    function update(address caller, UpdateType[] memory updates) external nonReentrant onlyRouter {
        LiquidityDetails storage details = _liquidityDetail;
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) details.xLiquid = u.value;
                else if (u.index == 1) details.yLiquid = u.value;
            } else if (u.updateType == 1) { // Fee update
                if (u.index == 0) {
                    details.xFees = u.value;
                    emit FeesUpdated(_listingId, details.xFees, details.yFees);
                } else if (u.index == 1) {
                    details.yFees = u.value;
                    emit FeesUpdated(_listingId, details.xFees, details.yFees);
                }
            } else if (u.updateType == 2) { // xSlot update
                Slot storage slot = _xLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.yFeesAcc; // Store yFeesAcc for xSlot
                    _activeXLiquiditySlots.push(u.index);
                    _userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    removeUserIndex(u.index, slot.depositor);
                    removeActiveSlot(_activeXLiquiditySlots, u.index);
                }
                slot.allocation = u.value;
                details.xLiquid += u.value;
            } else if (u.updateType == 3) { // ySlot update
                Slot storage slot = _yLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.xFeesAcc; // Store xFeesAcc for ySlot
                    _activeYLiquiditySlots.push(u.index);
                    _userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    removeUserIndex(u.index, slot.depositor);
                    removeActiveSlot(_activeYLiquiditySlots, u.index);
                }
                slot.allocation = u.value;
                details.yLiquid += u.value;
            }
        }
        emit LiquidityUpdated(_listingId, details.xLiquid, details.yLiquid);
    }

    // Syncs liquidity updates with agent
    function globalizeUpdate(address caller, bool isX, uint256 amount, bool isDeposit) internal {
        if (_agent == address(0)) {
            emit GlobalizeUpdateFailed(caller, _listingId, isX, amount);
            return;
        }
        address token = isX ? _tokenA : _tokenB;
        uint8 decimals = isX ? _decimalA : _decimalB;
        uint256 normalizedAmount = normalize(amount, decimals);
        try IOMFAgent(_agent).globalizeLiquidity(
            _listingId,
            _tokenA,
            _tokenB,
            caller,
            normalizedAmount,
            isDeposit
        ) {} catch {
            emit GlobalizeUpdateFailed(caller, _listingId, isX, amount);
        }
    }

    // Updates token registry with user addresses
    function updateRegistry(address caller, bool isX) internal {
        address registry;
        try IOMFListing(_listingAddress).getRegistryAddress() returns (address reg) {
            registry = reg;
        } catch {
            emit UpdateRegistryFailed(caller, isX);
            return;
        }
        if (registry == address(0)) {
            emit UpdateRegistryFailed(caller, isX);
            return;
        }
        address token = isX ? _tokenA : _tokenB;
        address[] memory users = new address[](1);
        users[0] = caller;
        try ITokenRegistry(registry).initializeBalances(token, users) {} catch {
            emit UpdateRegistryFailed(caller, isX);
        }
    }

    // Changes slot depositor
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant onlyRouter {
        require(newDepositor != address(0), "Invalid new depositor");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = isX ? _xLiquiditySlots[slotIndex] : _yLiquiditySlots[slotIndex];
        require(slot.depositor == caller, "Caller not depositor");
        require(slot.allocation > 0, "Invalid slot");
        address oldDepositor = slot.depositor;
        slot.depositor = newDepositor;
        removeUserIndex(slotIndex, oldDepositor);
        _userIndex[newDepositor].push(slotIndex);
        emit SlotDepositorChanged(isX, slotIndex, oldDepositor, newDepositor);
    }

    // Deposits tokens into liquidity
    function deposit(address caller, address token, uint256 amount) external nonReentrant onlyRouter {
        require(token == _tokenA || token == _tokenB, "Invalid token");
        require(caller != address(0), "Invalid caller");
        uint8 decimals = token == _tokenA ? _decimalA : _decimalB;
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        uint256 postBalance = IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        uint256 normalizedAmount = normalize(receivedAmount, decimals);
        UpdateType[] memory updates = new UpdateType[](1);
        uint256 index = token == _tokenA ? _activeXLiquiditySlots.length : _activeYLiquiditySlots.length;
        updates[0] = UpdateType(token == _tokenA ? 2 : 3, index, normalizedAmount, caller, address(0));
        this.update(caller, updates);
        globalizeUpdate(caller, token == _tokenA, receivedAmount, true);
        updateRegistry(caller, token == _tokenA);
    }

    // Prepares withdrawal for tokenA
    function xPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant onlyRouter returns (PreparedWithdrawal memory) {
        require(caller != address(0), "Invalid caller");
        LiquidityDetails storage details = _liquidityDetail;
        Slot storage slot = _xLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        require(slot.allocation >= amount, "Amount exceeds allocation");
        uint256 withdrawAmountA = amount > details.xLiquid ? details.xLiquid : amount;
        uint256 deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0;
        uint256 withdrawAmountB = 0;
        if (deficit > 0) {
            uint256 currentPrice;
            try IOMFListing(_listingAddress).getPrice() returns (uint256 price) {
                currentPrice = price;
            } catch {
                revert("Price fetch failed");
            }
            require(currentPrice > 0, "Price cannot be zero");
            uint256 compensation = (deficit * 1e18) / currentPrice;
            withdrawAmountB = compensation > details.yLiquid ? details.yLiquid : compensation;
        }
        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    // Executes withdrawal for tokenA
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external nonReentrant onlyRouter {
        require(caller != address(0), "Invalid caller");
        Slot storage slot = _xLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amountA, slot.depositor, address(0));
        this.update(caller, updates);
        if (withdrawal.amountA > 0) {
            uint256 amountA = denormalize(withdrawal.amountA, _decimalA);
            IERC20(_tokenA).safeTransfer(caller, amountA);
            globalizeUpdate(caller, true, withdrawal.amountA, false);
            updateRegistry(caller, true);
        }
        if (withdrawal.amountB > 0) {
            uint256 amountB = denormalize(withdrawal.amountB, _decimalB);
            IERC20(_tokenB).safeTransfer(caller, amountB);
            globalizeUpdate(caller, false, withdrawal.amountB, false);
            updateRegistry(caller, false);
        }
    }

    // Prepares withdrawal for tokenB
    function yPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant onlyRouter returns (PreparedWithdrawal memory) {
        require(caller != address(0), "Invalid caller");
        LiquidityDetails storage details = _liquidityDetail;
        Slot storage slot = _yLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        require(slot.allocation >= amount, "Amount exceeds allocation");
        uint256 withdrawAmountB = amount > details.yLiquid ? details.yLiquid : amount;
        uint256 deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0;
        uint256 withdrawAmountA = 0;
        if (deficit > 0) {
            uint256 currentPrice;
            try IOMFListing(_listingAddress).getPrice() returns (uint256 price) {
                currentPrice = price;
            } catch {
                revert("Price fetch failed");
            }
            require(currentPrice > 0, "Price cannot be zero");
            uint256 compensation = (deficit * currentPrice) / 1e18;
            withdrawAmountA = compensation > details.xLiquid ? details.xLiquid : compensation;
        }
        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    // Executes withdrawal for tokenB
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external nonReentrant onlyRouter {
        require(caller != address(0), "Invalid caller");
        Slot storage slot = _yLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amountB, slot.depositor, address(0));
        this.update(caller, updates);
        if (withdrawal.amountB > 0) {
            uint256 amountB = denormalize(withdrawal.amountB, _decimalB);
            IERC20(_tokenB).safeTransfer(caller, amountB);
            globalizeUpdate(caller, false, withdrawal.amountB, false);
            updateRegistry(caller, false);
        }
        if (withdrawal.amountA > 0) {
            uint256 amountA = denormalize(withdrawal.amountA, _decimalA);
            IERC20(_tokenA).safeTransfer(caller, amountA);
            globalizeUpdate(caller, true, withdrawal.amountA, false);
            updateRegistry(caller, true);
        }
    }

    // Claims fees for a liquidity slot
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 /* volume */) external nonReentrant onlyRouter {
        require(listingAddress == _listingAddress, "Invalid listing address");
        require(caller != address(0), "Invalid caller");
        (, uint256 yBalance, , ) = IOMFListing(_listingAddress).volumeBalanceView();
        require(yBalance > 0, "Invalid listing");
        FeeClaimContext memory context;
        context.caller = caller;
        context.isX = isX;
        context.liquidityIndex = liquidityIndex;
        LiquidityDetails storage details = _liquidityDetail;
        Slot storage slot = isX ? _xLiquiditySlots[liquidityIndex] : _yLiquiditySlots[liquidityIndex];
        require(slot.depositor == caller, "Caller not depositor");
        context.liquid = isX ? details.xLiquid : details.yLiquid;
        context.fees = isX ? details.yFees : details.xFees;
        context.allocation = slot.allocation;
        context.dFeesAcc = slot.dFeesAcc;
        _processFeeClaim(context);
    }

    // Handles token transfers
    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant onlyRouter {
        LiquidityDetails storage details = _liquidityDetail;
        uint8 decimals = token == _tokenA ? _decimalA : _decimalB;
        uint256 normalizedAmount = normalize(amount, decimals);
        if (token == _tokenA) {
            require(details.xLiquid >= normalizedAmount, "Insufficient xLiquid");
            details.xLiquid -= normalizedAmount;
            IERC20(token).safeTransfer(recipient, amount);
        } else if (token == _tokenB) {
            require(details.yLiquid >= normalizedAmount, "Insufficient yLiquid");
            details.yLiquid -= normalizedAmount;
            IERC20(token).safeTransfer(recipient, amount);
        } else {
            revert("Invalid token");
        }
        emit LiquidityUpdated(_listingId, details.xLiquid, details.yLiquid);
    }

    // Adds fees to liquidity
    function addFees(address caller, bool isX, uint256 fee) external nonReentrant onlyRouter {
        LiquidityDetails storage details = _liquidityDetail;
        UpdateType[] memory feeUpdates = new UpdateType[](1);
        feeUpdates[0] = UpdateType(1, isX ? 0 : 1, fee, address(0), address(0));
        if (isX) {
            details.xFeesAcc += fee; // Increment cumulative xFeesAcc
        } else {
            details.yFeesAcc += fee; // Increment cumulative yFeesAcc
        }
        this.update(caller, feeUpdates);
    }

    // Updates liquidity balances
    function updateLiquidity(address caller, bool isX, uint256 amount) external nonReentrant onlyRouter {
        LiquidityDetails storage details = _liquidityDetail;
        if (isX) {
            require(details.xLiquid >= amount, "Insufficient xLiquid");
            details.xLiquid -= amount;
        } else {
            require(details.yLiquid >= amount, "Insufficient yLiquid");
            details.yLiquid -= amount;
        }
        emit LiquidityUpdated(_listingId, details.xLiquid, details.yLiquid);
    }

    // Returns liquidity amounts for IOMFLiquidityTemplate
    function liquidityAmounts() external view override returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = _liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    // Returns listing address (ignores listingId)
    function getListingAddress(uint256) external view returns (address) {
        return _listingAddress;
    }

    // Removes slot index from userIndex
    function removeUserIndex(uint256 slotIndex, address user) internal {
        uint256[] storage indices = _userIndex[user];
        for (uint256 i = 0; i < indices.length; i++) {
            if (indices[i] == slotIndex) {
                indices[i] = indices[indices.length - 1];
                indices.pop();
                break;
            }
        }
    }

    // Removes slot index from active slots
    function removeActiveSlot(uint256[] storage slots, uint256 slotIndex) internal {
        for (uint256 i = 0; i < slots.length; i++) {
            if (slots[i] == slotIndex) {
                slots[i] = slots[slots.length - 1];
                slots.pop();
                break;
            }
        }
    }
}