/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-26: Added MockSwapFailed event with reason in mockSwap for better error reporting.
 - 2025-10-19: Created MockFeeClaimer with mockSwap and setLAU functions.
 - 2025-10-19: Updated mockSwap to use transferFrom instead of transfer.
*/

pragma solidity ^0.8.2;

interface ITERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockFeeClaimer {
    address public owner;
    address public lauAddress;

    event MockSwapFailed(address indexed caller, string reason);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    // Sets LAU contract address
    function setLAU(address _lauAddress) external onlyOwner {
        require(_lauAddress != address(0), "Invalid LAU address");
        lauAddress = _lauAddress;
    }

    // Deducts 0.01% of caller's LAU balance and transfers to LAU contract
    function mockSwap() external returns (bool) {
        if (lauAddress == address(0)) {
            emit MockSwapFailed(msg.sender, "LAU address not set");
            return false;
        }
        uint256 balance = ITERC20(lauAddress).balanceOf(msg.sender);
        uint256 fee = (balance * 1) / 10000; // 0.01%
        if (fee == 0) {
            emit MockSwapFailed(msg.sender, "Fee too low");
            return false;
        }
        if (!ITERC20(lauAddress).transferFrom(msg.sender, lauAddress, fee)) {
            emit MockSwapFailed(msg.sender, "TransferFrom failed");
            return false;
        }
        return true;
    }
}