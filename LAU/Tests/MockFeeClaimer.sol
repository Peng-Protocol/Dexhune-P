/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
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
        require(lauAddress != address(0), "LAU address not set");
        uint256 balance = ITERC20(lauAddress).balanceOf(msg.sender);
        uint256 fee = (balance * 1) / 10000; // 0.01%
        require(fee > 0, "Fee too low");
        require(ITERC20(lauAddress).transferFrom(msg.sender, lauAddress, fee), "TransferFrom failed");
        return true;
    }
}