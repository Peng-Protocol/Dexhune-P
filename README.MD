# Overview
Dexhune-P is an Automated Market Maker (AMM) x Orderbook Hybrid, the system allows a scaled down order matching system where instead of directly matching orders, order balances are used for settlement, respecting max/min order price bounds but enforcing `impactPrice`. Price is derived from the cumulative balances of buy and sell orders, therefore each order has the potential to move the market. `impactPrice` is an AMM concept which estimates the price change an order may have after it is settled, this is important for preventing liquidity draining, where a user buys and immediately sells with profit. With `impactPrice` a user either makes no profit or loses if no one else buys.

**OMF** "Marker Foundry : Oracle Type" is a variant of **MFP** (Marker Foundry : Pairing Type), **OMF** derives a fixed price from an oracle address, calculating a price conversion to XAU (the base asset). The OMF system aims to reduce liquidity fragmentation as seen with existing price pegged assets (stablecoins, RWAs) and extreme price fluctuations, by merging the issuance/redemption mechanism with the market. 

The name **Marker Foundry** is derived from the  fictional setting of Dead Space™ where "Markers" are sources of unlimited energy but at a dark cost. In the far flung future, mankind, in desperation, replicates these markers, fulfilling a cosmic evolutionary cycle.  

## System Summary
Dexhune-P operates via `MFPAgent` or `OMFAgent` to deploy `MFPListingTemplate` or `OMFListingTemplate` and `CCLiquidityTemplate` contracts for unique token pairs. `MFPListingTemplate` or `OMFListingTemplate` serve as the order book, enabling order creation, cancellation, and settlement via `CCOrderRouter`, `MFPSettlementRouter`, and `MFPLiquidRouter`. It uses the relative presence of `TokenB / TokenA` for pricing (inverted calculation on OMF based on oracle prices), enables partial fills, tracking historical data and balances. `CCLiquidityTemplate` enables deposits, withdrawals, fee claims, and payouts, storing liquidity details and slot data. `CCLiquidityRouter` handles deposits, partial withdrawals with compensation, and fee calculations, while `MFPLiquidRouter` settles orders using liquidity balances, charging up to 1% fees. `CCGlobalizer` and `TokenRegistry` ensure cross-contract order and balance consistency. Pagination (`maxIterations`, `step`) optimizes queries, and relisting supports system upgrades.

# MFPAgent

## Description
The `MFPAgent` contract (Solidity ^0.8.2) manages deployment and initialization of token pair listings and liquidity contracts, serving as a central hub for tracking listings.

## Key Functionality
- **Listing Management**: Deploys `MFPListingTemplate` and `CCLiquidityTemplate` via `MFPListingLogic` and `CCLiquidityLogic` using `_deployPair`. Supports token-token (`listToken`) and token-native (`listNative`) pairs, with relisting (`relistToken`, `relistNative`) restricted to original listers.
- **State Tracking**: Uses `getListing`, `getLister`, `listingsByLister`, `allListings`, `allListedTokens` mapped to TokenA / TokenB token pairs and lister details.
- **Initialization**: Configures contracts with routers, tokens via `_initializeListing`, `_initializeLiquidity`.
- **Lister Management**: Supports `transferLister` and paginated queries (`getListingsByLister`, `queryByAddressView`) with `maxIterations`.
- **Validation**: Ensures non-zero addresses, unique token pairs, emits `ListingCreated`, `ListingRelisted`, `ListerTransferred`.

## Interactions
- **MFPListingLogic**: Deploys listing contracts via `deploy` with CREATE2, ensuring deterministic addresses. Can be updated by owner.
- **CCLiquidityLogic**: Deploys liquidity contracts similarly, linked to listings via `liquidityAddressView`. Can be updated by owner.

## Globalizer Integration
- **CCGlobalizer**: Optionally set via `setGlobalizerAddress`, enabling order and liquidity globalization. Listings call `setGlobalizerAddress` if configured, allowing cross-contract order tracking. Owner sets or resets this address. 

## Token Registry Integration
- **TokenRegistry**: Tracks token balances for users, integrated via `registryAddress`. Used by listings for balance queries, ensuring consistent token data across the system. Owner sets or resets this address.

## Security
- Restricts critical functions to owner.
- Uses try-catch for external calls, ensuring graceful degradation.
- Validates inputs (e.g., non-zero addresses, token pair uniqueness) to prevent errors.
- Opt-in updates via relisting or router-resets ensure that the system is upgradable and secure. If routers are updated the new addresses can be pushed via `resetRouters` on the `MFPListingTemplate` and `CCLiquidityTemplate`, restricted to the original lister. Globalizer and Token Registry cannot be changed on the listing template without relisting. Liquidity template fetches latest Globalizer and Token Registry from Agent. Templates can only be updated by relisting. Agent retains old pairs after relisting and continues to validate them, but `getListing` and other queries return only the latest listing. 

