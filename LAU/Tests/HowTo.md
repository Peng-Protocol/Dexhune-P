# Running LAU Tests in Remix

## Prerequisites
- Ensure `LinkGold.sol`, `MockFeeClaimer.sol`, `MockOracleETH.sol`, `MockOracleXAU.sol`, and `LAUTests.sol` are in your Remix workspace.
- Place `LinkGold.sol` in `./LAU`.
- Place mock contracts and `LAUTests.sol` in `./LAU/Tests`.

## Steps
1. Open Remix (https://remix.ethereum.org).
2. Upload all contracts to the specified directories.
3. In the "Solidity Compiler" tab, select `^0.8.2` and compile all contracts.
4. In the "Deploy & Run Transactions" tab, select the Remix VM.
5. Ensure sufficient ETH balance (100 ETH default).
6. Deploy `LAUTests` using the default account.
7. Call `initiateTesters` with 10 ETH and specify number of testers (e.g., 5). Last tester is reward-exempt if >2 testers.
 - Ensure ETH amount is specified in "value" (above contracts tray) when calling payable functions.
8. Call `testDispense`, then `testApprove`, and `testMockSwap` sequentially.
9. Check the Remix console for reverts (failed `require` statements indicate test failures).

## Notes
- Use the default account for all calls.
- Set gas limit to at least 10M in Remix VM.
- Verify contract paths match import statements in `LAUTests.sol`.