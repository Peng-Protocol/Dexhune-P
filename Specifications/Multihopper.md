# **Premise**
A multihop system for Dexhune-P contracts. 

## **Multihop Contract**
A contract for executing multihop routes on Dexhune-P listings. 
The contract creates orders and settles them within the same transaction, with the aim of quickly selling one asset and buying another on a different listing contract. 

### **Functions**
- Hop 

Can accommodate up to (4) listings, requires listing addresses - `maxPrice` and `minPrice` for each order and `settleType` (whether to use `settleOrders` or `settleLiquid`) 

This operation buys or sells tokens from one listing to the next as a means of  arriving at a target token. 
This behaves similar to the Uniswap router but for Dexhune-P. 

The operation settles orders on the route with either `settleOrders` or `settleLiquid` as specified by the caller. 

The recipient for any `in-between` orders is the multihop contract. While the order recipient of any `end` order is the caller's address. 

Contract uses the settled funds from a prior order to place a new order on the subsequent listing, using the "Settled" output, which is stated in the order details. 

Max and min prices for all stages are set by the caller. 

A hop can be `stalled` at any `stage` if a particular listing cannot settle an order due to illiquidity or out-of-range prices. 

The contract determines if a hop has stalled by querying `queryLatest` at the target listing contract, ensures that the order has been made correctly and stores the order ID. 

The Multihopper attempts to call `settleOrders` or `settleLiquid` respectively once it confirms an order has been placed.
It then queries the order by ID to note if the order is stalled or filled. 
It records the stalled hop - its stage and amount filled.

If the order is completely filled then the contract uses the settled amount to place an order at the next stage. 
Settled amount is stated in `Filled` in the order details. 
Updates the stalled hop if completed or if stalled again at a later stage.

Required fields; Number of listings, listing address (per listing), maxPrice (per listing), minPrice (per listing), order type (per listing), settleType (per listing), 

Note; can also just create an order on a single listing and settle it in the same transaction. 

Note; Multihopper calls order and settle functions at the appropriate router. 


- setRouter (ownerOnly)

Determines the address of the Pairing Foundry router. 

- continueHop  

Queries up to (100) stalled hops. 

Queries the ID of the stalled order to see if it has been filled then continues with the remaining stages in the hop. If not; ignores the stalled hop. 

Is triggered by each new 'hop' but can be independently called. 

...

- cancelHop 

If a hop is stalled; this function attempts to cancel the order at its current stage, only the maker address can call this function. 

When a hop is cancelled, the contract queries the order ID to determine how much was filled in the target token, then returns (to the maker) the amount filled in the target token. Whereas the unsettled principal is automatically sent back to the maker by the Pairing Foundry when the order is cancelled. 

Requires; HopID

...

- cancelAll

Cancels up to (100) stalled multihops a caller has.  

...

- queryHopByID 

All hops are stored by a fixed incremental ID, this returns the full details of a stalled hop by its fixed ID.

- queryOrdersByAddress 

Returns the IDs of orders made by a particular address. 

- queryHopHeight 

Returns the number of hops done. 
 
...

### **Data**
- router

Stores the address of the pairing foundry router. Order related functions are executed here. 


- stalledHops 

Each hop that could not be settled in a single transaction is stored as a specific data entry in the contract, along with the `stage` the hop is at and all other multihop data. 
Each stage stores; current listing - orderID - min/max price - maker address - remaining listings and principal amount. 
This allows hops to be delayed and restarted if an order cannot be immediately filled. 