## Notes
- Supports pagination (`maxIterations`, `step`) for efficient queries.

# OMFAgent

## Description
The `OMFAgent` contract (Solidity ^0.8.2) based on `MFPAgent`, manages listings with a fixed `baseToken` (tokenB) and oracle parameters for pricing.

## Key Functionality
- **Listing Management**: Same as MFP but does not support Native listing/relisting, restricts tokenB to `baseToken`.
- **State Tracking**: Only maps tokenA to a listing, all TokenB's are `baseToken`, this affects `getListing` `getLister`, `listingsByLister`, `allListings`, `allListedTokens`.
- **Initialization**: Configures listings with oracle parameters (`oracleAddress`, `oracleFunction`, `oracleBitSize`, `oracleIsSigned`, `oracleDecimals`) and `baseToken` via `_initializeListing`.
- **Oracle Integration**: Sets `baseOracleParams` for base token pricing (e.g., `tokenAUSDPrice / baseTokenUSDPrice`).
- **Lister Management**: Same as MFP. 

## Interactions
Same as MFP.

## Security
- Same as MFP.

# MFPListingTemplate

## Description 
The `MFPListingTemplate` contract (Solidity ^0.8.2) serves as the central order book. The contract ensures secure, normalized (1e18 decimals) handling of token pairs (tokenA, tokenB), with price calculations derived from own balances. Router-only access for write functions.

## Router Interactions
- **CCOrderRouter**: Creates/cancels orders via `ccUpdate`.

- **MFPSettlementRouter**: Settles orders using listing template balances, respects order max/min price bounds with partial fills, accounts for slippage. Fetches pending orders using; (`pendingBuyOrdersView`, `pendingSellOrdersView`) and updates order states via `ccUpdate`. 

- **MFPLiquidRouter**: Settles only the caller's buy/sell orders using liquidity balances (charges a fee up to 1% depending on liquidity usage), transfers principal to liquidity template and updates liquid balances (`xLiquid`, `yLiquid`). 
Only uses listing template for fetching liquidity address via orders via `liquidityAddressView`, fetches orders using `makerPendingOrdersView` and updates order states via `ccUpdate` and transfers principal via `transactToken` or `transactNative`.

- **CCLiquidityRouter**: Manages deposits - withdrawals - fee claims - and depositor changes on liquidity contract, only uses `liquidityAddressView` on listing template. 

- **Double Impact**: When an order is created it pushes the price upwards or downwards because it adds more of a given token. This is illustrated as follows; 
`Price = TokenB Balance  / TokenA Balance`
Example; 
`200 / 100 = 2` 
Buy orders use TokenB to acquire TokenA, therefore if a buy order is created with 5 TokenB, this increases the contract's TokenB balance; 
`205 / 100 = 2.05`
When the buy order is settled this moves an equivalent amount at impact price, the impact is calculated as a simulation of post-settlement balances, in this case `2.439024390243902 ` would be moved if settled at current price, this would push the price to; 
`205÷97.56097560975609 = 2.10125` 
Which is the `impactPrice`, the order is then settled at the impact price rather than current price. 
This means for their 5 TokenB, they would be settled for `2.379535990481856` TokenB not `2.439024390243902` and definitely not `2.5` (at the original nominal price before they created the order).

## Key Interactions
- **Order Management**: Tracks buy/sell orders using `makerPendingOrders`, `pendingBuyOrdersView`, and `pendingSellOrdersView`. Stores order details in `BuyOrderCore`, `BuyOrderPricing`, `BuyOrderAmounts`, `SellOrderCore`, `SellOrderPricing`, and `SellOrderAmounts`. Updates are processed via `ccUpdate` with `BuyOrderUpdate` or `SellOrderUpdate` structs, ensuring status (cancelled, pending, partially filled, filled) and amount consistency.
- **Price Calculation**: Computes real-time prices via `prices(0)`, using own balances (`IERC20.balanceOf`) normalized to 1e18. Handles edge cases (e.g., zero balances) by returning minimal price (1).

Price effectively tracks TokenA -> TokenB. Example; LINK/USDT with a price of 35 indicates that LINK is worth 35 USDT. A buy order would require; `35 USDT / 35 = 1`, and sell; `1 LINK * 35 = 35`. 

