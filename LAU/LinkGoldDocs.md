# Link Gold (LAU) Smart Contract Documentation

## Overview
Link Gold (LAU) is an ERC20-compliant token with 18 decimals, built on Solidity 0.8.2. It features a dispense mechanism to mint LAU by depositing ETH, a cell-based balance tracking system, and a reward distribution mechanism based on wholeCycle and cellCycle counters. LAU integrates with a Chainlink oracle for ETH/USD pricing and a TokenRegistry for balance updates in transfers and dispensing.

## Dispense Mechanism
The `dispense` function allows users to deposit ETH to mint LAU:
- Requires non-zero ETH (`msg.value > 0`), set `oracleAddress`, and `feeClaimer`.
- Uses Chainlink’s `latestAnswer` (8 decimals) to fetch ETH/USD price.
- Calculates LAU: `lauAmount = msg.value * price / 10^8`, minted to caller.
- Transfers `msg.value` (ETH) to `feeClaimer`, emitting `EthTransferred` on success.
- Protected by a `nonReentrant` modifier to prevent reentrancy attacks.
- Calls `TokenRegistry.initializeBalances([address(this)], [msg.sender])` if `tokenRegistry` is set; otherwise, emits `TokenRegistryNotSet` with `msg.sender`.
- Emits `Dispense(recipient, feeClaimer, lauAmount)` to log LAU minted to `recipient`.

## Transfer and Fees
- **Transfer/TransferFrom**: Transfers LAU without fees.
- Updates sender and recipient balances, calls `_updateCells` for cell management.
- Calls `TokenRegistry.initializeBalances([address(this)], [from, to])` if `tokenRegistry` is set; otherwise, emits `TokenRegistryNotSet`.
- Increments `swapCount`; every 10 swaps increments `wholeCycle` and triggers `_distributeRewards`.

## Cell System
- **Structure**: Addresses with non-zero balances are stored in cells (`cells`), each holding up to 100 addresses.
- **CellHeight**: Tracks highest cell index where an address was added, incremented when a cell fills.
- **Addition**: New non-zero balance addresses are added to `cells[cellHeight]`.
- **Removal**: If balance becomes 0, address is removed via gap-closing (last non-zero address in the same cell fills the gap). Gap-closing is isolated to the individual cell, with no impact on other cells.
- **Cell Gap-Closing**: If a cell becomes empty and is the highest cell (`cellIndex == cellHeight`), `cellHeight` is decremented. This repeats for consecutive empty cells at the top, ensuring efficiency without updating addresses in other cells.
- **Tracking**: `addressToCell` maps addresses to their cell index.

## WholeCycle and CellCycle
- **WholeCycle**: Increments every 10 swaps (`transfer` or `transferFrom`).
- **CellCycle**: Each cell has a `cellCycle` counter, incremented after receiving rewards.
- **Reward Distribution**:
  - Triggered when `wholeCycle` increments.
  - Selects one random cell (index 0 to `cellHeight`) using `keccak256(blockhash, timestamp) % (cellHeight + 1)`.
  - If `cellCycle[selectedCell] < wholeCycle`, distributes `contractBalance / 10000` proportionally to cell addresses based on their balances.
  - Updates `contractBalance` and recipient balances.

## TokenRegistry Integration
- **Purpose**: Tracks LAU balances via `initializeBalances(address token, address[] memory userAddresses)`, updating `userTokens` and `userTokenExists`.
- **Setup**: `tokenRegistry` address set via owner-only `setTokenRegistry`.
- **Usage**:
  - `transfer`/`transferFrom`: Calls `initializeBalances([address(this)], [from, to])`.
  - `dispense`: Calls `initializeBalances([address(this)], [msg.sender])`.
  - **Graceful Degradation**: If `tokenRegistry` is unset, skips `initializeBalances` and emits `TokenRegistryNotSet` with the token and affected users.

## Reentrancy Protection
- `dispense` uses a `nonReentrant` modifier to prevent reentrancy during ETH processing and minting.
- Other functions are safe due to balance checks and no external calls before state updates.

## Chainlink Oracle
- Uses Chainlink ETH/USD price feed via `IOracle.latestAnswer()`, returning int256 with 8 decimals.
- Price converted to uint256; negative prices cause reversion.
- Owner sets `oracleAddress` via `setOracleAddress`.

## Query Functions
- **Standard**:
  - `balanceOf(address)`: Returns account balance.
  - `allowance(address, address)`: Returns allowance.
  - `totalSupply()`: Returns total LAU supply.
  - `decimals()`: Returns 18.
  - `name()`: Returns "Link Gold".
  - `symbol()`: Returns "LAU".
  - `getOraclePrice()`: Returns current Chainlink price.
  - `getCell(uint256)`: Returns address array for a cell.
  - `getAddressCell(address)`: Returns cell index for an address.
  - `getCellBalances(uint256)`: Returns non-zero addresses in a cell and their balances.
- **Exotic**:
  - `getTopHolders(uint256 count)`: Returns top `count` addresses by balance and their balances, sorted across all cells.

## Security Considerations
- **Owner Privileges**: `setOracleAddress`, `setFeeClaimer`, `setTokenRegistry` are owner-only, requiring secure key management.
- **TokenRegistry**: Graceful degradation ensures functionality if `tokenRegistry` is unset. Assumes `initializeBalances` is permissionless.
- **Cell Management**: Cell gap-closing ensures efficient `cellHeight`, but empty cells below `cellHeight` may persist and be selected (skipped via `cellBalance == 0`). Consider compacting cells if needed.
- **ETH Transfer**: ETH transfer to `feeClaimer` uses `call` for safety, but `feeClaimer` must accept ETH to avoid reversion.
