// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.20
// Changes:
// - Removed smiley face emoji typos from transact calls in xExecuteOut and yExecuteOut.
// - Fixed typos in yPrepOut: corrected routerAddressAaron to routerAddress, removed redundant normalized(normalize(...)).
// - Fixed typo in yExecuteOut: corrected slot.depositor_index to slot.depositor.
// - Refactored claimFees into _fetchClaimData and _processFeeClaim helpers with ClaimData struct to resolve stack too deep error.
// - Added payable keyword to addFees function to allow msg.value usage.
// - Updated xPrepOut, yPrepOut, xExecuteOut, yExecuteOut to use IMFPListing.PreparedWithdrawal.
// - Added local variables xFees, yFees in update function to resolve undeclared identifier errors.
// - Removed mapping(uint256 => LiquidityDetails), replaced with LiquidityDetails public liquidityDetails to support single listing, aligning with OMF-LiquidityTemplate.sol (v0.0.15).
// - Removed listingId from xLiquiditySlots, yLiquiditySlots, activeXLiquiditySlots, activeYLiquiditySlots mappings/arrays.
// - Added updateRegistry to sync depositor balances with TokenRegistry after deposit, xExecuteOut, yExecuteOut, fetching registry address via IMFPListing.getRegistryAddress.
// - Added ITokenRegistry interface and RegistryUpdateFailed event.
// - Added agent, setAgent, globalizeUpdate, IMFPAgent interface, GlobalLiquidityUpdated event, and onlyRouter modifier for global liquidity synchronization.
// - Added changeSlotDepositor and SlotDepositorChanged event, removed transferLiquidity (redundant).
// - Added liquidityAmounts and feeAmounts view functions to support MFP-ListingTemplate.sol queryYield and align with OMF-LiquidityTemplate.sol.
// - Added removeSlot helper function, updated update to use it for slot removal with stack depth mitigation comments.
// - Updated claimFees to use calculateFeeShare, directly update xFees/yFees, removing _claimFeeShare.
// - Updated deposit, xExecuteOut, yExecuteOut to include globalizeUpdate and updateRegistry calls with try-catch.
// - Updated xPrepOut, yPrepOut to use IMFPListing.prices(listingId) for compatibility with MFP-ListingTemplate.sol, retained getPrice in IMFPListing for future alignment.
// - Removed updateLiquidity (redundant with update).
// - Added constructor to initialize listingId = 0.
// - Retained validateListing, getListingId, and native ETH support (payable deposit, transact ETH transfers).
// - Preserved core functionality: liquidity updates, deposits, withdrawals, fee claims, view functions.

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IMFPListing {
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function getListingId() external view returns (uint256);
    function getPrice() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }
}

