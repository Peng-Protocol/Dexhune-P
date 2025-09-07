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

The agent manages token listings, creating unique listings and liquidity contracts for `tokenA` and a fixed `baseToken` as `tokenB`, arbitrating valid listings, templates, and routers. Native ETH is not supported as `tokenA`. Oracle parameters, including base token oracle parameters, are set during listing/relisting.

### Structs

- **ListingDetails**:
  - `listingAddress` (address): Listing contract address.
  - `liquidityAddress` (address): Associated liquidity contract address.
  - `tokenA` (address): First token in pair.
  - `tokenB` (address): Fixed to `baseToken`.
  - `listingId` (uint256): Listing ID.
- **OracleParams**:
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
- `baseOracleParams` (OracleParams): Base token oracle parameters, set via `setBaseOracleParams`.
- `_baseOracleSet` (bool): Tracks if base oracle parameters are set.

### Functions

#### Setter Functions

- **addRouter**
  - **Parameters**:
    - `router` (address): Router address to add.
  - **Actions**:
    - Validates non-zero address and non-existing router.
    - Appends to `routers` array.
    - Emits `RouterAdded`.
  - **Restricted**: `onlyOwner`.
  - **Internal Call Tree**:
    - Calls `routerExists`.
  - **Emits**: `RouterAdded`.
- **removeRouter**
  - **Parameters**:
    - `router` (address): Router address to remove.
  - **Actions**:
    - Validates non-zero address and existing router.
    - Removes router by swapping with the last element and popping.
    - Emits `RouterRemoved`.
  - **Restricted**: `onlyOwner`.
  - **Internal Call Tree**:
    - Calls `routerExists`.
  - **Emits**: `RouterRemoved`.
- **getRouters**
  - **Actions**:
    - Returns `routers` array.
  - **Returns**:
    - `address[]`: Router addresses.
- **setListingLogic**
  - **Parameters**:
    - `_listingLogic` (address): Listing logic contract address.
  - **Actions**:
    - Validates non-zero address.
    - Sets `listingLogicAddress`.
  - **Restricted**: `onlyOwner`.
- **setLiquidityLogic**
  - **Parameters**:
    - `_liquidityLogic` (address): Liquidity logic contract address.
  - **Actions**:
    - Validates non-zero address.
    - Sets `liquidityLogicAddress`.
  - **Restricted**: `onlyOwner`.
- **setRegistry**
  - **Parameters**:
    - `_registryAddress` (address): Registry contract address.
  - **Actions**:
    - Validates non-zero address.
    - Sets `registryAddress`.
  - **Restricted**: `onlyOwner`.
- **setBaseToken**
  - **Parameters**:
    - `_baseToken` (address): Fixed `tokenB` address.
  - **Actions**:
    - Validates non-zero address and unset `baseToken`.
    - Sets `baseToken`.
    - Emits `BaseTokenSet`.
  - **Restricted**: `onlyOwner`.
  - **Emits**: `BaseTokenSet`.
- **setGlobalizerAddress**
  - **Parameters**:
    - `_globalizerAddress` (address): Globalizer contract address.
  - **Actions**:
    - Validates non-zero address.
    - Sets `globalizerAddress`.
    - Emits `GlobalizerAddressSet`.
  - **Restricted**: `onlyOwner`.
  - **Emits**: `GlobalizerAddressSet`.
- **setBaseOracleParams**
  - **Parameters**:
    - `_baseOracleAddress` (address): Base token oracle contract address.
    - `_baseOracleFunction` (bytes4): Oracle function selector.
    - `_baseOracleBitSize` (uint16): Bit size of oracle return type.
    - `_baseOracleIsSigned` (bool): Signed/unsigned oracle return type.
    - `_baseOracleDecimals` (uint8): Oracle decimals.
  - **Actions**:
    - Validates non-zero `_baseOracleAddress`, non-zero `_baseOracleFunction`, `_baseOracleBitSize` > 0 and ≤ 256, `_baseOracleDecimals` ≤ 18.
    - Sets `baseOracleParams` with provided values.
    - Sets `_baseOracleSet` to true.
    - Emits `OracleParamsSet`.
  - **Restricted**: `onlyOwner`.
  - **Emits**: `OracleParamsSet`.

#### Listing Functions

- **listToken**
  - **Parameters**:
    - `tokenA` (address): First token in pair.
    - `oracleParams` (OracleParams): Oracle configuration for `tokenA`.
  - **Actions**:
    - Validates `baseToken`, `tokenA` (non-zero, not `baseToken`), unlisted pair, routers, logic addresses, registry, and `oracleParams`.
    - Calls `_deployPair`, `_initializeListing`, `_initializeLiquidity`, `_updateState`.
    - Stores `msg.sender` as lister.
    - Emits `ListingCreated`.
    - Increments `listingCount`.
  - **Returns**:
    - `listingAddress` (address): New listing contract address.
    - `liquidityAddress` (address): New liquidity contract address.
  - **Internal Call Tree**:
    - `_deployPair`: Calls `deploy` on `ICCListingLogic` and `ISSLiquidityLogic`.
    - `_initializeListing`: Calls `setRouters`, `setListingId`, `setLiquidityAddress`, `setTokens`, `setAgent`, `setRegistry`, `setGlobalizerAddress`, `setOracleParams`, `setBaseOracleParams` (if `_baseOracleSet`).
    - `_initializeLiquidity`: Calls `setRouters`, `setListingId`, `setListingAddress`, `setTokens`, `setAgent`.
    - `_updateState`: Updates `getListing`, `allListings`, `allListedTokens`, `queryByAddress`, `getLister`, `listingsByLister`.
  - **External Call Tree**:
    - `ICCListingLogic.deploy`.
    - `ISSLiquidityLogic.deploy`.
    - `ICCListingTemplate` setters: `setRouters`, `setListingId`, `setLiquidityAddress`, `setTokens`, `setAgent`, `setRegistry`, `setGlobalizerAddress`, `setOracleParams`, `setBaseOracleParams`.
    - `ISSLiquidityTemplate` setters: `setRouters`, `setListingId`, `setListingAddress`, `setTokens`, `setAgent`.
  - **Emits**: `ListingCreated`.
  