- **Balance Tracking**: Monitors token balances (`volumeBalances`) for tokenA and tokenB, normalized for consistency, supporting real-time queries for routers.
- **Liquidity Integration**: Interfaces with `ICCLiquidityTemplate` via `liquidityAddressView` to fetch `xLiquid`, `yLiquid`, `xFees`, and `yFees`, enabling additional data queries via `CCDexlytan`.
- **Historical Data**: Maintains `HistoricalData` array and `_dayStartIndices` for tracking price, balances, and volumes at midnight timestamps, created via `ccUpdate` with `HistoricalUpdate` struct. Historical volumes are updated within `BuyOrderUpdate` or `SellOrderUpdate` using `pending` and `amountSent` changes. 
- **Security**: Restricts updates to validated routers (`routers` mapping, `routerAddressesView`) via `ICCAgent.getRouters`. Uses try-catch for external calls, emitting events (`OrderUpdated`, `BalancesUpdated`, `UpdateFailed`) for graceful degradation.
- **Token Registry and Globalizer**: Supports `TokenRegistry` for global balance storage and `Globalizer` for order globalization, ensuring cross-contract consistency.

# OMFListingTemplate

## Description
The `OMFListingTemplate` contract (Solidity ^0.8.2) based on `MFPListingTemplate` manages order book with oracle-based pricing functionality, handling token pairs (tokenA, baseToken), deriving price from a set oracle address and parameters. 

## Router Interactions
Same as `MFPListingTemplate` with a key nuance. Because `MFPSettlementRouter` and `MFPLiquidRouter` calculate impact price by calculating an order's impact on liquidity balance and projecting that onto the listing price; they create a unique restriction where even though orders do not move the price of an OMF Listing, they still have to be within certain limits to prevent overuse of opposite listing balances or liquidity balances as a whole. (Also, I didn't want to create OMF variants of the routers *without* impact price because that's unnecessary work). 

## Key Interactions
- **Price Calculation**: Differs primarily from `MFPListingTemplate` in how it determines price. It uses TokenA oracle (`oracleAddress`, `oracleFunction`) and base token oracle for `prices(0)` (`tokenAUSDPrice / baseTokenUSDPrice`), normalized to 1e18. It takes priceA and priceB to calculate a final priceC. This is because Chainlink Data Feeds typically list assets as ASSET/USD where all tokenB's are assumed to be USD. But because our base token is now pegged to XAU/USD, it is not possible to directly peg every asset, so this double conversion is used. Example;
 `LINK/USD -> XAU/USD`
 `35 / 3500 = 0.01`
This means 1 LINK is equal to 0.01 XAU. Buy orders convert tokenB to TokenA as; 
 `Order Amount / price` 
 Example; 
 `10 XAU / 0.01 = 1000 LINK`
 Whereas sells convert TokenA to TokenB; 
 `Order Amount * price`
 Example; 
 `1000 LINK * 0.01 = 10 XAU`. 
 
# CCLiquidityTemplate

## Description 
The `CCLiquidityTemplate` contract (Solidity ^0.8.2) manages liquidity allocations, enabling deposits, withdrawals, fee claims, and payouts.

### Router Interactions
- **CCLiquidityRouter**: Calls `ccUpdate` to adjust liquid balance (`xLiquid`/`yLiquid`) and liquidity slot data during deposit.  
  -  Calls transfer functions (`transactToken`/`transactNative`) during withdrawal, with  `ccUpdate` for liquid balance and slot data updates. 
  - Similar interactions for fee claims
  - Similar interactions for depositor changes. 
  - Fetches `liquidityAddressView`, `liquidityDetailsView`, `getXSlotView`, `getYSlotView`, `userXIndexView`, `userYIndexView`, `liquidityAmounts`, during various operations. 
  
- **MFPLiquidRouter**: Similar interactions as `CCLiquidityRouter `. 
  
### Storage and Updates
- **Storage**:
  - `LiquidityDetails`: Stores `xLiquid`, `yLiquid` (liquidity amounts), `xFees`, `yFees` (accumulated fees), `xFeesAcc`, `yFeesAcc` (cumulative fee snapshots).
  - `xLiquiditySlots`, `yLiquiditySlots`: Map slot indices to `Slot` structs (`depositor`, `recipient`, `allocation`, `dFeesAcc`, `timestamp`).
  - `activeXLiquiditySlots`, `activeYLiquiditySlots`: Track active slot indices.
  - `userXIndex`, `userYIndex`: Map user addresses to their slot indices.
  - `longPayout`, `shortPayout`: Store payout details for leverage markets (`makerAddress`, `recipientAddress`, `required`, `filled`, `amountSent`, `orderId`, `status`).
  - `longPayoutByIndex`, `shortPayoutByIndex`, `activeLongPayouts`, `activeShortPayouts`, `userPayoutIDs`, `activeUserPayoutIDs`: Track payout order IDs.
  - `nextPayoutId`: Tracks next payout ID, incremted during payout creation.
  - `routers`, `routerAddresses`: Track authorized routers.
  - `listingAddress`, `tokenA`, `tokenB`, `listingId`, `agent`: Store contract configuration.
