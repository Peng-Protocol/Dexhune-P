### OMFAgent - Liquidity/ListingLogic Contracts Documentation

The system comprises `OMFAgent`, `OMFListingLogic`, and `CCLiquidityLogic`. Together, they form the factory suite of an AMM Orderbook Hybrid on the EVM, with listings restricted to a fixed `baseToken` as `tokenB` and oracle parameters for price feeds.

## CCLiquidityLogic Contract

The liquidity logic inherits `CCLiquidityTemplate` and is used by the `OMFAgent` to deploy new liquidity contracts tied to listing contracts for a unique `tokenA` and `baseToken` pair.

### Mappings and Arrays

- None defined in this contract.

### State Variables

- None defined in this contract.

### Functions

#### deploy

- **Parameters**:
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions**:
  - Deploys a new `CCLiquidityTemplate` contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns**:
  - `address`: Address of the newly deployed `CCLiquidityTemplate` contract.

## MFPListingLogic Contract

The listing logic inherits `OMFListingTemplate` and is used by the `OMFAgent` to deploy new listing contracts tied to liquidity contracts for a unique `tokenA` and `baseToken` pair.

### Mappings and Arrays

- None defined in this contract.

### State Variables

- None defined in this contract.

### Functions

#### deploy

- **Parameters**:
  - `salt` (bytes32): Unique salt for deterministic address generation.
- **Actions**:
  - Deploys a new `OMFListingTemplate` contract using the provided salt.
  - Uses create2 opcode via explicit casting to address for deployment.
- **Returns**:
  - `address`: Address of the newly deployed `OMFListingTemplate` contract.

## OMFAgent Contract

The agent manages token listings, enables the creation of unique listings and liquidities for token pairs with `tokenA` and a fixed `baseToken` as `tokenB`, and arbitrates valid listings, templates, and routers. Native ETH is not supported as `tokenA`. Oracle parameters are set during listing/relisting.

### Structs

- **ListingDetails**: Details of a listing contract.
  - `listingAddress` (address): Listing contract address.
  - `liquidityAddress` (address): Associated liquidity contract address.
  - `tokenA` (address): First token in pair.
  - `tokenB` (address): Fixed to `baseToken`.
  - `listingId` (uint256): Listing ID.
- **OracleParams**: Parameters for oracle price feed configuration.
  - `oracleAddress` (address): Oracle contract address.
  - `oracleFunction` (bytes4): Oracle function selector (e.g., `0x50d25bcd` for `latestAnswer()`).
  - `oracleBitSize` (uint16): Bit size of oracle return type (e.g., `256` for `int256`).
  - `oracleIsSigned` (bool): True for signed types (e.g., `int256`), false for unsigned (e.g., `uint256`).
  - `oracleDecimals` (uint8): Oracle decimals (e.g., `8` for Chainlink).

### Mappings and Arrays

- `getListing` (mapping - address => address): Maps `tokenA` to the listing address for a trading pair with `baseToken`.
- `allListings` (address[]): Array of all listing addresses created.
- `allListedTokens` (address[]): Array of all unique tokens listed, including `baseToken`.
- `queryByAddress` (mapping - address => uint256[]): Maps a token to an array of listing IDs involving that token.
- `getLister` (mapping - address => address): Maps listing address to the lister’s address.
- `listingsByLister` (mapping - address => uint256[]): Maps a lister to an array of their listing IDs.

### State Variables

- `routers` (address[]): Array of router contract addresses, set post-deployment via `addRouter`.
- `listingLogicAddress` (address): Address of the `MFPListingLogic` contract, set post-deployment.
- `liquidityLogicAddress` (address): Address of the `CCLiquidityLogic` contract, set post-deployment.
- `registryAddress` (address): Address of the registry contract, set post-deployment.
- `baseToken` (address): Fixed `tokenB` for all listings, set post-deployment via `setBaseToken`.
- `listingCount` (uint256): Counter for the number of listings created, incremented per listing.
- `globalizerAddress` (address): Address of the globalizer contract, set post-deployment via `setGlobalizerAddress`.

### Functions

#### Setter Functions

- **addRouter**
  - **Parameters**:
    - `router` (address): Address to add to the routers array.
  - **Actions**:
    - Requires non-zero address and that the router does not already exist.
    - Appends the router to the `routers` array.
    - Emits `RouterAdded` event.
    - Restricted to owner via `onlyOwner` modifier.
- **removeRouter**
  - **Parameters**:
    - `router` (address): Address to remove from the routers array.
  - **Actions**:
    - Requires non-zero address and that the router exists.
    - Removes the router by swapping with the last element and popping the array.
    - Emits `RouterRemoved` event.
    - Restricted to owner via `onlyOwner` modifier.
- **getRouters**
  - **Actions**:
    - Returns the current `routers` array.
  - **Returns**:
    - `address[]`: Array of all router addresses.
