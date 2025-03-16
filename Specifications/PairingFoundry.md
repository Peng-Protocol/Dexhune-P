# **Premise**
A succinct and homogenized version of `MF-PairingFoundry.md` and `MF-FixedFoundry.md`. 

# **General**
The system is made up of (4) contracts, `MFP-Listing`, `MFP-Liquidity`, `MFP-Router`, `MFP-Agent`. 


## **MFP-Listing**

### **Data**
- routerAddress 

Stores the valid router address that can call `transact` or `update`. 

- Listing Data (9) 

Contract Name : (string),
Token-A address : (address),
Token-B address : (address),
Price : (uint256),
Liquidity Address : (address),
xBalance : (uint256),
yBalance : (uint256),
xVolume : (uint256),
yVolume : (uint256),

`Token-$ address` can be `0` indicating [NATIVE]. 

- Order Slots (14)

Slot Index: (uint256),
Maker Address: (address),
Recipient Address: (address),
Order type: (bool),
Token-A Contract: (address),
Token-B Contract: (address),
Max Price: (uint256),
Min Price: (uint256),
Principal:  (`TOKEN-0` or `TOKEN-1`),
Pending:  (`TOKEN-0` or `TOKEN-1`),
Filled: (uint256)
Created at: (uint256),
Last Settled Price: (uint256),
Order ID: (uint256),
Status: (uint256),

`Recipient Address` is where the settlement is sent, this is necessary for Multihop. 

`Status` is `Pending`, `Settled`, or `Cancelled`, Cancelled orders can No longer be settled. 

`Last Settled Price` is updated after every settlement.

`Filled` stores how much of the destination token the maker has received, is updated after every settlement - partial or whole. 


- price
  
Price is calculated as; 

`Token-0 Balance / Token-1 Balance`


If price can not be acquired then default price is lowest divisible unit of Token-1 

Whenever price is updated, the prior price becomes historical, this updates all historical data as well. 

- historicalSellVolume 

Stores entries for previous yVolume appended with index + timestamp.

- historicalBuyVolume 

Stores entries for previous xVolume appended with an index + timestamp.

- historicalPrice
  
Stores entries for previous price appended with an index + timestamp. 

- historicalMarketCap
  
Stores entries for previous mcap appended with index + timestamp. 

- Order Index
  
Stores the index numbers of all order slots, indexes are malleable - addressable and adjust their number when a slot is cleared. 

- Maker Index
  
A separate set of indexing exists for individual maker addresses. 

- Order ID
  
All orders are tagged on a third scheme that is rigid and does not change number. 

### **Functions**

- QueryOrderByIndex

This function returns the order details of a target order slot by its order index, if there is no order then the query fails. 

- queryOrderByID 

This function returns the full details of an order by its ID.

Once an order is cancelled or filled, this will still return the full details and order status. 

- QueryOrderByMaker

Returns the index numbers of up to (1000) orders made by an address. Requires `step` to query additional (1000) entries. 

This uses a separate index for each maker address. 

- queryOrderByMakerIndex 

Returns the full details of an order slot by an index number in a specific maker address's index storage. 

- queryLatest 

Returns the full details of the newest order slot. 

- queryHistoricalSellVolume 

Returns up to (1000) prior historical sell volume entries, requires `step` to query additional (1000). 

- queryHistoricalBuyVolume 

Returns up to (1000) prior historical buy volume entries, requires `step` to query additional (1000). 

- queryHistoricalPrice

Returns up to (1000) prior historical price entries, requires `step` to query additional (1000). 

- queryHistoricalMarketCap 

Returns up to (1000) prior historical mcap entries, requires `step` to query additional (1000). 

- queryYield 

Calculates and returns the real yield rate for fees collected. First gets the latest historical (x or y)volume entry and attempts to find a volume entry from 24 hours ago or the latest fee before a 24 hour cutoff point. Then calculates; 