- **Updates**: Handles up to (10) update types as follows; 
    - `0`: Sets `xLiquid`/`yLiquid`.
    - `1`: Adds to `xFees`/`yFees`.
    - `2`/`3`: Updates `xSlot`/`ySlot` details (`allocation`, increases or reduces `xLiquid`/`yLiquid`, `userXIndex`/`userYIndex`).
    - `4`/`5`: Changes slot `depositor`.
    - `6`/`7`: Updates slot `dFeesAcc` (Is needed during fee claims to reset a depositor's eligible fees).
    - `8`/`9`: Subtracts from `xFees`/`yFees`.
  - Payouts are created and updated via `ssUpdate`. 
  
### Key Interactions
- **Token Registry and Globalizer**: Same as `MFPListingTemplate`, but fetches addresses from `MFPAgent`.
- **Security**: Same as `MFPListingTemplate`.
  
# CCOrderRouter

## Description 
As seen in `CCListingTemplate`. 

## Interactions
- Segregates ERC20 token order creation; (`createTokenBuyOrder`, `createTokenSellOrder`,) from Native token order creation; (`createNativeBuyOrder`, `createNativeSellOrder`)
- Allows singular order cancelation orders (`clearSingleOrder`), distinct from bulk cancellation; (`clearOrders`). 

## Key Interactions
- **Token/ETH Transfers**: Validates ERC20 transfers and ETH transfers to `CCListingTemplate`, ensuring sufficient allowance and successful transfer before order execution.
- **Order Data**: Allows order creation with max/min price bounds, uses `recipient` field for user supplied order recipient. 
- **Validation**: Uses `onlyValidListing` modifier to verify listing via `CCAgent`, ensuring non-zero liquidity address and distinct token pairs.
- **Payout Settlement**: Fetches active payout IDs from `CCLiquidityTemplate` using `activeLongPayoutsView` and `activeShortPayoutsView`, settles payouts using liquidity balance via `transactToken` or `transactNative`, updates liquidity balances using `ccUpdate` at `CCLiquidityTemplate`. 
- **Data Queries**: Retrieves maker orders via `makerPendingOrdersView`, order details via `getBuyOrderCore`, `getSellOrderCore`, `getBuyOrderAmounts`, `getSellOrderAmounts`, and token details via `tokenA`, `tokenB`, `decimalsA`, `decimalsB` on `CCListingTemplate`. 

## Security
- Uses `nonReentrant` modifier to prevent reentrancy.
- Peng `ReentrancyGuard` uses `reentrancyException` with `addRenterer ` and `removeReenterer` restricted to contract owner. 
- Emits `TransferFailed` for failed transfers with reasons.
- Validates inputs (maker, recipient, amount) and token types before processing.
- Ensures normalized amounts for consistency across token decimals.

# MFPSettlementRouter

## Description
Handles order settlement for `MFPListingTemplate` using direct transfers.

## Key Interactions
- **Order Settlement**: Iterates over pending orders using `pendingBuyOrdersView`/`pendingSellOrdersView`. Processes in batches with `step` and `maxIterations` (e.g., orders [2,22,23,24,30], `step`=2, `maxIterations`=3 processes 22,23,24).
- **Order Validation**: Ensures non-zero pending amounts and status (1 or 2) in `_validateOrder`.
- **Balance Handling**: Uses `transactToken`/`transactNative` for transfers, checking post-transfer balances.
- **Update Application**: Applies updates via `ccUpdate` with `BuyOrderUpdate`/`SellOrderUpdate` structs. Updates `pending`, `filled`, `amountSent`, and `status` (2 for partial, 3 for filled) via `ccUpdate`.
- **Historical Data**: Creates `_createHistoricalEntry` for price/volume analytics.
- **Security**: Uses `nonReentrant` and try-catch, reverting with detailed reasons. Returns "No orders settled: price out of range or transfer failure" if no orders settle, ensuring graceful degradation.
- **Partial Fills**: If an order cannot be fully settled at the current price without violating the order's min/max price bounds, the system calculates `swapAmount` to determine the max amount that can be swapped within the price bounds. If `swapAmount` is zero the order is skipped.
- **Impact Price**: This represents the post-swap balances caused by the order, is used to simulate the impact the order will have on price. All settlement operations use impact price as an additional control measure, impact price cannot be above or below max/min price bounds, otherwise the order will be settled using partial fills. 

# MFPLiquidRouter

## Description 
As seen in `MFPListingTemplate` and `CCLiquidityTemplate`.

## Key Interactions
- **Liquid Settlement**: Uses liquidity balances to settle active or pending orders, restricts settlement using impact price (as seen in `MFPSettlementRouter`) for consistency. 
- **Pagination**: Limits processing up to `maxIterations` orders starting from `step`. E.g; if a pending orders array has (5) orders, "2,22,23,24,30", the user or frontend specifies a `step` "2" and `maxIterations` "3" this limits processing to orders "22,23,24". 
- **Fee Handling**: Deducts fees (up to 1% if 100% of a liquidity balance is used). Records fees in `CCLiquidityTemplate` using `ccUpdate`. 
- **Liquidity Updates**: Transfers principal to liquidity contract and adjusts `xLiquid`/`yLiquid` using normalized amounts (1e18 decimals) to ensure consistency.
- **Historical Data**: Creates `HistoricalUpdate` entries before processing orders, capturing current `volumeBalances` and `prices(0)` from `MFPListingTemplate` for accurate tracking.
- **Security**: Uses `nonReentrant` modifier to prevent reentrancy. Validates listings via `onlyValidListing` modifier.
- **Full Settlement**: Only Executes full settlement of pending or active orders, can settle orders that were previously partially settled but does not create partial settlement. 
- *Listing Balances**: The `volumeBalances` function in `MFPListingTemplate` is used  to check available token balances (`xBalance`, `yBalance`) before settling orders. It ensures sufficient balances exists to process buy/sell orders without reverting due to insufficient funds. For buy orders, it verifies `yBalance` (TokenB) is adequate for the principal; for sell orders, it checks `xBalance` (TokenA). 
- *Graceful Degradation**: The system avoids reverts for non-critical failures. Such as;
1. **No Pending Orders**: If `makerPendingOrdersView` returns an empty array or `step` exceeds the array length, the contract emits a `NoPendingOrders` event and returns without reverting.
2. **Insufficient Liquidity**: If `volumeBalances` indicates zero `xBalance` (for sell orders) or `yBalance` (for buy orders), it emits an `InsufficientBalance` event and exits without processing, avoiding a revert.
3. **Invalid Pricing**: If the order's pricing (`impactPrice`) is outside `maxPrice`/`minPrice`, it emits a `PriceOutOfBounds` event, skips the order, and continues processing others, ensuring batch operations proceed.
4. **Zero Pending Amount**: If an order's `pendingAmount` is zero, `_processOrderBatch` skips it without reverting, continuing to the next order.

# CCLiquidityRouter

## Description 
As seen in `CCListingTemplate` and `CCLiquidityTemplate`. 

## Key Interactions
- **Native Handling**: The system splits Native (`depositNativeToken`) and ERC20 (`depositToken`) deposit functions. 
- **Partial Withdrawals**: The system allows a valid depositor to withdraw a part of their allocation while retaining the rest, unclaimed fees are forfeit. 
- **Compensation**: The system allows users to specify a `compensationAmount` during withdrawals,   this is the opposite token from that which the user provided. The system validates ownership and sufficient slot allocation (primary + converted compensation). *converted compensation* is gotten by converting the stated `compensationAmount` to a relative value in the allocation token. Using the current price from `CCListingTemplate` using `prices`. The system limits withdrawals to the slot allocation the user has.
- **Fee Calculation**: Elligible fees are calculated based on liquidity and volume contribution. The contract computes `contributedFees` as `x/yFeesAcc` (total lifetime fees) minus `dFeesAcc` (slot's feeAcc snapshot). The `liquidityContribution` is the slot's `allocation` divided by total liquidity (`xLiquid` or `yLiquid`). The `feeShare` is `contributedFees` multiplied by `liquidityContribution`, capped at available fees.
- **Depositor Changes**: Allows the original depositor to transfer ownership of their slot. 
- **Slot Creation**: Each deposit uses a unique slot, old slots cannot be reused. 
- **Security**: Uses `onlyValidListing` modifier for listing validation via `CCAgent` `isValidListing`. Employs `nonReentrant` to prevent reentrancy attacks. Failures trigger events for graceful degradation.
