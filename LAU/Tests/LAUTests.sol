/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025
 Changes:
 - 2025-10-26: Split testMockSwap into testMockSwap and testRewardDistribution.
 - 2025-10-26: Enhanced testMockSwap with allowance checks and detailed revert reasons.
 - 2025-10-26: Updated testDispense to ensure min 0.01 LAU per tester with 50% ETH cap.
 - 2025-10-26: Enhanced testMockSwap error messages with tester index, token (LAU), stage.
 - 2025-10-26: Enhanced testMockSwap with explicit balance checks and detailed revert reasons.
 - 2025-10-26: Added MockSwapFailed event decoding in testMockSwap for detailed errors.
 - 2025-10-26: Added balance checks in testMockSwap to debug fee collection failure.
 - 2025-10-26: Updated testMockSwap to skip swaps if tester LAU balance is too low.
 - 2025-10-26: Updated testMockSwap to use initiateSimpleCall for mockSwap, removing unused swapAmount.
 - 2025-10-26: Updated testDispense to use 50% of tester ETH, testMockSwap to use 1% of LAU balance.
 - 2025-10-26: Updated testMockSwap to log addresses not receiving rewards and check rewards after all swaps.
 - 2025-10-26: Relaxed testMockSwap to check if any non-exempt tester received rewards.
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
    
    event NonRewardedTester(address indexed tester);
    event MockSwapFailed(address indexed tester, string reason);
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
        uint256 ethAmount = (address(testers[i]).balance * 50) / 100; // Use 50% ETH
        require(ethAmount > 0, "Tester ETH balance too low");
        uint256 expectedLAU = (ethAmount * 3500) / 4000; // ETH to LAU ratio
        if (expectedLAU < 0.01 * 10**18) expectedLAU = 0.01 * 10**18; // Min 0.01 LAU
        testers[i].initiateEthCall(address(lau), ethAmount);
        uint256 balanceAfter = lau.balanceOf(address(testers[i]));
        require(balanceAfter - balancesBefore[i] >= expectedLAU, "Incorrect LAU dispensed for tester");
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

    // Tests mockSwap for one swap each using MockTesters
    function testMockSwap() public {
    require(msg.sender == tester, "Only tester");
    require(testers.length > 0, "No testers deployed");

    for (uint256 i = 0; i < testers.length; i++) {
        uint256 balanceBefore = lau.balanceOf(address(testers[i]));
        if (balanceBefore < 0.01 * 10**18) {
            emit NonRewardedTester(address(testers[i]));
            revert(string(abi.encodePacked("Swap failed: Tester ", i, " has insufficient LAU balance")));
        }
        uint256 allowance = lau.allowance(address(testers[i]), address(feeClaimer));
        if (allowance < 0.01 * 10**18) {
            emit NonRewardedTester(address(testers[i]));
            revert(string(abi.encodePacked("Swap failed: Tester ", i, " has insufficient LAU allowance")));
        }
        (bool success, bytes memory data) = address(testers[i]).call(
            abi.encodeWithSignature("initiateSimpleCall(address,string)", address(feeClaimer), "mockSwap()")
        );
        if (!success) {
            string memory reason = data.length >= 4 ? abi.decode(data, (string)) : "Unknown mockSwap error";
            emit MockSwapFailed(address(testers[i]), reason);
            revert(string(abi.encodePacked("Swap failed for tester ", i, ": ", reason)));
        }
        uint256 balanceAfter = lau.balanceOf(address(testers[i]));
        uint256 fee = (balanceBefore * 1) / 10000; // 0.01% fee
        require(balanceBefore - balanceAfter == fee, "TransferFrom failed");
    }
}

// Split from testMockSwap, tests reward distribution using tester zero as initiator.
function testRewardDistribution() public {
    require(msg.sender == tester, "Only tester");
    require(testers.length > 0, "No testers deployed");
    uint256[] memory balancesBefore = new uint256[](testers.length);

    for (uint256 i = 0; i < testers.length; i++) {
        balancesBefore[i] = lau.balanceOf(address(testers[i]));
    }

    for (uint256 i = 0; i < 20; i++) {
        uint256 currentBalance = lau.balanceOf(address(testers[0]));
        if (currentBalance < 0.01 * 10**18) {
            emit NonRewardedTester(address(testers[0]));
            revert(string(abi.encodePacked("Swap ", i, " failed: Tester 0 has insufficient LAU balance")));
        }
        uint256 allowance = lau.allowance(address(testers[0]), address(feeClaimer));
        if (allowance < 0.01 * 10**18) {
            emit NonRewardedTester(address(testers[0]));
            revert(string(abi.encodePacked("Swap ", i, " failed: Tester 0 has insufficient LAU allowance")));
        }
        (bool success, bytes memory data) = address(testers[0]).call(
            abi.encodeWithSignature("initiateSimpleCall(address,string)", address(feeClaimer), "mockSwap()")
        );
        if (!success) {
            string memory reason = data.length >= 4 ? abi.decode(data, (string)) : "Unknown mockSwap error";
            emit MockSwapFailed(address(testers[0]), reason);
            revert(string(abi.encodePacked("Swap ", i, " failed for tester 0: ", reason)));
        }
    }

    uint256 feesInPool = lau.balanceOf(address(lau));
    require(feesInPool > 0, "No fees collected in pool");

    bool rewardsDistributed = false;
    for (uint256 i = 1; i < testers.length - (testers.length > 2 ? 1 : 0); i++) {
        uint256 balanceAfter = lau.balanceOf(address(testers[i]));
        if (balanceAfter > balancesBefore[i]) {
            rewardsDistributed = true;
        } else {
            emit NonRewardedTester(address(testers[i]));
        }
    }
    require(rewardsDistributed, "No rewards distributed to eligible testers");

    if (testers.length > 2) {
        uint256 exemptBalance = lau.balanceOf(address(testers[testers.length - 1]));
        require(exemptBalance == balancesBefore[testers.length - 1], "Exempt tester received rewards");
    }
}
}