- **setListingLogic**
  - **Parameters**:
    - `_listingLogic` (address): Address to set as the listing logic contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `listingLogicAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setLiquidityLogic**
  - **Parameters**:
    - `_liquidityLogic` (address): Address to set as the liquidity logic contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `liquidityLogicAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setRegistry**
  - **Parameters**:
    - `_registryAddress` (address): Address to set as the registry contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `registryAddress` state variable.
    - Restricted to owner via `onlyOwner` modifier.
- **setBaseToken**
  - **Parameters**:
    - `_baseToken` (address): Address to set as the fixed `tokenB`.
  - **Actions**:
    - Requires non-zero address and that `baseToken` is not already set.
    - Updates `baseToken` state variable.
    - Emits `BaseTokenSet` event.
    - Restricted to owner via `onlyOwner` modifier.
- **setGlobalizerAddress**
  - **Parameters**:
    - `_globalizerAddress` (address): Address to set as the globalizer contract.
  - **Actions**:
    - Requires non-zero address.
    - Updates `globalizerAddress` state variable.
    - Emits `GlobalizerAddressSet` event.
    - Restricted to owner via `onlyOwner` modifier.

#### Listing Functions

- **listToken**
  - **Parameters**:
    - `tokenA` (address): First token in the pair (must not be zero or `baseToken`).
    - `oracleParams` (OracleParams): Struct with oracle configuration (`oracleAddress`, `oracleFunction`, `oracleBitSize`, `oracleIsSigned`, `oracleDecimals`).
  - **Actions**:
    - Verifies `baseToken` is set, `tokenA` is valid and not equal to `baseToken`, and pair isn’t already listed.
    - Validates oracle parameters: non-zero `oracleAddress`, non-zero `oracleFunction`, `oracleBitSize` > 0 and ≤ 256, `oracleDecimals` ≤ 18.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create listing and liquidity contracts with salt based on `tokenA`, `baseToken`, and `listingCount`.
    - Calls `_initializeListing` to set up listing contract with `routers` array, listing ID, liquidity address, `tokenA`, `baseToken`, agent, registry, `globalizerAddress` (if set), and `oracleParams`.
    - Calls `_initializeLiquidity` to set up liquidity contract with `routers` array, listing ID, listing address, `tokenA`, `baseToken`, and agent.
    - Calls `_updateState` to update `getListing`, `allListings`, `allListedTokens`, `queryByAddress`, `getLister`, and `listingsByLister`, storing `msg.sender` as lister.
    - Emits `ListingCreated` event with `tokenA`, `baseToken`, listing address, liquidity address, listing ID, and lister.
    - Increments `listingCount`.
  - **Returns**:
    - `listingAddress` (address): Address of the new listing contract.
    - `liquidityAddress` (address): Address of the new liquidity contract.
- **relistToken**
  - **Parameters**:
    - `tokenA` (address): First token in the pair (must not be zero or `baseToken`).
    - `oracleParams` (OracleParams): Struct with oracle configuration.
  - **Actions**:
    - Verifies `baseToken` is set, `tokenA` is valid and not equal to `baseToken`, and pair is already listed.
    - Verifies `msg.sender` is the original lister via `getLister`.
    - Validates oracle parameters: non-zero `oracleAddress`, non-zero `oracleFunction`, `oracleBitSize` > 0 and ≤ 256, `oracleDecimals` ≤ 18.
    - Verifies at least one router, `listingLogicAddress`, `liquidityLogicAddress`, and `registryAddress` are set.
    - Calls `_deployPair` to create new listing and liquidity contracts with salt based on `tokenA`, `baseToken`, and `listingCount`.
    - Calls `_initializeListing` to set up new listing contract with `routers` array, listing ID, liquidity address, `tokenA`, `baseToken`, agent, registry, `globalizerAddress` (if set), and `oracleParams`.
    - Calls `_initializeLiquidity` to set up new liquidity contract with `routers` array, listing ID, listing address, `tokenA`, `baseToken`, and agent.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and `msg.sender` as lister.
    - Emits `ListingRelisted` event with `tokenA`, `baseToken`, old listing address, new listing address, listing ID, and lister.
    - Increments `listingCount`.
  - **Returns**:
    - `newListingAddress` (address): Address of the new listing contract.
    - `newLiquidityAddress` (address): Address of the new liquidity contract.
- **transferLister**
  - **Parameters**:
    - `listingAddress` (address): Address of the listing to transfer lister status.
    - `newLister` (address): Address of the new lister.
  - **Actions**:
    - Verifies `msg.sender` is the current lister via `getLister`.
    - Requires non-zero `newLister` address.
    - Updates `getLister` mapping with `newLister`.
    - Retrieves `listingId` from `allListings` and appends to `listingsByLister` for `newLister`.
    - Emits `ListerTransferred` event.