- **relistToken**
  - **Parameters**:
    - `tokenA` (address): First token in pair.
    - `oracleParams` (OracleParams): Oracle configuration for `tokenA`.
  - **Actions**:
    - Validates `baseToken`, `tokenA`, existing listing, lister, routers, logic addresses, registry, and `oracleParams`.
    - Calls `_deployPair`, `_initializeListing`, `_initializeLiquidity`.
    - Updates state mappings/arrays.
    - Emits `ListingRelisted`.
    - Increments `listingCount`.
  - **Returns**:
    - `newListingAddress` (address): New listing contract address.
    - `newLiquidityAddress` (address): New liquidity contract address.
  - **Internal Call Tree**:
    - Same as `listToken`.
  - **External Call Tree**:
    - Same as `listToken`.
  - **Emits**: `ListingRelisted`.
- **transferLister**
  - **Parameters**:
    - `listingAddress` (address): Listing to transfer.
    - `newLister` (address): New lister address.
  - **Actions**:
    - Validates `msg.sender` as current lister and non-zero `newLister`.
    - Updates `getLister` and `listingsByLister`.
    - Emits `ListerTransferred`.
  - **Emits**: `ListerTransferred`.
- **getListingsByLister**
  - **Parameters**:
    - `lister` (address): Lister to query.
    - `maxIteration` (uint256): Indices per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Returns paginated listing IDs from `listingsByLister`.
  - **Returns**:
    - `uint256[]`: Listing IDs.

#### View Functions

- **isValidListing**
  - **Parameters**:
    - `listingAddress` (address): Address to check.
  - **Actions**:
    - Checks `allListings` for `listingAddress`.
    - Retrieves `tokenA`, `tokenB` via `ICCListingTemplate.getTokens`.
    - Retrieves `liquidityAddress` via `ICCListing.liquidityAddressView`.
  - **Returns**:
    - `isValid` (bool): True if valid.
    - `details` (ListingDetails): Listing details.
  - **External Call Tree**:
    - `ICCListingTemplate.getTokens`.
    - `ICCListing.liquidityAddressView`.
- **queryByIndex**
  - **Parameters**:
    - `index` (uint256): Index to query.
  - **Actions**:
    - Validates index and returns `allListings` entry.
  - **Returns**:
    - `address`: Listing address.
- **queryByAddressView**
  - **Parameters**:
    - `target` (address): Token to query.
    - `maxIteration` (uint256): Indices per step.
    - `step` (uint256): Pagination step.
  - **Actions**:
    - Returns paginated listing IDs from `queryByAddress`.
  - **Returns**:
    - `uint256[]`: Listing IDs.
- **queryByAddressLength**
  - **Parameters**:
    - `target` (address): Token to query.
  - **Actions**:
    - Returns `queryByAddress` array length.
  - **Returns**:
    - `uint256`: Number of listing IDs.
- **allListingsLength**
  - **Actions**:
    - Returns `allListings` length.
  - **Returns**:
    - `uint256`: Total listings.
- **allListedTokensLength**
  - **Actions**:
    - Returns `allListedTokens` length.
  - **Returns**:
    - `uint256`: Total listed tokens.

### Additional Details

- **Relisting Behavior**:
  - **Purpose**: Replaces a token pair listing to update routers, oracle parameters, or configurations.
  - **Replacement**:
    - Deploys new `MFPListingTemplate` and `SSLiquidityTemplate` contracts.
    - Updates state mappings/arrays, keeping old listing in `allListings`.
  - **User Interaction**:
    - Old listings remain accessible via `CCOrderRouter` functions, validated by `isValidListing`.
    - New orders use `getListing[tokenA]`.
  - **Event**: `ListingRelisted`.
- **Oracle Parameters**:
  - Configures `tokenA` and base token oracle settings during `listToken`/`relistToken`.
  - Validates `oracleAddress`, `oracleFunction`, `oracleBitSize` (≤ 256), `oracleDecimals` (≤ 18).
  - Sets via `setOracleParams` and `setBaseOracleParams` in `_initializeListing`.
- **Globalizer Integration**:
  - Sets `globalizerAddress` in listings if defined.
- **Lister Tracking**:
  - Stores `msg.sender` as lister in `listToken`/`relistToken`.
  - `transferLister` updates lister status.
- **No Native ETH Support**:
  - Listings use ERC20 `tokenA` and `baseToken`.
