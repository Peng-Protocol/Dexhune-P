/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-23: Fixed testDispense to calculate expectedLAU per ethAmount in loop, added reward exception for last MockTester if >2 testers, updated testMockSwap to verify exempt address receives no rewards.
 - 2025-10-23: Removed payable modifier from testDispense, as MockTesters use their own ETH.
 - 2025-10-23: Added MockTester deployment via initiateTesters, updated testDispense, testApprove, testMockSwap to use testers, added reward validation.
 - 2025-10-19: Rewrote for Remix compatibility, used address(this) for balance/allowance checks, merged testMockSwap and testRewards with corrected assertions.
 - 2025-10-19: Created LAUTests.sol for LinkGold testing.
*/

pragma solidity ^0.8.2;

import "../LinkGold.sol";
import "./MockFeeClaimer.sol";
import "./MockOracleETH.sol";
import "./MockOracleXAU.sol";
import "./MockTester.sol";

contract LAUTests {
    LinkGold public lau;
    MockFeeClaimer public feeClaimer;
    MockOracleETH public oracleETH;
    MockOracleXAU public oracleXAU;
    MockTester[] public testers;
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

    // Deploys and funds MockTester contracts, adds last tester as reward exception if >2 testers
    function initiateTesters(uint256 numTesters) public payable {
        require(msg.sender == tester, "Only tester");
        require(numTesters > 0, "Invalid tester count");
        uint256 ethPerTester = msg.value / numTesters;
        for (uint256 i = 0; i < numTesters; i++) {
            MockTester newTester = new MockTester(address(this));
            (bool success, ) = address(newTester).call{value: ethPerTester}("");
            require(success, "ETH transfer failed");
            testers.push(newTester);
        }
        if (numTesters > 2) {
            address[] memory exceptions = new address[](1);
            exceptions[0] = address(testers[numTesters - 1]);
            lau.addRewardExceptions(exceptions);
        }
    }

    // Tests dispense using MockTesters
    function testDispense() public {
        require(msg.sender == tester, "Only tester");
        require(testers.length > 0, "No testers deployed");
        uint256[] memory balancesBefore = new uint256[](testers.length);

        for (uint256 i = 0; i < testers.length; i++) {
            balancesBefore[i] = lau.balanceOf(address(testers[i]));
            uint256 ethAmount = (address(testers[i]).balance * 90) / 100;
            uint256 expectedLAU = (ethAmount * 3500) / 4000;
            testers[i].initiateEthCall(address(lau), ethAmount);
            uint256 balanceAfter = lau.balanceOf(address(testers[i]));
            require(balanceAfter - balancesBefore[i] == expectedLAU, "Incorrect LAU dispensed");
        }
    }

    // Tests approve using MockTesters
    function testApprove() public {
        require(msg.sender == tester, "Only tester");
        require(testers.length > 0, "No testers deployed");
        for (uint256 i = 0; i < testers.length; i++) {
            testers[i].initiateNonEthCall(address(lau), "approve(address,uint256)", address(feeClaimer), VERY_BIG_NUMBER);
            require(lau.allowance(address(testers[i]), address(feeClaimer)) == VERY_BIG_NUMBER, "Approval failed");
        }
    }

    // Tests mockSwap and reward distribution using MockTesters
    function testMockSwap() public {
        require(msg.sender == tester, "Only tester");
        require(testers.length > 0, "No testers deployed");
        uint256[] memory balancesBefore = new uint256[](testers.length);

        for (uint256 i = 0; i < testers.length; i++) {
            balancesBefore[i] = lau.balanceOf(address(testers[i]));
            testers[i].initiateNonEthCall(address(feeClaimer), "mockSwap()", address(0), 0);
        }

        for (uint256 i = 0; i < 19; i++) {
            testers[0].initiateNonEthCall(address(feeClaimer), "mockSwap()", address(0), 0);
        }

        uint256 feesInPool = lau.balanceOf(address(lau));
        require(feesInPool > 0, "Fees were not collected");

        bool rewardsDistributed = true;
        for (uint256 i = 1; i < testers.length - (testers.length > 2 ? 1 : 0); i++) {
            uint256 balanceAfter = lau.balanceOf(address(testers[i]));
            if (balanceAfter <= balancesBefore[i]) {
                rewardsDistributed = false;
                break;
            }
        }
        require(rewardsDistributed, "Rewards not distributed to testers");

        if (testers.length > 2) {
            uint256 exemptBalance = lau.balanceOf(address(testers[testers.length - 1]));
            require(exemptBalance == balancesBefore[testers.length - 1], "Exempt tester received rewards");
        }
    }
}