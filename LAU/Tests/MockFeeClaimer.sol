/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-19: Created MockFeeClaimer with mockSwap and setLAU functions for testing LAU contract.
*/

pragma solidity ^0.8.2;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
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

    // Sets LAU contract address
    function setLAU(address _lauAddress) external onlyOwner {
        require(_lauAddress != address(0), "Invalid LAU address");
        lauAddress = _lauAddress;
    }

    // Deducts 0.01% of caller's LAU balance and transfers to LAU contract
    function mockSwap() external returns (bool) {
        require(lauAddress != address(0), "LAU address not set");
        uint256 balance = IERC20(lauAddress).balanceOf(msg.sender);
        uint256 fee = (balance * 1) / 10000; // 0.01%
        require(fee > 0, "Fee too low");
        require(IERC20(lauAddress).transfer(lauAddress, fee), "Transfer failed");
        return true;
    }
}