```
Latest (x or y)volume height - oldest 24hr (x or y)volume height = total 24hr (x or y)volume

Total 24hr (x or y)Volume / 100 * 0.05 = total (x or y)Fees 

Total (x or y)Fees / total (x or y)Liquid * 100 = daily (x or y)Yield 

Daily (x or y)Yield * 365 = (x or y)APY
``` 

This function fetches (x or y)Liquid data from liquidity contract.

## **MFP-Liquidity**

### **Data**

- routerAddress 

Stores the valid router address that can call `transact` or `update`. 

- Liquidity Details

Listing : (address),
xLiquid : (uint256),
yLiquid : (uint256),
xFees : (uint256),
yFees : (uint256),

- Liquidity Slots 

depositor : (address),
xRatio : (uint256),
xAllocation : (uint256),
dVolume : (uint256),
index : (uint256),
type : (string),

depositor : (address),
yRatio : (uint256),
yAllocation : (uint256),
dVolume : (uint256),
index : (uint256),
type : (string),

`Ratios` store how much of the overall liquidity the depositor owns

- Liquidity Index
  
Stores the index numbers of all Liquidity slots, indexes are malleable - addressable and adjust their number when a slot is cleared. 

- User Index
  
A separate set of indexing exists for individual depositors. 

### **Functions**
- QueryLiquidbyIndex

Returns the details of a liquidity slot based on the index number. 

- queryLiquidByDepIndex 

Returns the details of a liquidity slot based on the depositor index number. Requires valid address. 

- QueryLiquidbyDepositor 

Returns up to (1000) Liquidity slot index numbers based on a depositor address. Requires `step` to query additional (1000) entries. 

- queryLiquidByType 

Returns up to (1000) Liquidity slot index numbers based on stated `type`, types are; `x` or `y`). Requires `step` to query additional (1000) entries. 

- QueryLiquid

Requires `isStable` (bool), returns the amount of 'TOKEN-0' or 'TOKEN-1' currently in x or y Liquid. 

- update (Router only)

Changes the details of up to (100) liquidity slots, either creating a new slot, changing depositor, reducing allocation, clearing a slot, etc. 

- QueryLiquidity

Returns the full Liquidity contract details excluding Liquidity slots. 

- transact (Router only)

Used by the router to move `TOKEN-0` or `TOKEN-1` out of the Liquidity contract to a recipient. 

- setRouter (ownerOnly)

Determines the router address. 


 
## **MFP-Router**

### **Data**

- listingAgent

Stores the listing agent contract address where validation data is updated or fetched from. Only interacts with listings that are on the listing validation, otherwise various functions fail. 

### **Functions**

- **createBuyOrder**

Requires Listing Address 
Takes Order Details
Checks decimals
Normalizes input to 18 decimals 
Checks `balanceOf` of the target listing address for token-A
Notes balance
Calls transferFrom for the order amount from the caller to the target listing 
Subtracts 0.05% from order amount to xFees 
Checks balanceOf at the listing address for token-A
Notes new listing contract balance 
Subtracts new listing balance with old balance 
Difference becomes order's principal 
Sets order details into a new order slot
Updates xVolume, adds order amount
Updates price on listing contract 
Updates xFees balance data on liquidity contract 
Updates balances on listing contract 
Note differences in call/query functions if the transacted token is `NATIVE`. 
*
Updates agent contract's validation balances and liquids.

- createSellOrder

Same as `createBuyOrder` but with sell order details, spends token-B of the listing, updates yVolume and yFees. 

- clearSingleOrder

Notes the order pending amount,
Sets the order status to `cancelled`,
Sends the pending amount to the `Recipient Address`,
Can only be called by the maker,
If there are insufficient tokens units to cover the cancellation fully then only what is available is paid, the order remains pending and the order's pending amount is subtracted by the cancelled amount. 
*
Updates validation balances and liquids

- clearOrders 

Similar to `clearSingleOrder` but searches for up to (100) pending orders a caller has and executes `clearSingleOrder` on all of them.
*
Updates validation balances and liquids
   
- settleOrders 

