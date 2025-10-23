/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-23: Created MockTester with initiateEthCall and initiateNonEthCall for testing.
*/

pragma solidity ^0.8.2;

// Interface for LinkGold contract
interface ILinkGold {
    function dispense() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

// Interface for MockFeeClaimer contract
interface IMockFeeClaimer {
    function mockSwap() external returns (bool);
}

contract MockTester {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    receive() external payable {}

    // Initiates payable call to target contract (e.g., dispense)
    function initiateEthCall(address target, uint256 ethAmount) external payable {
        require(msg.sender == owner, "Not owner");
        require(ethAmount <= address(this).balance, "Insufficient ETH");
        (bool success, ) = target.call{value: ethAmount}(abi.encodeWithSignature("dispense()"));
        require(success, "ETH call failed");
    }

    // Initiates non-ETH call to target contract (e.g., approve, mockSwap)
    function initiateNonEthCall(address target, string memory signature, address param1, uint256 param2) external {
        require(msg.sender == owner, "Not owner");
        (bool success, ) = target.call(abi.encodeWithSignature(signature, param1, param2));
        require(success, "Non-ETH call failed");
    }
}