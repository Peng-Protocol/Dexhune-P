// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.10 (Updated)
// Changes:
// - Aligned with MFPLiquidityTemplate: LiquidityDetails, UpdateType, update, split withdraw (from v0.0.9).
// - Added IMFPListing (renamed IOMFListing) for tVolume (from v0.0.9).
// - Implemented getPrice() from OMFListingTemplate in x/yPrepOut for withdrawal compensation (new in v0.0.10).
// - Fixed DeclarationError: Corrected typo "abi_decode" to "abi.decode" in yPrepOut (this revision).

import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";

interface IOMFListing {
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getPrice() external view returns (uint256);
} 

contract OMFLiquidityTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public router;
    address public listingAddress;
    uint256 public listingId;

    address public token0;    // Token-0 (listed token)
    address public baseToken; // Token-1 (reference token)

    struct LiquidityDetails {
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 xFees;
        uint256 yFees;
    }

    struct Slot {
        address depositor;
        uint256 allocation; // Normalized amount contributed
        uint256 dVolume;    // Volume at deposit time (reset on claim)
        uint256 timestamp;
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;    // 0 = xLiquid/xFees, 1 = yLiquid/yFees, or slot index
        uint256 value;    // Amount or allocation
        address addr;     // Depositor
        address recipient;// Unused
    }

    struct PreparedWithdrawal {
        uint256 amount0; // token0
        uint256 amount1; // baseToken
    }

    mapping(uint256 => LiquidityDetails) public liquidityDetails;
    mapping(uint256 => mapping(uint256 => Slot)) public xLiquiditySlots;
    mapping(uint256 => mapping(uint256 => Slot)) public yLiquiditySlots;
    mapping(uint256 => uint256[]) public activeXLiquiditySlots;
    mapping(uint256 => uint256[]) public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    event LiquidityAdded(bool isX, uint256 amount);
    event FeesAdded(bool isX, uint256 amount);
    event FeesClaimed(bool isX, uint256 amount, address depositor);
    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);

    constructor() {}

    modifier onlyRouter() {
        require(msg.sender == router, "Only router");
        _;
    }

    function setRouter(address _router) external {
        require(router == address(0), "Router already set");
        require(_router != address(0), "Invalid router");
        router = _router;
    }

    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        require(listingAddress == address(0), "Listing address already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _token0, address _baseToken) external {
        require(token0 == address(0) && baseToken == address(0), "Tokens already set");
        require(_token0 != address(0) && _baseToken != address(0), "Tokens cannot be NATIVE");
        require(_token0 != _baseToken, "Identical tokens");
        token0 = _token0;
        baseToken = _baseToken;
    }

    function update(address caller, UpdateType[] memory updates) external onlyRouter {
        LiquidityDetails storage details = liquidityDetails[listingId];
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) details.xLiquid = u.value;
                else if (u.index == 1) details.yLiquid = u.value;
            } else if (u.updateType == 1) { // Fee update
                if (u.index == 0) details.xFees += u.value;
                else if (u.index == 1) details.yFees += u.value;
            } else if (u.updateType == 2) { // xSlot update
                Slot storage slot = xLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    activeXLiquiditySlots[listingId].push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    removeSlot(true, u.index);
                }
                slot.allocation = u.value;
                (, , uint256 xVolume, ) = IOMFListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = xVolume;
                details.xLiquid += u.value;
            } else if (u.updateType == 3) { // ySlot update
                Slot storage slot = yLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    activeYLiquiditySlots[listingId].push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    removeSlot(false, u.index);
                }
                slot.allocation = u.value;
                (, , , uint256 yVolume) = IOMFListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = yVolume;
                details.yLiquid += u.value;
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function addFees(address caller, bool isX, uint256 fee) external onlyRouter nonReentrant {
        require(fee > 0, "Invalid fee");
        address token = isX ? token0 : baseToken;
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(caller, address(this), fee);
        uint256 actualReceived = IERC20(token).balanceOf(address(this)) - preBalance;
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(1, isX ? 0 : 1, actualReceived, address(0), address(0));
        this.update(caller, updates);
        emit FeesAdded(isX, actualReceived);
    }

    function deposit(address caller, bool isX, uint256 amount) external onlyRouter nonReentrant {
        require(amount > 0, "Invalid amount");
        address token = isX ? token0 : baseToken;
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(caller, address(this), amount);
        uint256 postBalance = IERC20(token).balanceOf(address(this));
        uint256 actualReceived = postBalance - preBalance;
        uint256 normalizedAmount = normalize(actualReceived, IERC20(token).decimals());

        UpdateType[] memory updates = new UpdateType[](1);
        uint256 slotIndex = isX ? activeXLiquiditySlots[listingId].length : activeYLiquiditySlots[listingId].length;
        updates[0] = UpdateType(isX ? 2 : 3, slotIndex, normalizedAmount, caller, address(0));
        this.update(caller, updates);
        emit LiquidityAdded(isX, normalizedAmount);
    }

    function xPrepOut(address caller, uint256 amount, uint256 index) external onlyRouter returns (PreparedWithdrawal memory) {
        LiquidityDetails storage details = liquidityDetails[listingId];
        Slot storage slot = xLiquiditySlots[listingId][index];
        require(slot.depositor == caller, "Not depositor");
        uint256 normalizedAmount = normalize(amount, IERC20(token0).decimals());
        require(slot.allocation >= normalizedAmount, "Amount exceeds allocation");

        uint256 withdrawAmount0 = normalizedAmount > details.xLiquid ? details.xLiquid : normalizedAmount;
        uint256 deficit = normalizedAmount > withdrawAmount0 ? normalizedAmount - withdrawAmount0 : 0;
        uint256 withdrawAmount1 = 0;

        if (deficit > 0) {
            (bool success, bytes memory returnData) = listingAddress.staticcall(abi.encodeWithSignature("getPrice()"));
            require(success, "Price fetch failed");
            uint256 currentPrice = abi.decode(returnData, (uint256));
            require(currentPrice > 0, "Price cannot be zero");
            withdrawAmount1 = (deficit * 1e18) / currentPrice;
            withdrawAmount1 = withdrawAmount1 > details.yLiquid ? details.yLiquid : withdrawAmount1;
        }
        return PreparedWithdrawal(withdrawAmount0, withdrawAmount1);
    }

    function yPrepOut(address caller, uint256 amount, uint256 index) external onlyRouter returns (PreparedWithdrawal memory) {
        LiquidityDetails storage details = liquidityDetails[listingId];
        Slot storage slot = yLiquiditySlots[listingId][index];
        require(slot.depositor == caller, "Not depositor");
        uint256 normalizedAmount = normalize(amount, IERC20(baseToken).decimals());
        require(slot.allocation >= normalizedAmount, "Amount exceeds allocation");

        uint256 withdrawAmount1 = normalizedAmount > details.yLiquid ? details.yLiquid : normalizedAmount;
        uint256 deficit = normalizedAmount > withdrawAmount1 ? normalizedAmount - withdrawAmount1 : 0;
        uint256 withdrawAmount0 = 0;

        if (deficit > 0) {
            (bool success, bytes memory returnData) = listingAddress.staticcall(abi.encodeWithSignature("getPrice()"));
            require(success, "Price fetch failed");
            uint256 currentPrice = abi.decode(returnData, (uint256));
            require(currentPrice > 0, "Price cannot be zero");
            withdrawAmount0 = (deficit * currentPrice) / 1e18;
            withdrawAmount0 = withdrawAmount0 > details.xLiquid ? details.xLiquid : withdrawAmount0;
        }
        return PreparedWithdrawal(withdrawAmount0, withdrawAmount1);
    }

    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external onlyRouter nonReentrant {
        Slot storage slot = xLiquiditySlots[listingId][index];
        require(slot.depositor == caller, "Not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amount0, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amount0 > 0) {
            this.transact(caller, token0, denormalize(withdrawal.amount0, IERC20(token0).decimals()), caller);
        }
        if (withdrawal.amount1 > 0) {
            this.transact(caller, baseToken, denormalize(withdrawal.amount1, IERC20(baseToken).decimals()), caller);
        }
    }

    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external onlyRouter nonReentrant {
        Slot storage slot = yLiquiditySlots[listingId][index];
        require(slot.depositor == caller, "Not depositor");
        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amount1, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amount1 > 0) {
            this.transact(caller, baseToken, denormalize(withdrawal.amount1, IERC20(baseToken).decimals()), caller);
        }
        if (withdrawal.amount0 > 0) {
            this.transact(caller, token0, denormalize(withdrawal.amount0, IERC20(token0).decimals()), caller);
        }
    }

    function transact(address caller, address token, uint256 amount, address recipient) external onlyRouter nonReentrant {
        LiquidityDetails storage details = liquidityDetails[listingId];
        uint256 normalizedAmount = normalize(amount, IERC20(token).decimals());
        if (token == token0) {
            require(details.xLiquid >= normalizedAmount, "Insufficient Token-0 liquidity");
            details.xLiquid -= normalizedAmount;
        } else if (token == baseToken) {
            require(details.yLiquid >= normalizedAmount, "Insufficient Token-1 liquidity");
            details.yLiquid -= normalizedAmount;
        }
        IERC20(token).safeTransfer(recipient, amount);
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function claimFees(address caller, bool isX, uint256 slotIndex, uint256 /* volume */) external onlyRouter nonReentrant {
        Slot storage slot = isX ? xLiquiditySlots[listingId][slotIndex] : yLiquiditySlots[listingId][slotIndex];
        require(slot.depositor == caller, "Not depositor");
        LiquidityDetails storage details = liquidityDetails[listingId];

        (, , uint256 xVolume, uint256 yVolume) = IOMFListing(listingAddress).volumeBalances(listingId);
        uint256 tVolume = isX ? xVolume : yVolume;
        uint256 liquid = isX ? details.xLiquid : details.yLiquid;
        uint256 fees = isX ? details.xFees : details.yFees;
        uint256 allocation = slot.allocation;

        uint256 feeShare = calculateFeeShare(tVolume, slot.dVolume, liquid, allocation, fees);
        if (feeShare > 0) {
            if (isX) {
                require(details.xFees >= feeShare, "Insufficient Token-0 fees");
                details.xFees -= feeShare;
                IERC20(token0).safeTransfer(caller, denormalize(feeShare, IERC20(token0).decimals()));
            } else {
                require(details.yFees >= feeShare, "Insufficient Token-1 fees");
                details.yFees -= feeShare;
                IERC20(baseToken).safeTransfer(caller, denormalize(feeShare, IERC20(baseToken).decimals()));
            }
            slot.dVolume = tVolume; // Reset dVolume to current tVolume from listing
            emit FeesClaimed(isX, feeShare, caller);
        }
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

    function removeSlot(bool isX, uint256 slotIndex) internal {
        mapping(uint256 => Slot) storage slots = isX ? xLiquiditySlots[listingId] : yLiquiditySlots[listingId];
        uint256[] storage activeSlots = isX ? activeXLiquiditySlots[listingId] : activeYLiquiditySlots[listingId];
        address depositor = slots[slotIndex].depositor;
        slots[slotIndex] = Slot(address(0), 0, 0, 0);
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

    function calculateFeeShare(
        uint256 volume,
        uint256 dVolume,
        uint256 liquid,
        uint256 allocation,
        uint256 fees
    ) internal pure returns (uint256) {
        uint256 contributedVolume = volume > dVolume ? volume - dVolume : 0;
        uint256 feesAccrued = (contributedVolume * 5) / 10000; // 0.05% fee rate
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        uint256 feeShare = (feesAccrued * liquidityContribution) / 1e18;
        return feeShare > fees ? fees : feeShare;
    }

    function liquidityAmounts(uint256) external view returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = liquidityDetails[listingId];
        return (details.xLiquid, details.yLiquid);
    }

    function feeAmounts(uint256) external view returns (uint256 xFee, uint256 yFee) {
        LiquidityDetails memory details = liquidityDetails[listingId];
        return (details.xFees, details.yFees);
    }

    function activeXLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeXLiquiditySlots[listingId];
    }

    function activeYLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeYLiquiditySlots[listingId];
    }

    function userIndexView(address user) external view returns (uint256[] memory) {
        return userIndex[user];
    }

    function getXSlotView(uint256 index) external view returns (Slot memory) {
        return xLiquiditySlots[listingId][index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory) {
        return yLiquiditySlots[listingId][index];
    }
}