Requires a Listing Address 
Updates Price on listing contract 
Searches for up to (100) pending orders
Calculates their x and y pending 
Obtains the available x and y balances 
Settles as many orders that can be settled wholly 
Settles as many orders that can only be settled partially 

Buys are settled as; 

```
Order amount / price = pre output

yLiquidity - pre output = impact-y

x-liquid / impact-y = impact price

order amount / impact price = settlement-y
```

Sells are settled as;

```
Order amount * price = pre output

xLiquidity - pre output = impact-x

impact-x / y-liquid = impact price

order amount * impact price = settlement-x
```

Settlement cannot use >50% of the available liquidity 
Only settles orders whose max/min prices are met
Updates balances on listing contract
Updates Price on listing contract again
Note that all numbers in all formulas need to use some form of safe math to account for decimals
Note that all decimals should be normalized to 18
*
Updates agent validation balances and liquids

- settleLiquid 

Similar to `settleOrders` but uses x and y liquids to settle pending orders
Moves settled x principal to x liquid and vice versa.  

- depositX 

Requires a Listing Address
Finds Liquidity Address on Listing Address 
Moves Token-0 from the caller into the Liquidity Contract 

Calculates and stores Ratio as; 

`x-deposit / impact x-amount = x-ratio`

Fetches xVolume from Listing Address
Saves dVolume 
Stores allocation 
Updates Liquidity index 
Note differences in call/query functions if the transacted token is `NATIVE`. 
*
Updates validation balances and liquids

- depositY 

Similar to depositX but ... 

Calculates and stores Ratio as; 

`y-deposit / impact y-amount = y-ratio`

Fetches yVolume from Listing Address. 

- withdrawX 

Requires Listing Address
Requires withdrawal amount
Requires user index
Finds Liquidity Address on Listing Address
Fetches `x-liquidity`, `x-ratio`, `xAllocation`, `price`

Calculates output; 

`Current x-Liquidity * x-ratio = pending output`

Output cannot be greater than xAllocation
Default to nominal xAllocation as output
if output is lesser than allocation then calculate;

```
initial deposit - pending amount = deficit

deficit / price = compensation-y
```

Pays pending amount
Attempts to pay compensation-y from y-liquid or y-liquid and y-balance if y-liquid is insufficient 
If both are insufficient then withdrawal fails
Optional `withLoss` boolean
If `withLoss` true then pay withdrawal with any amount of compensation
Updates ratio using new allocation balance; 

`x-allocation / impact x-amount = x-ratio`

When a withdrawal leaves `0` allocation then the liquidity slot is erased and the liquidity index is updated
Forfeits unclaimed fees if slot is erased. 
*
Updates validation balances and liquids

- withdrawY 

Same as withdrawX but deals with Y-Type liquidity slots and their details.

Calculates output; 

`Current y-Liquidity * y-ratio = pending output`


Calculates compensation-x; 

`deficit * price = compensation-x`


- dualDeposit

Requires a Token-0 and Token-1 amount
Calls `depositX` and `depositY` with the stated amounts

- claimFees 

Requires user liquidity index number
fetches current x or y volume depending on liquidity slot type 
Fetches total x or y liquidity depending on liquidity slot type
fetches dVolume

Calculates; 

```
Current (x or y)Volume - (x or y)Volume at deposit = contributed volume

contributed volume / 100 * 0.05 = fees accrued

user Liquidity / total Liquidity = Liquidity contribution

fees accrued * liquidity contribution = output amount
```

Resets dVolume to current (x or y)Volume
Output amount cannot be greater than available fees, if greater then only pay available fees. 

- transferLiquidity 

Requires a user liquidity index number
Changes the `depositor` of stated index to a new address
Stating `0` sets this to the burn address
Can only be called by the current depositor. 
 
- setAgent 

Determines the `Listing Agent` contract.


## **MFP-Agent**
The listing agent, creates new Listing and Liquidity contracts, stores `validation` details for the router to retrieve or update.  

### **Data**

- **Listing Validation**

