// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

// Version: 0.0.3

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

contract MFPLiquidityTemplate is Ownable {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public tokenA;
    address public tokenB;
    uint8 public tokenADecimals;
    uint8 public tokenBDecimals;
    mapping(uint256 => LiquidityDetails) public liquidityDetails; // listingId -> details (18 decimals)
    mapping(uint256 => mapping(uint256 => XSlot)) public xLiquiditySlots; // listingId -> index -> slot
    mapping(uint256 => mapping(uint256 => YSlot)) public yLiquiditySlots; // listingId -> index -> slot
    mapping(uint256 => uint256) public liquidityIndexCount; // listingId -> next index

    struct LiquidityDetails {
        uint256 xLiquidity; // Token-0 liquidity (18 decimals)
        uint256 yLiquidity; // Token-1 liquidity (18 decimals)
        uint256 xFees;      // Token-0 fees (18 decimals)
        uint256 yFees;      // Token-1 fees (18 decimals)
    }
    struct XSlot {
        address depositor;
        uint256 ratio;      // Share of fees (18 decimals)
        uint256 allocation; // Deposited amount (18 decimals)
        uint256 slotIndex;
        uint256 listingId;
    }
    struct YSlot {
        address depositor;
        uint256 ratio;      // Share of fees (18 decimals)
        uint256 allocation; // Deposited amount (18 decimals)
        uint256 slotIndex;
        uint256 listingId;
    }
    struct UpdateType {
        uint8 updateType;   // 0 = balance update, 1 = fee update, 2 = x-slot, 3 = y-slot, 4 = transfer
        uint256 index;      // 0 = x, 1 = y for balances/fees; slot index for slots
        uint256 value;      // Amount or new ratio (18 decimals)
        address addr;       // Depositor or new depositor
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    event LiquidityAdded(uint256 listingId, uint256 index, bool isX, uint256 amount);
    event LiquidityRemoved(uint256 listingId, uint256 index, bool isX, uint256 amount);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);

    constructor() {
        _transferOwnership(msg.sender); // Owner = MFP-Agent
    }

    function setRouter(address _router) external onlyOwner {
        routerAddress = _router; // Set by MFP-Agent post-deployment
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
            if (u.updateType == 0) { // Update liquidity balances
                if (u.index == 0) {
                    details.xLiquidity = u.value;
                } else if (u.index == 1) {
                    details.yLiquidity = u.value;
                }
            } else if (u.updateType == 1) { // Update fees
                if (u.index == 0) {
                    details.xFees = u.value;
                } else if (u.index == 1) {
                    details.yFees = u.value;
                }
                emit FeesUpdated(listingId, details.xFees, details.yFees);
            } else if (u.updateType == 2) { // Update X liquidity slot
                XSlot storage slot = xLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0)) { // New slot
                    slot.depositor = u.addr;
                    slot.ratio = 1e18; // Initial full share, adjusted later if needed
                    slot.allocation = u.value;
                    slot.slotIndex = u.index;
                    slot.listingId = listingId;
                    details.xLiquidity += u.value;
                    emit LiquidityAdded(listingId, u.index, true, u.value);
                } else { // Update existing slot
                    slot.allocation = u.value;
                    if (u.value == 0) {
                        details.xLiquidity -= slot.allocation;
                        emit LiquidityRemoved(listingId, u.index, true, slot.allocation);
                    }
                }
            } else if (u.updateType == 3) { // Update Y liquidity slot
                YSlot storage slot = yLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0)) { // New slot
                    slot.depositor = u.addr;
                    slot.ratio = 1e18; // Initial full share
                    slot.allocation = u.value;
                    slot.slotIndex = u.index;
                    slot.listingId = listingId;
                    details.yLiquidity += u.value;
                    emit LiquidityAdded(listingId, u.index, false, u.value);
                } else { // Update existing slot
                    slot.allocation = u.value;
                    if (u.value == 0) {
                        details.yLiquidity -= slot.allocation;
                        emit LiquidityRemoved(listingId, u.index, false, slot.allocation);
                    }
                }
            } else if (u.updateType == 4) { // Transfer liquidity ownership
                XSlot storage xSlot = xLiquiditySlots[listingId][u.index];
                YSlot storage ySlot = yLiquiditySlots[listingId][u.index];
                require(xSlot.depositor != address(0), "Slot not initialized");
                xSlot.depositor = u.addr;
                ySlot.depositor = u.addr;
            }
        }
    }

    function transact(uint256 listingId, address token, uint256 amount, address recipient) external payable {
        require(msg.sender == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];
        uint256 nativeAmount = denormalize(amount, token == tokenA ? tokenADecimals : tokenBDecimals);

        if (token == tokenA) {
            require(details.xLiquidity >= amount, "Insufficient xLiquidity");
            details.xLiquidity -= amount;
            if (tokenA == address(0)) {
                (bool success, ) = recipient.call{value: nativeAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(recipient, nativeAmount);
            }
        } else if (token == tokenB) {
            require(details.yLiquidity >= amount, "Insufficient yLiquidity");
            details.yLiquidity -= amount;
            if (tokenB == address(0)) {
                (bool success, ) = recipient.call{value: nativeAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(recipient, nativeAmount);
            }
        } else {
            revert("Invalid token");
        }
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