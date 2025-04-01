// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.7
// Changes:
// - Renamed tokenA to token0, tokenB to baseToken (Token-0 to Token-1).
// - Removed xVolume/yVolume, kept xLiquid/yLiquid as liquidity pools.
// - Added withdrawLiquidity with slot limits, adjusted transact/deposit.
// - Inlined IOMFLiquidity interface functions where needed.

import "./imports/SafeERC20.sol";

contract OMFLiquidityTemplate {
    using SafeERC20 for IERC20;

    address public router;
    address public listingAddress;
    uint256 public listingId;

    address public token0;    // Token-0 (listed token)
    address public baseToken; // Token-1 (reference token)

    mapping(uint256 => uint256) public xLiquid;  // Token-0 liquidity
    mapping(uint256 => uint256) public yLiquid;  // Token-1 liquidity
    mapping(uint256 => uint256) public xFees;    // Token-0 fees
    mapping(uint256 => uint256) public yFees;    // Token-1 fees

    struct Slot {
        address depositor;
        uint256 allocation; // Normalized amount contributed
        uint256 dVolume;    // Volume at deposit time (placeholder, not updated here)
        uint256 timestamp;
    }

    mapping(uint256 => mapping(uint256 => Slot)) public xLiquiditySlots;
    mapping(uint256 => mapping(uint256 => Slot)) public yLiquiditySlots;
    mapping(uint256 => uint256[]) public activeXLiquiditySlots;
    mapping(uint256 => uint256[]) public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    event LiquidityAdded(bool isX, uint256 amount);
    event FeesAdded(bool isX, uint256 amount);
    event FeesClaimed(bool isX, uint256 amount, address depositor);

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

    function addFees(address caller, bool isX, uint256 fee) external onlyRouter {
        require(fee > 0, "Invalid fee");
        address token = isX ? token0 : baseToken;
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(caller, address(this), fee);
        uint256 actualReceived = IERC20(token).balanceOf(address(this)) - preBalance;
        if (isX) xFees[listingId] += actualReceived;
        else yFees[listingId] += actualReceived;
        emit FeesAdded(isX, actualReceived);
    }

    function deposit(address caller, bool isX, uint256 amount) external onlyRouter {
        require(amount > 0, "Invalid amount");
        address token = isX ? token0 : baseToken;
        uint256 preBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(caller, address(this), amount);
        uint256 postBalance = IERC20(token).balanceOf(address(this));
        uint256 actualReceived = postBalance - preBalance;
        uint256 normalizedAmount = normalize(actualReceived, IERC20(token).decimals());

        uint256 slotIndex = isX ? activeXLiquiditySlots[listingId].length : activeYLiquiditySlots[listingId].length;
        Slot storage slot = isX ? xLiquiditySlots[listingId][slotIndex] : yLiquiditySlots[listingId][slotIndex];
        slot.depositor = caller;
        slot.allocation = normalizedAmount;
        slot.dVolume = 0; // Volume tracked in OMFListingTemplate
        slot.timestamp = block.timestamp;

        if (isX) {
            xLiquid[listingId] += normalizedAmount;
            activeXLiquiditySlots[listingId].push(slotIndex);
        } else {
            yLiquid[listingId] += normalizedAmount;
            activeYLiquiditySlots[listingId].push(slotIndex);
        }
        userIndex[caller].push(slotIndex);
        emit LiquidityAdded(isX, normalizedAmount);
    }

    function withdrawLiquidity(bool isX, uint256 slotIndex, uint256 amount) external {
        Slot storage slot = isX ? xLiquiditySlots[listingId][slotIndex] : yLiquiditySlots[listingId][slotIndex];
        require(slot.depositor == msg.sender, "Not depositor");
        uint256 normalizedAmount = normalize(amount, IERC20(isX ? token0 : baseToken).decimals());
        require(slot.allocation >= normalizedAmount, "Exceeds allocation");
        if (isX) {
            require(xLiquid[listingId] >= normalizedAmount, "Insufficient Token-0 liquidity");
            xLiquid[listingId] -= normalizedAmount;
        } else {
            require(yLiquid[listingId] >= normalizedAmount, "Insufficient Token-1 liquidity");
            yLiquid[listingId] -= normalizedAmount;
        }
        IERC20(isX ? token0 : baseToken).safeTransfer(msg.sender, amount);
        slot.allocation -= normalizedAmount;
        if (slot.allocation == 0) removeSlot(isX, slotIndex);
    }

    function transact(address caller, address token, uint256 amount, address recipient) external onlyRouter {
        uint256 normalizedAmount = normalize(amount, IERC20(token).decimals());
        if (token == token0) {
            require(xLiquid[listingId] >= normalizedAmount, "Insufficient Token-0 liquidity");
            xLiquid[listingId] -= normalizedAmount;
        } else if (token == baseToken) {
            require(yLiquid[listingId] >= normalizedAmount, "Insufficient Token-1 liquidity");
            yLiquid[listingId] -= normalizedAmount;
        }
        IERC20(token).safeTransfer(recipient, amount);
    }

    function claimFees(address caller, bool isX, uint256 volume) external onlyRouter {
        require(volume > 0, "Invalid volume");
        uint256 slotIndex = userIndex[caller].length > 0 ? userIndex[caller][0] : 0; // First slot for simplicity
        Slot storage slot = isX ? xLiquiditySlots[listingId][slotIndex] : yLiquiditySlots[listingId][slotIndex];
        require(slot.depositor == caller, "Not depositor");

        uint256 liquid = isX ? xLiquid[listingId] : yLiquid[listingId];
        uint256 fees = isX ? xFees[listingId] : yFees[listingId];
        uint256 allocation = slot.allocation;

        uint256 feeShare = calculateFeeShare(volume, slot.dVolume, liquid, allocation, fees);
        if (feeShare > 0) {
            if (isX) {
                require(xFees[listingId] >= feeShare, "Insufficient Token-0 fees");
                xFees[listingId] -= feeShare;
                IERC20(token0).safeTransfer(caller, denormalize(feeShare, IERC20(token0).decimals()));
            } else {
                require(yFees[listingId] >= feeShare, "Insufficient Token-1 fees");
                yFees[listingId] -= feeShare;
                IERC20(baseToken).safeTransfer(caller, denormalize(feeShare, IERC20(baseToken).decimals()));
            }
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
        return (xLiquid[listingId], yLiquid[listingId]);
    }

    function feeAmounts(uint256) external view returns (uint256 xFee, uint256 yFee) {
        return (xFees[listingId], yFees[listingId]);
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