Listing Address ;  (address),
Listed Token(s) ;  (address),
xBalance ; (uint256),
yBalance ; (uint256),
xLiquid ; (uint256),
yLiquid ; (uint256),

### **Functions**

- queryByListing 

Returns validation slot details by the listing address. 

- queryByToken 

Returns up to (1000) validation slot index numbers by token address. Requires `step` to query additional (1000) entries. 

- querySlotByIndex 

Returns validation slot details by index number. 

- queryLatestIndex 

Returns the highest index number stored. 

- writeValidationSlot (Router Only)

Writes data into a validation slot, either creates a new slot or updates an existing one. 

- setRouter (ownerOnly) 

Determines the router address, the router can update balance and volume details in validation slots. 

- listToken 

Searches Listing validation for the exact token pair
Cannot list existing pair
Requires a `Token-0` and `Token-1` 
Stating `0` as a Token address sets the token to `NATIVE`
Creates a new listing and liquidity contract 
Verifies contracts 
Writes listing contract details
Writes liquidity contract details

# **Examples**
E1 : A token with the price of `0.25` implies that the token is worth 0.25 `TOKEN-0`. If a user puts an order to spend 250 `TOKEN-0` to buy the token, the exchange calculates; 250 / 0.25 = 1000. If they were selling (1000) `TOKEN-1` then the equation is; (1000) * 0.25 = 250. 

E2 : If a listing address has 500 `TOKEN-0` and 100 `TOKEN-1`, 500 / 100 = 5, this means the price is 5 `TOKEN-0'. If a user was buying 250 `TOKEN-0` worth of `TOKEN-1` this is; 250 / 5 = 50. Whereas if they were to sell 50 `TOKEN-1` it would be; 50 * 5 = 250.  

E3 : Assuming a token has a price of `2` and a yBalance with (100) `TOKEN-1`, while a user's order has 300 `TOKEN-0` pending, the contract settles them 50 `TOKEN-1` and updates the order to show that they have 200  `TOKEN-0` pending, while reducing the yBalance to (50), and increasing the xBalance by `100`. This is Partial settlement and also applies to settleLiquid. 

E4 : If an order with 200 `TOKEN-0` was settled for (100) `TOKEN-1` using `settleOrders`, this `TOKEN-0` amount becomes xBalance, but with settleLiquid this becomes xLiquid, vice versa for `TOKEN-1` with yBalance and yLiquid. 

E5 : If an order with 200 `TOKEN-0` was stored in xBalance, and was then settled using settleLiquid, this deducts the stored amount from xBalance and adds it to xLiquid, while deducting the respective `TOKEN-1` amount from yLiquid to settle the associated orders. Vice versa for `TOKEN-1` with yBalance and yLiquid. 

E6 & E7 : We don't talk about E6 & 7 

E8 : If a user attempted to sell (1000) `TOKEN-1` at a price of `1` but liquidity fees are active, their actual settlement will be subtracted by 0.05% equalling; 999.5, the 0.5 `TOKEN-0` fee is sent to the Liquidity contract and recorded under `yFees`. 
Orders settled partially bill fees on each settlement. 

If the user attempts to buy (1000) `TOKEN-1` in the same vein, fees are subtracted from the order before it is placed. The actual order would have a principal of 999.5 `TOKEN-0`. 

E9 : A buy order is made for a token. At the time the order is made the price is 5, their impact is 1%, once the order is placed the price goes up to 5.025, then once the order is settled the impact price is 5.05, this represents the post settlement price and is the price the user is settled at. 

With the price now at 5.05, when the user attempts to sell; if the impact is 1% again then the price they would be settled at is 5 or less and not 5.05.
 
The buyer makes no profit from trading with themselves and in fact loses due to fees or unforseen changes in balance. 

E10 : Same as E9 but after the first user buys; any number of users then also buy the token, driving the price up by 10%, now the price is 5.55. When the user attempts to sell; the price they sell at is 5.4945 due to changes that occur when their principal is added to the listing contract and pending amount is paid. Thus they made profit at the expense of the other buyer(s). 
