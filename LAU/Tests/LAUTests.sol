/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-19: Rewrote for Remix compatibility, used address(this) for balance/allowance checks, merged testMockSwap and testRewards with corrected assertions.
 - 2025-10-19: Created LAUTests.sol for LinkGold testing.
*/

pragma solidity ^0.8.2;

import "../LinkGold.sol";
import "./MockFeeClaimer.sol";
import "./MockOracleETH.sol";
import "./MockOracleXAU.sol";

contract LAUTests {
    LinkGold public lau;
    MockFeeClaimer public feeClaimer;
    MockOracleETH public oracleETH;
    MockOracleXAU public oracleXAU;
    address public tester;
    uint256 constant ETH_AMOUNT = 1 ether;
    uint256 constant VERY_BIG_NUMBER = 1e36;

    constructor() {
        lau = new LinkGold();
        oracleETH = new MockOracleETH();
        oracleXAU = new MockOracleXAU();
        feeClaimer = new MockFeeClaimer();
        tester = msg.sender;

        address[2] memory oracles = [address(oracleXAU), address(oracleETH)];
        lau.setOracleAddresses(oracles);
        lau.setFeeClaimer(address(feeClaimer));
        feeClaimer.setLAU(address(lau));
    }

    function testDispense() public payable {
        require(msg.sender == tester, "Only tester");
        uint256 balanceBefore = lau.balanceOf(address(this));
        uint256 expectedLAU = (ETH_AMOUNT * 3500) / 4000;

        for (uint256 i = 0; i < 3; i++) {
            lau.dispense{value: ETH_AMOUNT}();
        }
        uint256 balanceAfter = lau.balanceOf(address(this));
        require(balanceAfter - balanceBefore == expectedLAU * 3, "Incorrect LAU dispensed");
    }

    function testApprove() public {
        require(msg.sender == tester, "Only tester");
        lau.approve(address(feeClaimer), VERY_BIG_NUMBER);
        require(lau.allowance(address(this), address(feeClaimer)) == VERY_BIG_NUMBER, "Approval failed");
    }

    function testMockSwap() public {
        require(msg.sender == tester, "Only tester");
        uint256 balanceBefore = lau.balanceOf(address(this));
        uint256 linearDeduction = (balanceBefore * 1 * 30) / 10000;

        for (uint256 i = 0; i < 30; i++) {
            feeClaimer.mockSwap();
        }

        uint256 balanceAfter = lau.balanceOf(address(this));
        uint256 feesInPool = lau.balanceOf(address(lau));
        require(feesInPool > 0, "Fees were not collected");
        require(balanceAfter > balanceBefore - linearDeduction, "Rewards not distributed or deduction wrong");
    }
}