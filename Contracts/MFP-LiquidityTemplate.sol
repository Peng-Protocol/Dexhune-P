// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.10

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
    uint256 public listingId;

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
        address recipient;// not used
    }

    mapping(uint256 => LiquidityDetails) public liquidityDetails;
    mapping(uint256 => mapping(uint256 => Slot)) public xLiquiditySlots;
    mapping(uint256 => mapping(uint256 => Slot)) public yLiquiditySlots;
    mapping(uint256 => uint256[]) public activeXLiquiditySlots;
    mapping(uint256 => uint256[]) public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);

    // One-time setup functions
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

    function update(address caller, UpdateType[] memory updates) external {
        require(caller == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) { // Balance update
                if (u.index == 0) details.xLiquid = u.value;
                else if (u.index == 1) details.yLiquid = u.value;
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
                if (slot.depositor == address(0) && u.addr != address(0)) {
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
                if (slot.depositor == address(0) && u.addr != address(0)) {
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

    function transact(address caller, address token, uint256 amount, address recipient) external {
        require(caller == routerAddress, "Router only");
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

    function deposit(address caller, address token, uint256 amount) external payable {
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
        uint256 index = token == tokenA ? activeXLiquiditySlots[listingId].length : activeYLiquiditySlots[listingId].length;
        updates[0] = UpdateType(token == tokenA ? 2 : 3, index, normalizedAmount, msg.sender, address(0));
        this.update(caller, updates);
    }

    function xWithdraw(uint256 amount, uint256 index) external {
        Slot storage slot = xLiquiditySlots[listingId][index];
        require(slot.depositor == msg.sender, "Not depositor");
        uint256 withdrawAmount = slot.allocation < amount ? slot.allocation : amount;

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawAmount, msg.sender, address(0));
        this.update(routerAddress, updates);

        this.transact(routerAddress, tokenA, withdrawAmount, msg.sender);
    }

    function yWithdraw(uint256 amount, uint256 index) external {
        Slot storage slot = yLiquiditySlots[listingId][index];
        require(slot.depositor == msg.sender, "Not depositor");
        uint256 withdrawAmount = slot.allocation < amount ? slot.allocation : amount;

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawAmount, msg.sender, address(0));
        this.update(routerAddress, updates);

        this.transact(routerAddress, tokenB, withdrawAmount, msg.sender);
    }

    function claimFees(address caller, uint256 liquidityIndex, bool isX, uint256 volume) external {
        require(caller == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];
        Slot storage slot = isX ? xLiquiditySlots[listingId][liquidityIndex] : yLiquiditySlots[listingId][liquidityIndex];
        require(slot.depositor == msg.sender, "Not depositor");

        uint256 liquid = isX ? details.xLiquid : details.yLiquid;
        uint256 fees = isX ? details.xFees : details.yFees;
        uint256 allocation = slot.allocation;
        uint256 dVolume = slot.dVolume;

        (uint256 feeShare, UpdateType[] memory updates) = _claimFeeShare(volume, dVolume, liquid, allocation, fees);
        if (feeShare > 0) {
            updates[0] = UpdateType(1, isX ? 0 : 1, fees - feeShare, address(0), address(0));
            updates[1] = UpdateType(isX ? 2 : 3, liquidityIndex, allocation, msg.sender, address(0));
            this.update(caller, updates);

            this.transact(caller, isX ? tokenA : tokenB, feeShare, msg.sender);
            emit FeesClaimed(listingId, liquidityIndex, isX ? feeShare : 0, isX ? 0 : feeShare);
        }
    }

    function addFees(address caller, bool isX, uint256 fee) external {
        require(caller == routerAddress, "Router only");
        UpdateType[] memory feeUpdates = new UpdateType[](1);
        feeUpdates[0] = UpdateType(1, isX ? 0 : 1, fee, address(0), address(0));
        this.update(caller, feeUpdates);
    }

    function updateLiquidity(address caller, bool isX, uint256 amount) external {
        require(caller == routerAddress, "Router only");
        LiquidityDetails storage details = liquidityDetails[listingId];
        if (isX) {
            require(details.xLiquid >= amount, "Insufficient xLiquid");
            details.xLiquid -= amount;
        } else {
            require(details.yLiquid >= amount, "Insufficient yLiquid");
            details.yLiquid -= amount;
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function transferLiquidity(uint256 liquidityIndex, address newDepositor) external {
        Slot storage xSlot = xLiquiditySlots[listingId][liquidityIndex];
        require(xSlot.depositor == msg.sender, "Not depositor");

        UpdateType[] memory updates = new UpdateType[](2);
        updates[0] = UpdateType(2, liquidityIndex, xSlot.allocation, newDepositor, address(0));
        updates[1] = UpdateType(3, liquidityIndex, xSlot.allocation, newDepositor, address(0));
        this.update(routerAddress, updates);
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

    function _claimFeeShare(
        uint256 volume,
        uint256 dVolume,
        uint256 liquid,
        uint256 allocation,
        uint256 fees
    ) private pure returns (uint256 feeShare, UpdateType[] memory updates) {
        updates = new UpdateType[](2);
        uint256 contributedVolume = volume > dVolume ? volume - dVolume : 0;
        uint256 feesAccrued = (contributedVolume * 5) / 10000;
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        feeShare = (feesAccrued * liquidityContribution) / 1e18;
        feeShare = feeShare > fees ? fees : feeShare;
        return (feeShare, updates);
    }

    // View functions
    function liquidityDetails() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) {
        LiquidityDetails memory details = liquidityDetails[listingId];
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees);
    }

    function activeXLiquiditySlots() external view returns (uint256[] memory) {
        return activeXLiquiditySlots[listingId];
    }

    function activeYLiquiditySlots() external view returns (uint256[] memory) {
        return activeYLiquiditySlots[listingId];
    }

    function userIndex(address user) external view returns (uint256[] memory) {
        return userIndex[user];
    }

    function getXSlot(uint256 index) external view returns (Slot memory) {
        return xLiquiditySlots[listingId][index];
    }

    function getYSlot(uint256 index) external view returns (Slot memory) {
        return yLiquiditySlots[listingId][index];
    }
}