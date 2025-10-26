# Running LAU Tests in Remix

## Prerequisites
- Ensure `LinkGold.sol`, `MockFeeClaimer.sol`, `MockOracleETH.sol`, `MockOracleXAU.sol`, `MockTester.sol`, and `LAUTests.sol` are in your Remix workspace.
- Place `LinkGold.sol` in `./LAU`.
- Place mock contracts and `LAUTests.sol` in `./LAU/Tests`.

## Steps
1. Open Remix[](https://remix.ethereum.org).
2. Upload all contracts to the specified directories.
3. In the "Solidity Compiler" tab, select `^0.8.2` and compile all contracts.
4. In the "Deploy & Run Transactions" tab, select the Remix VM.
5. Ensure sufficient ETH balance (100 ETH default).
6. Deploy `LAUTests` using the default account.
7. Call `initiateTesters` with 10 ETH and specify number of testers (e.g., 5). Last tester is reward-exempt if >2 testers.
   - **Objective**: Deploys `MockTester` contracts, each funded with equal ETH (e.g., 2 ETH for 5 testers). Sets the last tester as reward-exempt if >2 testers to test exemption logic.
   - **Looking For**: Successful deployment and ETH transfer to testers; correct exemption setup.
   - **Avoid**: Insufficient ETH in transaction, invalid tester count, or failed ETH transfers.
   - Ensure ETH amount is specified in "value" (above contracts tray) for payable functions.
8. Call `testDispense`:
   - **Objective**: Tests `LinkGold.dispense` by having each tester send 50% of their ETH (e.g., 1 ETH) to mint LAU at 3500/4000 ETH-to-LAU ratio (~0.875 LAU), ensuring at least 0.01 LAU per tester.
   - **Looking For**: Correct LAU minting proportional to ETH sent, successful ETH transfer to `feeClaimer`, and proper balance updates.
   - **Avoid**: Insufficient tester ETH, incorrect LAU calculations, or failed `dispense` calls due to unset oracles/feeClaimer.
9. Call `testApprove`:
   - **Objective**: Tests `LinkGold.approve` by having each tester approve a large allowance (`VERY_BIG_NUMBER`) for `feeClaimer` to enable `mockSwap` transfers.
   - **Looking For**: Successful approval with correct allowance set in `LinkGold`.
   - **Avoid**: Failed approvals due to incorrect parameters or contract state issues.
10. Call `testMockSwap`:
    - **Objective**: Tests `MockFeeClaimer.mockSwap` by executing one swap per tester, deducting 0.01% of their LAU balance (~0.0000875 LAU) via `transferFrom`, verifying successful fee collection.
    - **Looking For**: Successful `transferFrom` with correct fee deduction and balance updates.
    - **Avoid**: Insufficient LAU balance (<0.01 LAU), insufficient allowance, or failed `transferFrom` due to contract misconfiguration.
11. Call `testRewardDistribution`:
    - **Objective**: Tests `LinkGold._distributeRewards` by having tester 0 perform 20 `mockSwap` calls to trigger reward distribution from collected fees, verifying non-exempt testers receive rewards and the exempt tester (if >2 testers) does not.
    - **Looking For**: Fee accumulation in `LinkGold` contract, reward distribution to eligible testers based on their balances, and no rewards for the exempt tester.
    - **Avoid**: Insufficient LAU/allowance for swaps, no fees collected, or rewards incorrectly distributed to exempt testers.
12. Check the Remix console for reverts (failed `require` statements or emitted events like `MockSwapFailed`/`NonRewardedTester` indicate test failures with specific reasons).

## Notes
- Use the default account for all calls.
- Set gas limit to at least 10M in Remix VM.
- Verify contract paths match import statements in `LAUTests.sol`.
- Each tester starts with ~0.875 LAU after `testDispense` (1 ETH at 3500/4000 ratio). Each `mockSwap` deducts ~0.0000875 LAU (0.01%), sufficient for 20 swaps (~0.00175 LAU total).
- Monitor console for detailed error messages to diagnose failures (e.g., insufficient balance/allowance, failed transfers).
