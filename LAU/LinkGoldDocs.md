# Link Gold (LAU) Smart Contract Docs

## Overview
Link Gold (LAU) is an ERC20-compliant token with 18 decimals, built on Solidity ^0.8.2. It features a dispense mechanism to mint LAU by depositing ETH, a cell-based balance tracking system, and a reward distribution mechanism based on `wholeCycle` and `cellCycle` counters. LAU uses Chainlink XAU/USD and ETH/USD oracles to calculate ETH/XAU for minting.

## Dispense Mechanism
The `dispense` function mints LAU by depositing ETH:
- **Params**: None (uses `msg.value`, `msg.sender`).
- **Requires**: `msg.value > 0`, set `oracleAddresses[0]` (XAU/USD), `oracleAddresses[1]` (ETH/USD), `feeClaimer`.
- **Logic**: Fetches XAU/USD and ETH/USD prices via `IOracle.latestAnswer()` (8 decimals). Calculates `ethXauPrice = (ethUsdPrice * 10^8) / xauUsdPrice`. Mints `lauAmount = (msg.value * ethXauPrice) / 10^8` to `msg.sender`. Transfers `msg.value` to `feeClaimer`. Emits `EthTransferred(feeClaimer, msg.value)` and `Dispense(msg.sender, feeClaimer, lauAmount)`.
- **Call Tree**:
  - External: `IOracle.latestAnswer()` (twice) → `_mint(msg.sender, lauAmount)` → `_updateCells(msg.sender, newBalance)`.
  - Emits: `Transfer(address(0), msg.sender, lauAmount)`, `EthTransferred`, `Dispense`.
- **Security**: `nonReentrant` modifier prevents reentrancy.

## Transfer and Fees
- **transfer(to, amount)**: Transfers LAU without fees.
  - **Params**: `to` (recipient address), `amount` (LAU).
  - **Logic**: Calls `_transfer(msg.sender, to, amount)`. Returns `true`.
  - **Call Tree**: `_transfer` → `_updateCells(from, newBalance)`, `_updateCells(to, newBalance)`, `_distributeRewards` (if `swapCount % 10 == 0`) → `_updateCells` (per rewarded address).
  - **Emits**: `Transfer(from, to, amount)`.
- **transferFrom(from, to, amount)**: Transfers LAU with allowance check.
  - **Params**: `from` (sender), `to` (recipient), `amount` (LAU).
  - **Logic**: Checks `_allowances[from][msg.sender] >= amount`, deducts allowance, calls `_transfer`. Returns `true`.
  - **Call Tree**: Same as `transfer`.

## Cell System
- **Structure**: `cells` (mapping: `uint256` → `address[100]`) stores non-zero balance addresses. `addressToCell` maps addresses to cell index.
- **CellHeight**: Public `uint256`, tracks highest cell index.
- **Addition**: Non-zero balance addresses added to `cells[cellHeight]`. Increments `cellHeight` if full.
- **Removal**: Zero-balance addresses removed via gap-closing (last non-zero address in cell fills gap). If highest cell empties, `cellHeight` decrements.
- **Internal Call**: `_updateCells(account, newBalance)` called by `_mint`, `_transfer`, `_distributeRewards`.

## WholeCycle and CellCycle
- **WholeCycle**: Increments every 10 swaps (`swapCount % 10 == 0`).
- **CellCycle**: `mapping(uint256 => uint256)` tracks reward cycles per cell.
- **Reward Distribution** (`_distributeRewards`):
  - **Trigger**: Called by `_transfer` when `wholeCycle` increments.
  - **Logic**: Selects random cell via `keccak256(blockhash, timestamp) % (cellHeight + 1)`. If `cellCycle[selectedCell] < wholeCycle`, distributes `contractBalance / 10000` proportionally to cell balances. Updates `contractBalance`, `_balances`, `cellCycle`.
  - **Call Tree**: `_updateCells` for each rewarded address.
  - **Emits**: `Transfer(address(this), account, accountReward)`, `RewardsDistributed(selectedCell, rewardAmount)`.

## Reentrancy Protection
- `dispense`: Uses `nonReentrant` modifier.
- Others: Safe due to balance checks before external calls.

## Chainlink Oracles
- **Interface**: `IOracle.latestAnswer()` returns int256 (8 decimals) for XAU/USD or ETH/USD.
- **Logic**: `setOracleAddresses(_oracleAddresses)` (owner-only) sets `[XAU/USD, ETH/USD]`. `dispense` and `getOraclePrice` calculate `ethXauPrice = (ethUsdPrice * 10^8) / xauUsdPrice`. Reverts on negative prices.
- **Call Tree**: `IOracle.latestAnswer()` called by `dispense`, `getOraclePrice`.
- **Frontend Interaction (Etherscan)**: To call `setOracleAddresses` via Etherscan:
  - Navigate to the contract’s “Write Contract” tab on Etherscan.
  - Connect your wallet (owner address required).
  - In the `setOracleAddresses` input, enter the array as a comma-separated list in square brackets, e.g., `[0xXAUUSDAddress,0xETHUSDAddress]`, where `0xXAUUSDAddress` and `0xETHUSDAddress` are the Chainlink oracle addresses for XAU/USD and ETH/USD.
  - Submit the transaction, ensuring both addresses are valid and non-zero to avoid reversion.

## Query Functions
- **Standard**:
  - `balanceOf(account)`: Returns `_balances[account]`.
  - `allowance(owner_, spender)`: Returns `_allowances[owner_][spender]`.
  - `totalSupply()`: Returns `_totalSupply`.
  - `decimals()`: Returns 18.
  - `name()`: Returns "Link Gold".
  - `symbol()`: Returns "LAU".
  - `getOraclePrice()`: Returns ETH/XAU price or 0 if unset/invalid.
- **Exotic**:
  - `getCell(cellIndex)`: Returns `cells[cellIndex]`.
  - `getAddressCell(account)`: Returns `addressToCell[account]`.
  - `getCellBalances(cellIndex)`: Returns non-zero addresses and balances in cell.
  - `getTopHolders(count)`: Iterates over all cells (might be gas intensive), Returns top holders up to the `count` number specified and their balances.

## Security Considerations
- **Owner Privileges**: `setOracleAddresses`, `setFeeClaimer` are owner-only.
- **Cell Management**: Empty cells below `cellHeight` may be selected (skipped if `cellBalance == 0`).
- **ETH Transfer**: `feeClaimer` must accept ETH to avoid `dispense` reversion.
- **Oracle Accuracy**: Ensure Chainlink oracles provide reliable XAU/USD and ETH/USD prices.