interface IMFPAgent {
    function globalizeLiquidity(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit) external;
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

contract MFPLiquidityTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public listingAddress;
    address public tokenA;
    address public tokenB;
    uint256 public listingId;
    address public agent;

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
        uint256 index;    // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value;    // amount or allocation (normalized)
        address addr;     // depositor
        address recipient;// unused
    }

    struct ClaimData {
        uint256 tVolume;
        uint256 liquid;
        uint256 fees;
        uint256 allocation;
        uint256 feeShare;
        uint8 decimals;
    }

    LiquidityDetails public liquidityDetails;
    mapping(uint256 => Slot) public xLiquiditySlots;
    mapping(uint256 => Slot) public yLiquiditySlots;
    uint256[] public activeXLiquiditySlots;
    uint256[] public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event GlobalLiquidityUpdated(bool isX, uint256 amount, bool isDeposit, address caller);
    event SlotDepositorChanged(bool isX, uint256 slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event RegistryUpdateFailed(string reason);

    constructor() {
        listingId = 0;
    }

    modifier onlyRouter() {
        require(msg.sender == routerAddress, "Only router");
        _;
    }

    function setRouter(address _routerAddress) external {
        require(routerAddress == address(0), "Router already set");
        require(_routerAddress != address(0), "Invalid router address");
        routerAddress = _routerAddress;
    }

    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setAgent(address _agent) external {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (18 - decimals);
        else return amount / 10 ** (decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (18 - decimals);
        else return amount * 10 ** (decimals - 18);
    }

    function updateRegistry(address caller, bool isX) internal {
        address registry = address(0);
        try IMFPListing(listingAddress).getRegistryAddress() returns (address reg) {
            registry = reg;
        } catch {
            emit RegistryUpdateFailed("Registry fetch failed");
            return;
        }
        if (registry == address(0)) {
            emit RegistryUpdateFailed("Registry not set");
            return;
        }
        address token = isX ? tokenA : tokenB;
        address[] memory users = new address[](1);
        users[0] = caller;
        try ITokenRegistry(registry).initializeBalances(token, users) {} catch {
            emit RegistryUpdateFailed("Registry update failed");
        }
    }

    function globalizeUpdate(address caller, bool isX, uint256 amount, bool isDeposit) external onlyRouter nonReentrant {
        require(amount > 0, "Invalid amount");
        require(agent != address(0), "Agent not set");
        address token = isX ? tokenA : tokenB;
        uint256 normalizedAmount = normalize(amount, token == address(0) ? 18 : IERC20(token).decimals());
        try IMFPAgent(agent).globalizeLiquidity(
            listingId,
            tokenA,
            tokenB,
            caller,
            normalizedAmount,
            isDeposit
        ) {} catch {
            emit GlobalLiquidityUpdated(isX, normalizedAmount, isDeposit, caller);
        }
        emit GlobalLiquidityUpdated(isX, normalizedAmount, isDeposit, caller);
    }

    function removeSlot(bool isX, uint256 slotIndex) internal {
        mapping(uint256 => Slot) storage slots = isX ? xLiquiditySlots : yLiquiditySlots;
        uint256[] storage activeSlots = isX ? activeXLiquiditySlots : activeYLiquiditySlots;
        address depositor = slots[slotIndex].depositor;
        slots[slotIndex] = Slot(address(0), address(0), 0, 0, 0);
        for (uint256 i = 0; i < activeSlots.length; i++) {
            if (activeSlots[i] == slotIndex) {
                activeSlots[i] = activeSlots[activeSlots.length - 1];
                activeSlots.pop();
                break;
            }
        }
        for (uint256 i = 0; i < userIndex[depositor].length; i++) {
            if (userIndex[depositor][i] == slotIndex) {
                userIndex[depositor][i] = userIndex[depositor][userIndex[depositor].length - 1];
                userIndex[depositor].pop();
                break;
            }
        }
    }

    // Using UpdateType struct and removeSlot function mitigates stack depth issues
    // by reducing variable scope and modularizing slot removal logic
    function update(address caller, UpdateType[] memory updates) external onlyRouter {
        LiquidityDetails storage details = liquidityDetails;
        uint256 xFees = details.xFees; // Store in local variable
        uint256 yFees = details.yFees; // Store in local variable

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) details.xLiquid = u.value;
                else if (u.index == 1) details.yLiquid = u.value;
            } else if (u.updateType == 1) { // Fee update
                if (u.index == 0) {
                    xFees += u.value;
                    details.xFees = xFees;
                    emit FeesUpdated(listingId, xFees, yFees);
                } else if (u.index == 1) {
                    yFees += u.value;
                    details.yFees = yFees;
                    emit FeesUpdated(listingId, xFees, yFees);
                }
            } else if (u.updateType == 2) { // xSlot update
                Slot storage slot = xLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.recipient = u.recipient;
                    slot.timestamp = block.timestamp;
                    activeXLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                    details.xLiquid += u.value;
                } else if (u.addr == address(0)) {
                    removeSlot(true, u.index);
                }
                slot.allocation = u.value;
                (, , uint256 xVolume, ) = IMFPListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = xVolume;
            } else if (u.updateType == 3) { // ySlot update
                Slot storage slot = yLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.recipient = u.recipient;
                    slot.timestamp = block.timestamp;
                    activeYLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                    details.yLiquid += u.value;
                } else if (u.addr == address(0)) {
                    removeSlot(false, u.index);
                }
                slot.allocation = u.value;
                (, , , uint256 yVolume) = IMFPListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = yVolume;
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external onlyRouter {
        require(newDepositor != address(0), "Invalid new depositor");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == caller, "Not depositor");
        require(slot.allocation > 0, "Invalid slot");
        address oldDepositor = slot.depositor;
        slot.depositor = newDepositor;
        for (uint256 i = 0; i < userIndex[oldDepositor].length; i++) {
            if (userIndex[oldDepositor][i] == slotIndex) {
                userIndex[oldDepositor][i] = userIndex[oldDepositor][userIndex[oldDepositor].length - 1];
                userIndex[oldDepositor].pop();
                break;
            }
        }
        userIndex[newDepositor].push(slotIndex);
        emit SlotDepositorChanged(isX, slotIndex, oldDepositor, newDepositor);
    }

    function calculateFeeShare(
        uint256 volume,
        uint256 dVolume,
        uint256 liquid,
        uint256 allocation,
        uint256 fees
    ) internal pure returns (uint256) {
        uint256 contributedVolume = volume > dVolume ? volume - dVolume : 0;
        uint256 feesAccrued = (contributedVolume * 5) / 10000;
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        uint256 feeShare = (feesAccrued * liquidityContribution) / 1e18;
        return feeShare > fees ? fees : feeShare;
    }

    function _fetchClaimData(
        bool isX,
        uint256 liquidityIndex
    ) internal view returns (ClaimData memory) {
        LiquidityDetails storage details = liquidityDetails;
        Slot storage slot = isX ? xLiquiditySlots[liquidityIndex] : yLiquiditySlots[liquidityIndex];
        (, , uint256 xVolume, uint256 yVolume) = IMFPListing(listingAddress).volumeBalances(listingId);
        ClaimData memory data;
        data.tVolume = isX ? xVolume : yVolume;
        data.liquid = isX ? details.xLiquid : details.yLiquid;
        data.fees = isX ? details.xFees : details.yFees;
        data.allocation = slot.allocation;
        data.decimals = isX ? (tokenA == address(0) ? 18 : IERC20(tokenA).decimals()) : (tokenB == address(0) ? 18 : IERC20(tokenB).decimals());
        return data;
    }

    function _processFeeClaim(
        address caller,
        bool isX,
        uint256 liquidityIndex,
        ClaimData memory data
    ) internal {
        LiquidityDetails storage details = liquidityDetails;
        Slot storage slot = isX ? xLiquiditySlots[liquidityIndex] : yLiquiditySlots[liquidityIndex];
        if (data.feeShare > 0) {
            if (isX) {
                require(details.xFees >= data.feeShare, "Insufficient xFees");
                details.xFees -= data.feeShare;
            } else {
                require(details.yFees >= data.feeShare, "Insufficient yFees");
                details.yFees -= data.feeShare;
            }
            slot.dVolume = data.tVolume;
            this.transact(caller, isX ? tokenA : tokenB, denormalize(data.feeShare, data.decimals), msg.sender);
            emit FeesClaimed(listingId, liquidityIndex, isX ? data.feeShare : 0, isX ? 0 : data.feeShare);
        }
    }

    function claimFees(
        address caller,
        address listingAddressParam,
        uint256 liquidityIndex,
        bool isX,
        uint256 volume
    ) external nonReentrant {
        require(caller == routerAddress, "Router only");
        require(IMFP(routerAddress).isValidListing(listingAddressParam), "Invalid listing");
        require(listingAddressParam == listingAddress, "Listing address mismatch");
        Slot storage slot = isX ? xLiquiditySlots[liquidityIndex] : yLiquiditySlots[liquidityIndex];
        require(slot.depositor == msg.sender, "Not depositor");

        ClaimData memory data = _fetchClaimData(isX, liquidityIndex);
        data.feeShare = calculateFeeShare(data.tVolume, slot.dVolume, data.liquid, data.allocation, data.fees);
        _processFeeClaim(caller, isX, liquidityIndex, data);
    }

    function addFees(address caller, bool isX, uint256 fee) external payable onlyRouter nonReentrant {
        require(fee > 0, "Invalid fee");
        address token = isX ? tokenA : tokenB;
        uint256 preBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        if (token == address(0)) {
            require(msg.value == fee, "Incorrect ETH amount");
        } else {
            IERC20(token).safeTransferFrom(caller, address(this), fee);
        }
        uint256 postBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 actualReceived = postBalance - preBalance;
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(1, isX ? 0 : 1, normalize(actualReceived, token == address(0) ? 18 : IERC20(token).decimals()), address(0), address(0));
        this.update(caller, updates);
    }

    function deposit(address caller, address token, uint256 amount) external payable nonReentrant {
        require(caller == routerAddress, "Router only");
        require(token == tokenA || token == tokenB, "Invalid token");
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 preBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        uint256 normalizedAmount = normalize(receivedAmount, decimals);

        UpdateType[] memory updates = new UpdateType[](1);
        uint256 index = token == tokenA ? activeXLiquiditySlots.length : activeYLiquiditySlots.length;
        updates[0] = UpdateType(token == tokenA ? 2 : 3, index, normalizedAmount, msg.sender, address(0));
        this.update(caller, updates);
        try this.globalizeUpdate(caller, token == tokenA, normalizedAmount, true) {} catch {
            emit GlobalLiquidityUpdated(token == tokenA, normalizedAmount, true, caller);
        }
        updateRegistry(caller, token == tokenA);
    }

    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(caller == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (token == tokenA) {
            require(details.xLiquid >= normalizedAmount, "Insufficient xLiquid");
            details.xLiquid -= normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else if (token == tokenB) {
            require(details.yLiquid >= normalizedAmount, "Insufficient yLiquid");
            details.yLiquid -= normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else {
            revert("Invalid token");
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function xPrepOut(address caller, uint256 amount, uint256 index) external onlyRouter returns (IMFPListing.PreparedWithdrawal memory) {
        require(caller == routerAddress, "Only router");
        LiquidityDetails storage details = liquidityDetails;
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == caller, "Not depositor");
        uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
        uint256 normalizedAmount = normalize(amount, decimalsA);
        require(slot.allocation >= normalizedAmount, "Amount exceeds allocation");

        uint256 withdrawAmountA = normalizedAmount > details.xLiquid ? details.xLiquid : normalizedAmount;
        uint256 deficit = normalizedAmount > withdrawAmountA ? normalizedAmount - withdrawAmountA : 0;
        uint256 withdrawAmountB = 0;

        if (deficit > 0) {
            uint256 currentPrice = IMFPListing(listingAddress).prices(listingId);
            require(currentPrice > 0, "Price cannot be zero");
            withdrawAmountB = (deficit * 1e18) / currentPrice;
            withdrawAmountB = withdrawAmountB > details.yLiquid ? details.yLiquid : withdrawAmountB;
        }
        return IMFPListing.PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function yPrepOut(address caller, uint256 amount, uint256 index) external onlyRouter returns (IMFPListing.PreparedWithdrawal memory) {
        require(caller == routerAddress, "Only router");
        LiquidityDetails storage details = liquidityDetails;
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == caller, "Not depositor");
        uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
        uint256 normalizedAmount = normalize(amount, decimalsB);
        require(slot.allocation >= normalizedAmount, "Amount exceeds allocation");

        uint256 withdrawAmountB = normalizedAmount > details.yLiquid ? details.yLiquid : normalizedAmount;
        uint256 deficit = normalizedAmount > withdrawAmountB ? normalizedAmount - withdrawAmountB : 0;
        uint256 withdrawAmountA = 0;

        if (deficit > 0) {
            uint256 currentPrice = IMFPListing(listingAddress).prices(listingId);
            require(currentPrice > 0, "Price cannot be zero");
            withdrawAmountA = (deficit * currentPrice) / 1e18;
            withdrawAmountA = withdrawAmountA > details.xLiquid ? details.xLiquid : withdrawAmountA;
        }
        return IMFPListing.PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function xExecuteOut(address caller, uint256 index, IMFPListing.PreparedWithdrawal memory withdrawal) external nonReentrant {
        require(caller == routerAddress, "Router only");
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == caller, "Not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amountA, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            this.transact(caller, tokenA, denormalize(withdrawal.amountA, decimalsA), slot.depositor);
            try this.globalizeUpdate(caller, true, withdrawal.amountA, false) {} catch {
                emit GlobalLiquidityUpdated(true, withdrawal.amountA, false, caller);
            }
            updateRegistry(caller, true);
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            this.transact(caller, tokenB, denormalize(withdrawal.amountB, decimalsB), slot.depositor);
            try this.globalizeUpdate(caller, false, withdrawal.amountB, false) {} catch {
                emit GlobalLiquidityUpdated(false, withdrawal.amountB, false, caller);
            }
            updateRegistry(caller, false);
        }
    }

    function yExecuteOut(address caller, uint256 index, IMFPListing.PreparedWithdrawal memory withdrawal) external nonReentrant {
        require(caller == routerAddress, "Router only");
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == caller, "Not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amountB, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            this.transact(caller, tokenB, denormalize(withdrawal.amountB, decimalsB), slot.depositor);
            try this.globalizeUpdate(caller, false, withdrawal.amountB, false) {} catch {
                emit GlobalLiquidityUpdated(false, withdrawal.amountB, false, caller);
            }
            updateRegistry(caller, false);
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            this.transact(caller, tokenA, denormalize(withdrawal.amountA, decimalsA), slot.depositor);
            try this.globalizeUpdate(caller, true, withdrawal.amountA, false) {} catch {
                emit GlobalLiquidityUpdated(true, withdrawal.amountA, false, caller);
            }
            updateRegistry(caller, true);
        }
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = liquidityDetails;
        return (details.xLiquid, details.yLiquid);
    }

    function feeAmounts() external view returns (uint256 xFee, uint256 yFee) {
        LiquidityDetails memory details = liquidityDetails;
        return (details.xFees, details.yFees);
    }

    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) {
        LiquidityDetails memory details = liquidityDetails;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees);
    }

    function activeXLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeXLiquiditySlots;
    }

    function activeYLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeYLiquiditySlots;
    }

    function userIndexView(address user) external view returns (uint256[] memory) {
        return userIndex[user];
    }

    function getXSlotView(uint256 index) external view returns (Slot memory) {
        return xLiquiditySlots[index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory) {
        return yLiquiditySlots[index];
    }

    function getListingId() external view returns (uint256) {
        return listingId;
    }

    function validateListing(address listingAddressParam) external view {
        require(IMFP(routerAddress).isValidListing(listingAddressParam), "Invalid listing");
        require(listingAddressParam == listingAddress, "Listing address mismatch");
        (uint256 xBalance, , , ) = IMFPListing(listingAddress).volumeBalances(listingId);
        require(xBalance > 0, "Invalid listing");
    }
}