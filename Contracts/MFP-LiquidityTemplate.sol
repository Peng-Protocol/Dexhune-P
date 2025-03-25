// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

// Version: 0.0.2

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

contract MFPLiquidityTemplate is Ownable {
    using SafeERC20 for IERC20;

    // State Variables
    address public routerAddress;
    address public listingAddress;
    address public tokenA; // Token-0 address (ETH if address(0))
    address public tokenB; // Token-1 address (ETH if address(0))
    uint8 public tokenADecimals; // Decimals for tokenA (18 for ETH)
    uint8 public tokenBDecimals; // Decimals for tokenB (18 for ETH)
    mapping(uint256 => address) public listings; // listingId -> MFP-Listing address
    mapping(uint256 => LiquidityDetails) public liquidityDetails; // Liquidity and fees (18 decimals)
    mapping(uint256 => mapping(uint256 => XLiquiditySlot)) public xLiquiditySlots; // Token-0 deposits (18 decimals)
    mapping(uint256 => mapping(uint256 => YLiquiditySlot)) public yLiquiditySlots; // Token-1 deposits (18 decimals)
    mapping(uint256 => uint256[]) public activeXLiquiditySlots; // Active Token-0 slots
    mapping(uint256 => uint256[]) public activeYLiquiditySlots; // Active Token-1 slots
    mapping(uint256 => uint256) public liquidityIndexCount; // Next slot index
    mapping(address => uint256[]) public userIndex; // User’s slot indexes

    // Structs
    struct LiquidityDetails {
        uint256 xLiquid; // Token-0 liquidity (18 decimals)
        uint256 yLiquid; // Token-1 liquidity (18 decimals)
        uint256 xFees; // Accumulated Token-0 fees (18 decimals)
        uint256 yFees; // Accumulated Token-1 fees (18 decimals)
    }
    struct XLiquiditySlot {
        address depositor;
        uint256 xRatio; // Ratio for fee distribution (18 decimals)
        uint256 xAllocation; // Current Token-0 amount (18 decimals)
        uint256 dVolume; // Volume for fee calculation (18 decimals)
        uint256 index;
    }
    struct YLiquiditySlot {
        address depositor;
        uint256 yRatio; // Ratio for fee distribution (18 decimals)
        uint256 yAllocation; // Current Token-1 amount (18 decimals)
        uint256 dVolume; // Volume for fee calculation (18 decimals)
        uint256 index;
    }
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value; // 18 decimals
        address addr;
        address recipient;
        uint256 maxPrice; // 18 decimals
        uint256 minPrice; // 18 decimals
    }

    // Events
    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);
    event SlotUpdated(uint256 listingId, uint256 index, bool isX, uint256 allocation);

    constructor() {
        _transferOwnership(msg.sender); // Owner = MFP-Agent
    }

    function setRouter(address _router) external {
        routerAddress = _router; // Set by MFP-Agent
    }

    function setListingAddress(uint256 listingId, address _listing) external {
        listingAddress = _listing;
        listings[listingId] = _listing; // Set by MFP-Agent
    }

    function setTokens(address _tokenA, address _tokenB) external onlyOwner {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        tokenA = _tokenA;
        tokenB = _tokenB;
        tokenADecimals = _tokenA == address(0) ? 18 : IERC20(_tokenA).decimals();
        tokenBDecimals = _tokenB == address(0) ? 18 : IERC20(_tokenB).decimals();
    }

    function update(uint256 listingId, UpdateType[] memory updates) external {
        require(msg.sender == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];

        for (uint256 i = 0; i < updates.length && i < 100; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Update liquidity
                if (u.index == 0) {
                    details.xLiquid = u.value;
                    emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
                } else if (u.index == 1) {
                    details.yLiquid = u.value;
                    emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
                }
            } else if (u.updateType == 1) { // Update fees
                if (u.index == 0) {
                    details.xFees = u.value; // Replace += with = to match router logic
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                } else if (u.index == 1) {
                    details.yFees = u.value; // Replace += with = to match router logic
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                }
            } else if (u.updateType == 2) { // Update xSlot
                XLiquiditySlot storage slot = xLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0) && u.value > 0) {
                    slot.depositor = u.addr;
                    slot.index = u.index;
                    userIndex[u.addr].push(u.index);
                }
                slot.xAllocation = u.value;
                if (u.value > 0) {
                    uint256 totalX = details.xLiquid;
                    slot.xRatio = totalX > 0 ? (slot.xAllocation * 1e18) / totalX : 1e18;
                    if (!isActive(activeXLiquiditySlots[listingId], u.index)) {
                        activeXLiquiditySlots[listingId].push(u.index);
                    }
                } else if (slot.xAllocation == 0) { // Prune when withdrawn
                    removeActiveSlot(activeXLiquiditySlots[listingId], u.index);
                    removeUserIndex(slot.depositor, u.index);
                }
                emit SlotUpdated(listingId, u.index, true, u.value);
            } else if (u.updateType == 3) { // Update ySlot
                YLiquiditySlot storage slot = yLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0) && u.value > 0) {
                    slot.depositor = u.addr;
                    slot.index = u.index;
                    userIndex[u.addr].push(u.index);
                }
                slot.yAllocation = u.value;
                if (u.value > 0) {
                    uint256 totalY = details.yLiquid;
                    slot.yRatio = totalY > 0 ? (slot.yAllocation * 1e18) / totalY : 1e18;
                    if (!isActive(activeYLiquiditySlots[listingId], u.index)) {
                        activeYLiquiditySlots[listingId].push(u.index);
                    }
                } else if (slot.yAllocation == 0) { // Prune when withdrawn
                    removeActiveSlot(activeYLiquiditySlots[listingId], u.index);
                    removeUserIndex(slot.depositor, u.index);
                }
                emit SlotUpdated(listingId, u.index, false, u.value);
            } else if (u.updateType == 4) { // Update userIndex (transfer)
                XLiquiditySlot storage xSlot = xLiquiditySlots[listingId][u.index];
                YLiquiditySlot storage ySlot = yLiquiditySlots[listingId][u.index];
                if (xSlot.depositor != address(0)) {
                    removeUserIndex(xSlot.depositor, u.index);
                    xSlot.depositor = u.addr;
                    userIndex[u.addr].push(u.index);
                } else if (ySlot.depositor != address(0)) {
                    removeUserIndex(ySlot.depositor, u.index);
                    ySlot.depositor = u.addr;
                    userIndex[u.addr].push(u.index);
                }
            }
        }
    }

    function transact(uint256 listingId, address token, uint256 amount, address recipient) external payable {
        require(msg.sender == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];
        uint256 nativeAmount;

        if (token == tokenA) {
            nativeAmount = denormalize(amount, tokenADecimals);
            require(details.xLiquid >= amount, "Insufficient xLiquid");
            details.xLiquid -= amount;
            if (tokenA == address(0)) {
                (bool success, ) = recipient.call{value: nativeAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(recipient, nativeAmount);
            }
            emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
        } else if (token == tokenB) {
            nativeAmount = denormalize(amount, tokenBDecimals);
            require(details.yLiquid >= amount, "Insufficient yLiquid");
            details.yLiquid -= amount;
            if (tokenB == address(0)) {
                (bool success, ) = recipient.call{value: nativeAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(recipient, nativeAmount);
            }
            emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
        } else {
            revert("Invalid token");
        }
    }

    // Helper functions
    function removeActiveSlot(uint256[] storage slots, uint256 index) internal {
        for (uint256 i = 0; i < slots.length; i++) {
            if (slots[i] == index) {
                slots[i] = slots[slots.length - 1];
                slots.pop();
                break;
            }
        }
    }

    function removeUserIndex(address user, uint256 index) internal {
        uint256[] storage indexes = userIndex[user];
        for (uint256 i = 0; i < indexes.length; i++) {
            if (indexes[i] == index) {
                indexes[i] = indexes[indexes.length - 1];
                indexes.pop();
                break;
            }
        }
    }

    function isActive(uint256[] storage slots, uint256 index) internal view returns (bool) {
        for (uint256 i = 0; i < slots.length; i++) {
            if (slots[i] == index) return true;
        }
        return false;
    }

    // Decimal normalization helpers
    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / (10 ** (18 - decimals));
        return amount * (10 ** (decimals - 18));
    }
}

// Assume IERC20 includes decimals() function
interface IERC20 {
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}