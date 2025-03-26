// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.5

import "./imports/SafeERC20.sol";

interface IMFPListing {
        function volumeBalances(uint256 listingId) external view returns (
            uint256 xBalance,
            uint256 yBalance,
            uint256 xVolume,
            uint256 yVolume
        );
    }

contract MFPLiquidityTemplate {
    using SafeERC20 for IERC20;

    address public routerAddress;
    address public listingAddress;
    address public tokenA;
    address public tokenB;

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
    mapping(uint256 => LiquidityDetails) public liquidityDetails;
    mapping(uint256 => mapping(uint256 => Slot)) public xLiquiditySlots;
    mapping(uint256 => mapping(uint256 => Slot)) public yLiquiditySlots;
    mapping(uint256 => uint256[]) public activeXLiquiditySlots;
    mapping(uint256 => uint256[]) public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;    // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value;    // amount or allocation (normalized)
        address addr;     // depositor
        address recipient;// not used
    }

    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);

    function setRouter(address _routerAddress) external {
        require(routerAddress == address(0), "Router already set");
        routerAddress = _routerAddress;
    }

    function setListingAddress(address _listingAddress) external {
        require(msg.sender == routerAddress, "Router only");
        require(listingAddress == address(0), "Listing already set");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(msg.sender == routerAddress, "Router only");
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function update(uint256 listingId, UpdateType[] memory updates) external {
        require(msg.sender == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) {
                    details.xLiquid = u.value;
                } else if (u.index == 1) {
                    details.yLiquid = u.value;
                }
            } else if (u.updateType == 1) { // Fee update
                if (u.index == 0) {
                    details.xFees += u.value;
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                } else if (u.index == 1) {
                    details.yFees += u.value;
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                }
            } else if (u.updateType == 2) { // xSlot update
                Slot storage slot = xLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    activeXLiquiditySlots[listingId].push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dVolume = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                (, , uint256 xVolume, ) = IMFPListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = xVolume;
                details.xLiquid += u.value;
            } else if (u.updateType == 3) { // ySlot update
                Slot storage slot = yLiquiditySlots[listingId][u.index];
                if (slot.depositor == address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    activeYLiquiditySlots[listingId].push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dVolume = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                (, , , uint256 yVolume) = IMFPListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = yVolume;
                details.yLiquid += u.value;
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function transact(uint256 listingId, address token, uint256 amount, address recipient) external {
        require(msg.sender == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];
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

} 