- **getListingsByLister**
  - **Parameters**:
    - `lister` (address): Address of the lister to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Retrieves indices from `listingsByLister` mapping.
    - Calculates start and end bounds based on `step` and `maxIteration`.
    - Returns a subset of indices for pagination.
  - **Returns**:
    - `uint256[]`: Array of listing IDs for the lister.

#### View Functions

- **isValidListing**
  - **Parameters**:
    - `listingAddress` (address): Address to check.
  - **Actions**:
    - Iterates `allListings` to find matching address.
    - If found, retrieves `tokenA` and `tokenB` via `ICCListingTemplate.getTokens`.
    - Retrieves liquidity address via `ICCListing.liquidityAddressView`.
    - Constructs `ListingDetails` struct with `listingAddress`, `liquidityAddress`, `tokenA`, `tokenB`, and `listingId`.
  - **Returns**:
    - `isValid` (bool): True if listing is valid.
    - `details` (ListingDetails): Struct with `listingAddress`, `liquidityAddress`, `tokenA`, `tokenB`, and `listingId`.
- **queryByIndex**
  - **Parameters**:
    - `index` (uint256): Index to query.
  - **Actions**:
    - Validates index is within `allListings` length.
    - Retrieves listing address from `allListings` array.
  - **Returns**:
    - `address`: Listing address at the index.
- **queryByAddressView**
  - **Parameters**:
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Number of indices to return per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Retrieves indices from `queryByAddress` mapping.
    - Calculates start and end bounds based on `step` and `maxIteration`.
    - Returns a subset of indices for pagination.
  - **Returns**:
    - `uint256[]`: Array of listing IDs for the target token.
- **queryByAddressLength**
  - **Parameters**:
    - `target` (address): Token to query.
  - **Actions**:
    - Retrieves length of `queryByAddress` array for the target token.
  - **Returns**:
    - `uint256`: Number of listing IDs for the target token.
- **allListingsLength**
  - **Actions**:
    - Retrieves length of `allListings` array.
  - **Returns**:
    - `uint256`: Total number of listings.
- **allListedTokensLength**
  - **Actions**:
    - Retrieves length of `allListedTokens` array.
  - **Returns**:
    - `uint256`: Total number of listed tokens.

## Additional Details

- **Relisting Behavior**:
  - **Purpose**: `relistToken` allows the original lister to replace a token pair listing with a new one to update routers, oracle parameters, or other configurations.
  - **Replacement**:
    - Deploys new `MFPListingTemplate` and `SSLiquidityTemplate` contracts with a new `listingId`.
    - Updates `getListing`, `allListings`, `queryByAddress`, `getLister`, and `listingsByLister` with new listing address and lister.
    - Old listing remains in `allListings` but is no longer referenced in `getListing` for the `tokenA`-`baseToken` pair.
  - **User Interaction with Old Listings**:
    - Old listings remain accessible via `CCOrderRouter` functions (e.g., `createTokenBuyOrder`, `createTokenSellOrder`, `clearSingleOrder`, `executeLongPayouts`, `executeShortPayouts`, `settleLongLiquid`, `settleShortLiquid`) because `isValidListing` validates against `allListings`.
    - Users can interact with old listings by explicitly providing their addresses, allowing order creation, cancellation, or payout execution, provided sufficient liquidity and valid order states.
    - New orders for the `tokenA`-`baseToken` pair will use the new listing address via `getListing[tokenA]`, potentially causing confusion if users interact with the old listing unintentionally.
  - **Event**: Emits `ListingRelisted` with `tokenA`, `baseToken`, old and new listing addresses, new `listingId`, and lister.
- **Oracle Parameters**:
  - **Purpose**: `OracleParams` struct allows users to configure oracle settings during `listToken` and `relistToken`, enabling price feeds for the listing contract (e.g., via Chainlink).
  - **Validation**: Ensures `oracleAddress` is non-zero, `oracleFunction` is non-zero, `oracleBitSize` is > 0 and ≤ 256, and `oracleDecimals` is ≤ 18.
  - **Integration**: Passed to `setOracleParams` in the listing contract during `_initializeListing`, ensuring price feed compatibility with `OMFListingTemplate`.
- **Globalizer Integration**:
  - The `globalizerAddress` is set in new listing contracts via `setGlobalizerAddress` during `_initializeListing` if defined, enabling integration with a separate globalizer contract for order and liquidity management.
- **Lister Tracking**:
  - `msg.sender` is stored as the lister in `listToken` via `getLister` and `listingsByLister`.
  - `transferLister` allows the current lister to transfer control to a new address, updating `getLister` and `listingsByLister`.
  - `getListingsByLister` provides paginated access to a lister’s listing IDs.
- **No Native ETH Support**:
  - Unlike `MFPAgent`, `OMFAgent` does not support native ETH as `tokenA`. All listings use `tokenA` as an ERC20 token and `baseToken` as `tokenB`.
