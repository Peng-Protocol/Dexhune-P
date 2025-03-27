# **Premise**
A multihop system for Dexhune-P contracts. 

## **Multihop Contract**
A contract for executing multihop routes on Dexhune-P listings. 
The contract creates orders and settles them within the same transaction, with the aim of quickly trading one asset and acquiring another on a different listing contract. 

### **Functions**
- Hop 

Can accommodate (4) listings max, requires listing addresses - `maxPricePercent` and `minPricePercent` for each order and `settleType` (whether to use `settleOrders` or `settleLiquid`) 

This operation buys or sells tokens from one listing to the next as a means of  arriving at a target token. 
This behaves similar to the Uniswap router but for Dexhune-P. 

The multihopper acquires and stores the order ID from the target listing by using `makerPendingOrders` at the listing address and getting the highest ID - the most recently created. 

The operation settles orders on the route with either `settleOrders` or `settleLiquid` as specified by the caller. 

The recipient for any `in-between` orders is the multihop contract. While the order recipient of any `end` order is the caller's address. 

Contract uses the settled funds from a prior order to place a new order on the subsequent listing, using the "Settled" output, which is stated in the order details. 

Max and min prices for all stages are calculated by the multihopper using the impact price percent set by the caller. 

A hop can be `stalled` at any `stage` if a particular listing cannot settle an order due to illiquidity or out-of-range prices. 

The Multihopper attempts to call `settleOrders` or `settleLiquid` respectively once it confirms an order has been placed.

It then queries the order by ID using `buyOrders` or `sellOrders` to note if the order is stalled or filled. 
It records the stalled hop and its stage.

If the order is completely filled then the contract uses the settled amount to place an order at the next stage. 

Settled amount is stated in `Filled` in the order details. 
Updates the stalled hop if completed or if stalled again at a later stage.

Required fields; Number of listings, listing address (per listing), maxPricePercent (per listing), minPricePercent (per listing), startToken, endToken, settleType. 

"startToken" and "endToken" determine much of the logic of the hop, based on the startToken the multihopper decides to buy or sell at the first listing if the listing has `startToken` as token-A or token-B. 
It then determines orders on subsequent listings based on which token it recieved and the position of said token in the next stage's pair. 

The multihopper has to calculate the end token for each stage in trying to reach the final ens token of the hop. This could fail due to out-of-gas errors if too many listings are specified or fail if the listings provided do not match the required tokens to reach the hop's endToken. 

The multihopper can determine routes that are shorter than the provided listings and simply ignore any extraneous routes to reach the hop's endToken. 

Note; can also just create an order on a single listing and settle it in the same transaction if only one listing is specified. Fails if the start or end tokens do not match the listings or their order of operation. 

Note; Multihopper calls order and settle functions at the appropriate router. 


- setRouter (ownerOnly)

Public, determines the address of the MFP router. 

- continueHop  

Queries up to (20) stalled hops. 

Queries the ID of the stalled order to see if it has been filled then continues with the remaining stages in the hop. If not; ignores the stalled hop. 

Is triggered by each new 'hop' but can be independently called. 



- cancelHop 

If a hop is stalled; this function attempts to cancel the order at its current stage, only the maker address can call this function. 

When a hop is cancelled, the contract queries the order ID to determine how much was filled in the target token, then returns (to the hop maker) the amount filled in the target token. Whereas the unsettled principal is sent back depending on the stage of the order. If it is an end stage order then the principal is automatically sent back to the hop maker by the MFP router when the order is cancelled - because the recipient of all end stage orders is the hop maker. 
But if it is not an end stage order then the multihopper is the recipient and therefore must send the unsettled principal to the hop maker. 

Requires; HopID



- cancelAll

Cancels up to (100) stalled multihops a caller has.  


### **Data**
- hopID 

All hops are stored by a fixed incremental ID, this mapping is public and returns the full details of a stalled hop by its fixed ID.

- hopsByAddress 

An array that stores the hopID numbers associated with a given address. Is public and queryable  

- totalHops

An array that stores the number of hops done. Is public and queryable  
 

- router

Stores the address of the pairing foundry router. Order related functions are executed here. 


- stalledHops 

Each hop that could not be settled in a single transaction is stored as a specific data entry in the contract, along with the `stage` the hop is at and all other multihop data. 
Each stage stores; current listing - orderID - min/max price Percent - Hop Maker address - remaining listings and principal amount. 
This allows hops to be delayed and restarted if an order cannot be immediately filled. 
