# Link Dollar v2 (LUSD) Docs

## Overview
Link Dollar v2 (LUSD) is an ERC20-compliant token with 18 decimals, built on Solidity ^0.8.2. It features a dispense mechanism to mint LUSD by depositing ETH, a 0.05% transfer fee, a cell-based balance tracking system, and reward distribution based on `wholeCycle` and `cellCycle` counters. LUSD integrates with a Chainlink ETH/USD oracle and `TokenRegistry` for transfer tracking, with reward exemptions.

## Dispense Mechanism
The `dispense` function mints LUSD by depositing ETH:
- **Params**: None (uses `msg.value`, `msg.sender`).
- **Requires**: `msg.value > 0`, set `oracleAddress`, `feeClaimer`.
- **Logic**: Fetches ETH/USD price via `IOracle.latestAnswer()` (8 decimals). Calculates `lusdAmount = msg.value * price / 10^8`. Mints to `msg.sender`. Transfers `msg.value` to `feeClaimer`. Emits `EthTransferred(feeClaimer, msg.value)` and `Dispense(msg.sender, feeClaimer, lusdAmount)`.
- **Call Tree**:
  - External: `IOracle.latestAnswer()` → `_mint(msg.sender, lusdAmount)` → `_updateCells(msg.sender, newBalance)`.
  - Emits: `Transfer(address(0), msg.sender, lusdAmount)`, `EthTransferred`, `Dispense`.
- **Security**: `nonReentrant` modifier prevents reentrancy.

## Transfer and Fees
- **transfer(to, amount)**: Transfers LUSD with 0.05% fee, registers sender/receiver in `TokenRegistry`.
  - **Params**: `to` (recipient address), `amount` (LUSD).
  - **Logic**: Calls `_transferWithRegistry(msg.sender, to, amount)`. Registers in `TokenRegistry` via `initializeBalances`. Returns `true`.
  - **Call Tree**: `_transferWithRegistry` → `_updateCells(from, newBalance)`, `_updateCells(to, newBalance)`, `TokenRegistry.initializeBalances`, `_distributeRewards` (if `swapCount % 10 == 0`).
  - **Emits**: `Transfer(from, to, amountAfterFee)`, `Transfer(from, address(this), fee)`, `TokenRegistryCallFailed` (if registry fails).
- **transferFrom(from, to, amount)**: Transfers LUSD with fee, no `TokenRegistry` calls.
  - **Params**: `from` (sender), `to` (recipient), `amount` (LUSD).
  - **Logic**: Checks `_allowances[from][msg.sender] >= amount`, deducts allowance, calls `_transferBasic`. Returns `true`.
  - **Call Tree**: `_transferBasic` → `_updateCells`, `_distributeRewards` (if needed).
- **Fee**: 0.05% (5 bps) added to `contractBalance`.

## Cell System
- **Structure**: `cells` (mapping: `uint256` → `address[100]`) stores non-zero balance addresses. `addressToCell` maps addresses to cell index.
- **CellHeight**: Public `uint256`, tracks highest cell index.
- **Addition**: Non-zero balance addresses added to `cells[cellHeight]`. Increments `cellHeight` if full.
- **Removal**: Zero-balance addresses removed via gap-closing (last non-zero address fills gap). If highest cell empties, `cellHeight` decrements.
- **Internal Call**: `_updateCells(account, newBalance)` called by `_mint`, `_transferWithRegistry`, `_transferBasic`, `_distributeRewards`.

## Reward Distribution
- **Mechanism**: Distributes `contractBalance * 0.05%` to a randomly selected cell every 10 swaps (`swapCount % 10 == 0`), incrementing `wholeCycle`.
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

## Chainlink Oracle
- **Interface**: `IOracle.latestAnswer()` returns int256 (8 decimals).
- **Logic**: Converts to uint256, reverts on negative. Set via `setOracleAddress(_oracleAddress)` (owner-only).
- **Call Tree**: Called by `dispense`, `getOraclePrice`.

## Query Functions
- **Standard**:
  - `balanceOf(account)`: Returns `_balances[account]`.
  - `allowance(owner_, spender)`: Returns `_allowances[owner_][spender]`.
  - `totalSupply()`: Returns `_totalSupply`.
  - `decimals()`: Returns 18.
  - `name()`: Returns "Link Dollar v2".
  - `symbol()`: Returns "LUSD".
  - `getOraclePrice()`: Returns Chainlink price or 0 if unset.
- **Exotic**:
  - `getCell(cellIndex)`: Returns `cells[cellIndex]`.
  - `getAddressCell(account)`: Returns `addressToCell[account]`.
  - `getCellBalances(cellIndex)`: Returns non-zero addresses and balances in cell.
  - `getTopHolders(count)`: Returns top `count` holders and balances.
  - `getRewardExceptions(start, maxIterations)`: Returns paginated exempt addresses.

## Security Considerations
- **Owner Privileges**: `setOracleAddress`, `setFeeClaimer`, `setTokenRegistry`, `addRewardExceptions`, `removeRewardExceptions` are owner-only.
- **Cell Management**: Empty cells below `cellHeight` may be selected (skipped if `cellBalance == 0`).
- **ETH Transfer**: `feeClaimer` must accept ETH to avoid `dispense` reversion.
- **TokenRegistry**: Must be set via `setTokenRegistry` to enable registration in `transfer`.
