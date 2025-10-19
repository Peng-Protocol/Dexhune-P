# Running LAU Tests in Remix

## Prerequisites
- Ensure `LinkGold.sol`, `MockFeeClaimer.sol`, `MockOracleETH.sol`, `MockOracleXAU.sol`, and `LAUTests.sol` are in your Remix workspace.
- `LinkGold.sol` should be in the `./LAU` directory.
- Mock contracts should be in the `./LAU/Tests` directory.

## Steps
1. Open Remix (https://remix.ethereum.org).
2. Upload all contracts to the respective directories.
3. In the "Solidity Compiler" tab, select version `^0.8.2` and compile all contracts.
4. In the "Deploy & Run Transactions" tab, select the `LAUTests` contract.
5. Deploy `LAUTests` using the Remix VM environment.
6. Run the `testLAUFlow` function to execute the test suite.
7. Check the Remix console for test results, ensuring all assertions pass.

## Notes
- Ensure sufficient gas limits in Remix VM.
- Verify contract paths match the import statements in `LAUTests.sol`.
</xaiArtifact>