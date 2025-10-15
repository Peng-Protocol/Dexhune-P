# Link Gold (LAU) Smart Contract Docs

## Overview
Link Gold (LAU) is an ERC20-compliant token with 18 decimals, built on Solidity ^0.8.2. It features a dispense mechanism to mint LAU by depositing ETH, a cell-based balance tracking system, and a reward distribution mechanism based on `wholeCycle` and `cellCycle` counters. LAU uses Chainlink XAU/USD and ETH/USD oracles to calculate ETH/XAU for minting. It integrates with `TokenRegistry` for transfer and dispense tracking, with reward exemptions.

## Dispense Mechanism
The `dispense` function mints LAU by depositing ETH:
- **Params**: None (uses `msg.value`, `msg.sender`).
- **Requires**: `msg.value > 0`, set `oracleAddresses[0]` (XAU/USD), `oracleAddresses[1]` (ETH/USD), `feeClaimer`.
- **Logic**: Fetches XAU/USD and ETH/USD prices via `IOracle.latestAnswer()` (8 decimals). Calculates `ethXauPrice = (ethUsdPrice * 10^8) / xauUsdPrice`. Mints `lauAmount = (msg.value * ethXauPrice) / 10^8` to `msg.sender`. Registers `msg.sender` in `TokenRegistry` via `initializeBalances`. Transfers `msg.value` to `feeClaimer`. Emits `EthTransferred(feeClaimer, msg.value)` and `Dispense(msg.sender, feeClaimer, lauAmount)`.
- **Call Tree**:
  - External: `IOracle.latestAnswer()` (twice) → `_mint(msg.sender, lauAmount)` → `_updateCells(msg.sender, newBalance)` → `TokenRegistry.initializeBalances(address(this), [msg.sender])` → `feeClaimer.call{value: msg.value}`.
  - Emits: `Transfer(address(0), msg.sender, lauAmount)`, `TokenRegistryCallFailed` (if registry fails), `EthTransferred`, `Dispense`.
- **Security**: `nonReentrant` modifier prevents reentrancy.

## Transfer and Fees
- **transfer(to, amount)**: Transfers LAU without fees, registers sender/receiver in `TokenRegistry`.
  - **Params**: `to` (recipient address), `amount` (LAU).
  - **Logic**: Calls `_transferWithRegistry(msg.sender, to, amount)`. Transfers full `amount`, registers in `TokenRegistry` via `initializeBalances`. Increments `swapCount`, triggers `_distributeRewards` if `swapCount % 10 == 0`. Returns `true`.
  - **Call Tree**: `_transferWithRegistry` → `_updateCells(from, newBalance)`, `_updateCells(to, newBalance)`, `TokenRegistry.initializeBalances(address(this), [from, to])`, `_distributeRewards` (if `swapCount % 10 == 0`) → `_updateCells` (per rewarded address).
  - **Emits**: `Transfer(from, to, amount)`, `TokenRegistryCallFailed` (if registry fails), `RewardsDistributed`, `Transfer` (if rewards distributed).
- **transferFrom(from, to, amount)**: Transfers LAU without fees, no `TokenRegistry` calls.
  - **Params**: `from` (sender), `to` (recipient), `amount` (LAU).
  - **Logic**: Checks `_allowances[from][msg.sender] >= amount`, deducts allowance, calls `_transferBasic`. Transfers full `amount`. Increments `swapCount`, triggers `_distributeRewards` if needed. Returns `true`.
  - **Call Tree**: `_transferBasic` → `_updateCells(from, newBalance)`, `_updateCells(to, newBalance)`, `_distributeRewards` (if needed) → `_updateCells` (per rewarded address).
  - **Emits**: `Transfer(from, to, amount)`, `RewardsDistributed`, `Transfer` (if rewards distributed).

## Cell System
- **Structure**: `cells` (mapping: `uint256` → `address[100]`) stores non-zero balance addresses. `addressToCell` maps addresses to cell index.
- **CellHeight**: Public `uint256`, tracks highest cell index.
- **Addition**: Non-zero balance addresses added to `cells[cellHeight]`. Increments `cellHeight` if full.
- **Removal**: Zero-balance addresses removed via gap-closing (last non-zero address fills gap). If highest cell empties, `cellHeight` decrements.
- **Internal Call**: `_updateCells(account, newBalance)` called by `_mint`, `_transferWithRegistry`, `_transferBasic`, `_distributeRewards`.

## Reward Distribution
- **Mechanism**: Distributes `contractBalance / 10000` to a randomly selected cell every 10 swaps (`swapCount % 10 == 0`), incrementing `wholeCycle`.
- **Logic**: 
  - Selects cell via `keccak256(blockhash, timestamp) % (cellHeight + 1)`. Skips if `cellCycle[selectedCell] >= wholeCycle` or `cellBalance == 0`.
  - Calculates total `cellBalance` excluding `rewardExceptions` addresses.
  - Distributes reward proportionally to non-exempt account balances in the cell.
  - Updates `contractBalance`, `_balances`, `cellCycle[selectedCell]`.
- **Reward Exceptions**: `rewardExceptions` mapping and `rewardExceptionList` array track exempt addresses, managed via `addRewardExceptions` and `removeRewardExceptions` (owner-only). `getRewardExceptions(start, maxIterations)` provides paginated access.
- **Call Tree**: `_distributeRewards` → `_updateCells` (per rewarded address).
- **Emits**: `Transfer(address(this), account, accountReward)`, `RewardsDistributed(selectedCell, rewardAmount)`.
- **Trigger**: Called by `_transferWithRegistry`, `_transferBasic` when `wholeCycle` increments.

## WholeCycle and CellCycle
- **WholeCycle**: Increments every 10 swaps (`swapCount % 10 == 0`).
- **CellCycle**: `mapping(uint256 => uint256)` tracks reward cycles per cell.

## Reentrancy Protection
- `dispense`: Uses `nonReentrant` modifier.
- Others: Safe due to balance checks before external calls.

## Chainlink Oracles
- **Interface**: `IOracle.latestAnswer()` returns int256 (8 decimals) for XAU/USD or ETH/USD.
- **Logic**: `setOracleAddresses(_oracleAddresses)` (owner-only) sets `[XAU/USD, ETH/USD]`. `dispense` and `getOraclePrice` calculate `ethXauPrice = (ethUsdPrice * 10^8) / xauUsdPrice`. Reverts on negative prices.
- **Call Tree**: `IOracle.latestAnswer()` called by `dispense`, `getOraclePrice`.
- **Frontend Interaction (Etherscan)**: To call `setOracleAddresses`:
  - Navigate to “Write Contract” on Etherscan.
  - Connect owner wallet.
  - Input `[0xXAUUSDAddress,0xETHUSDAddress]` in `setOracleAddresses`, using valid Chainlink oracle addresses.

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
  - `getTopHolders(count)`: Returns top `count` holders and balances.
  - `getRewardExceptions(start, maxIterations)`: Returns paginated exempt addresses.

## Security Considerations
- **Owner Privileges**: `setOracleAddresses`, `setFeeClaimer`, `setTokenRegistry`, `addRewardExceptions`, `removeRewardExceptions` are owner-only.
- **Cell Management**: Empty cells below `cellHeight` may be selected (skipped if `cellBalance == 0`).
- **ETH Transfer**: `feeClaimer` must accept ETH to avoid `dispense` reversion.
- **TokenRegistry**: Must be set via `setTokenRegistry` to enable registration in `transfer` and `dispense`.
