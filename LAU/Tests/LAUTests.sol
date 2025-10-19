/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-19: Created LAUTests.sol to test LinkGold contract functionality per LAUTests.txt.
*/

pragma solidity ^0.8.2;

import "./LAU/LinkGold.sol";
import "./LAU/Tests/MockFeeClaimer.sol";
import "./LAU/Tests/MockOracleETH.sol";
import "./LAU/Tests/MockOracleXAU.sol";

contract LAUTests {
    LinkGold lau;
    MockFeeClaimer feeClaimer;
    MockOracleETH oracleETH;
    MockOracleXAU oracleXAU;
    address[3] accounts;
    uint256 constant ETH_AMOUNT = 1 ether;
    uint256 constant VERY_BIG_NUMBER = 1e36;

    // Sets up contracts and accounts
    function setUp() public {
        lau = new LinkGold();
        oracleETH = new MockOracleETH();
        oracleXAU = new MockOracleXAU();
        feeClaimer = new MockFeeClaimer();

        // Set oracle addresses in LAU
        address[2] memory oracles = [address(oracleXAU), address(oracleETH)];
        lau.setOracleAddresses(oracles);

        // Set feeClaimer and LAU addresses
        lau.setFeeClaimer(address(feeClaimer));
        feeClaimer.setLAU(address(lau));

        // Create 3 accounts with 5 ETH each
        for (uint256 i = 0; i < 3; i++) {
            accounts[i] = address(uint160(uint(keccak256(abi.encode(i + 1)))));
            vm.deal(accounts[i], 5 ether);
        }
    }

    // Tests dispensing, approvals, swaps, and reward distribution
    function testLAUFlow() public {
        setUp();

        // Expected LAU amount: (1 ETH * (3500e8 / 4000e8)) = 0.875e18 LAU
        uint256 expectedLAU = (ETH_AMOUNT * 3500 * 1e8) / (4000 * 1e8) * 1e10;

        // Each account dispenses 1 ETH
        for (uint256 i = 0; i < 3; i++) {
            uint256 balanceBefore = lau.balanceOf(accounts[i]);
            vm.prank(accounts[i]);
            lau.dispense{value: ETH_AMOUNT}();
            uint256 balanceAfter = lau.balanceOf(accounts[i]);
            assertEq(balanceAfter - balanceBefore, expectedLAU, "Incorrect LAU dispensed");
        }

        // Each account approves mockFeeClaimer
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(accounts[i]);
            lau.approve(address(feeClaimer), VERY_BIG_NUMBER);
            assertEq(lau.allowance(accounts[i], address(feeClaimer)), VERY_BIG_NUMBER, "Approval failed");
        }

        // Each account calls mockSwap 10 times
        uint256[] memory balancesBefore = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            balancesBefore[i] = lau.balanceOf(accounts[i]);
            vm.startPrank(accounts[i]);
            for (uint256 j = 0; j < 10; j++) {
                feeClaimer.mockSwap();
            }
            vm.stopPrank();
        }

        // Check deductions and contract balance
        uint256 contractBalance = lau.balanceOf(address(lau));
        for (uint256 i = 0; i < 3; i++) {
            uint256 balanceAfter = lau.balanceOf(accounts[i]);
            uint256 expectedDeduction = (balancesBefore[i] * 1 * 10) / 10000; // 0.01% per swap * 10
            assertEq(balancesBefore[i] - balanceAfter, expectedDeduction, "Incorrect deduction");
            assertGt(contractBalance, 0, "No fees collected");
        }

        // Check reward distribution (proportional to holdings)
        uint256 totalDistributed;
        for (uint256 i = 0; i < 3; i++) {
            uint256 balanceAfter = lau.balanceOf(accounts[i]);
            uint256 received = balanceAfter - (balancesBefore[i] - ((balancesBefore[i] * 1 * 10) / 10000));
            totalDistributed += received;
            assertApproxEqRel(received, (contractBalance * balancesBefore[i]) / (3 * expectedLAU), 1e16, "Incorrect reward proportion");
        }
        assertGt(totalDistributed, 0, "No rewards distributed");
    }
}