# **Premise**
The Multihopper Frontend app. 

## **General**
The frontend is made up of (3) pages; 
- Multihop Interface 
- Liquidity Menu 
- List Menu 

## **Page 1 : Multihop interface**
### **Multihop Routes**
Routes are calculated depending on the number of listings the frontend needs to go through to acquire the desired token. 

Frontend acquires listings by querying 'queryByToken' at the Listing Agent contract using the stated Token-A and Token-B. Frontend determines required route by performing the following; 

- Single Hop
  
Find two listings that have Token-A and Token-B where each listing has the same paired asset as Token-C. 

If none then return error pop-up; "No feasible routes found! Contact the token's deployer for assistance!" 

(Note; if Token-A and Token-B have a listing together then no hop is required, frontend executes a regular order). 


All route data is cached locally and can be reused. 


Once all routable listings are found and cached the frontend calculates the conversion price. 


- Single Hop Conversion; 

This calculates how much Token-B the user can expect to get out. 

If Token-A is Token-0 in the listing, calculates an output amount in - 1h as; 

```
Token-A amount / minPrice-A = Token-C output

if not, then; 

Token-A amount * maxPrice-A = Token-C output
```

If Token-C is Token-0 in the listing, then; 

```
Token-C output / minPrice-C = Token-B output

if not, then; 

Token-C output * maxPrice-C = Token-B output 
 ```
...

Once a route is determined, the frontend pushes a transaction to execute the required orders via the multihop contract. 

...

Slippage along route should be the same, if any order could cause a price change that goes above the user's max price or below the user's min price, then the frontend will present a pop-up that reads; "Warning! Price impact is higher than your price range, your order will remain pending until it can be filled at your preferred price range. If you still want an instant settlement; use the (slippage button image) button to change your order price range or click 'find new route' to attempt to find a new route to your desired asset". 

- Find New Route Button 

Located on the price impact on routes pop-up, prompts the frontend to attempt to find a new route by querying more listings, using additional `steps` where needed on the Listing Agent contract. 

If no route can be found that doesn't cause too much price impact, frontend presents a temporary pop-up that reads; "Impact still too high, change order size or increase slippage". 

...

Price impact on buys is measured using the following; 

```
Token-0 order amount + Token-0 xBalance = Token-0 impact 

Token-0 impact / Token-1 yBalance = impact price 

Impact price / current price * 100 - 100 = price impact percent
```
 

Whereas on sell orders; 

```
Token-1 order amount + Token-1 yBalance = Token-1 impact 

Token-0 xBalance / Token-1 impact  = impact price 
```

Impact price should not be greater than the user's max price or lower than the user's min price, else prompt error and highlight amount in red. 

Impact is calculated using the projected output of each hop. 

...

### **USD Price Conversion **
If the listing is to LUSD or USDT or USDC, then the price is cached as $`price`. 

If the listing's TOKEN-0 is `NATIVE` or wrapped `NATIVE` or wETH, then the frontend queries price via Chainlink data feeds and calculates;  

Listing Price * Chainlink price = Token price USD 

Conversely, If the listing's Token-1 is `NATIVE` or wrapped `NATIVE` or wETH, then; 

Listing Price / Chainlink price = Token price USD 

If the listing is not to any of these assets then it doesn't use USD price Conversion. 

**Order Type**

The frontend determines order type for each listing on the route based on what token the user/multihop should have at that point in the route vs what token it wants to acquire. 

If the user/multihop currently has Token-0 then the order type for the subsequent listing is (buy), but if they have Token-1 then the order type is (sell). 

**Settle Type**

The frontend determines which settlement type (settleOrders or settleLiquid) to use based on if the x or y balances have more than the x or y liquids, uses the storage with the most assets. 

## **Page Content**
UI and associated logic for the page. 

- **1a ; Wallet Connect Button** 

You do know how wallet connect works, right? 

- **1b ; Dexhune Logo**

Is DXH logo, is present on every page.

- **1c ; Multihop Menu**

Comprises 1d to 1n.

- **1d ; Token-A Ticker**

Displays up to 4 letters of a token's ticker, else uses ellipses for >5 letter ticker symbols. 
Starts as a field titled "Token Name - Symbol or Address" if no token is inserted. 
Can be clicked on to reveal field again for setting new Token-A. 

If a name or symbol is *entered* (user must deselect the field or hit `enter`), the frontend queries the token name or symbol at the `Dexhune Markets` Contract. 

If no token has the name or symbol, this presents a temporary pop-up that reads; "Token not found! Ensure the name or symbol is properly typed. If the token is listed but not recognized, insert the contract address instead."

Once the token is determined, the frontend queries the address at the Listing Agent using `queryByToken`, if not found then returns a temporary pop-up that reads; "Token not listed!". 

If the token is found then this caches the first (1000) listings the token has. 

If the user types `POL`, then the frontend uses the native token as Token-A. 

Default Token-A entry is `NATIVE`. 

User can specify a token contract address but it must be listed on the Listing Agent.

- **1e ; Token-A Amount**

Displayed directly next to the ticker, is a field that allows the user to state the amount they wish to exchange. 

Titled; "Amount". 

If the Token-A and B have a direct listing, and if Token-A is Token-0 on the listing, calculates an output amount that is displayed in `Token-B Amount` as; 


`Token-A amount / price = Token-B Amount`

However, if Token-A is Token-1 in the listing, calculates an output as; 

`Token-A amount * price =  Token-B Amount`


If Token-A and B do not have a direct listing, but both have listings of some sort, the frontend first fetches the x - y balances and liquids, caches them before calculating a multihop route and conversion. 



- Token-A Balance  

Queries and displays the user's Token-A Balance. 

- Max 

A button that changes `Token-A Amount` to the user's max balance of a given token. 



- **1f ; Switch Button**

Switches the tokens in `Token-A Ticker` and `Token-B Ticker`.

- **1g ; Slippage Button**

(Be creative with the button image)
Opens a closeable slippage menu as follows;

- maxPrice 

A field for setting max price, by default; continuously updates to 2% greater than current price unless a custom max price is set. Fetches price every 10 seconds when this menu is open.

- minPrice 

A field for setting min price, by default; continuously updates to 2% lesser than current price unless a custom min price is set. Fetches price every 10 seconds when this menu is open.

(Note that these are text fields for stating exact min/max price).

- Max Slippage Slider 

Sets the default max price percent, is reset whenever the app is reopened. 

- Min Slippage Slider 

Same as `Max Slippage Slider` but for min price percent. 

(Note; Multihop can only work with slippage percent and not specific max/min prices. The frontend calculates multihop prices using a percentage of the current price for listings on the route) 

... 

- Slippage Help 

Displays a closeable pop-up that reads; "All orders are range orders, use this menu to determine what price range your order can be executed at. Your order will not revert if the price changes suddenly, rather it will remain pending until your preferred price is met!". 

- **1h ; Token-B Ticker**

Same as `Token-A Ticker` but when the token is found; the frontend attempts to find a listing on the validation contract that has the same Token-0 and Token-1. If there is no direct listing then the frontend prepares for multihop. 

- **1i ; Token-B amount** 
Same as `Token-A Amount` but if typed into; updates the input in `Token-A Amount`. 

- Token-B Balance 

Queries and displays the user's Token-B Balance. 

...

- **1j ; Swap Button**

Pushes a transaction to approve the Token-A amount if not approved. 
(Text on button displays `approve` if not approved). Otherwise pushes a transaction for multihop or single listing order + settlement, both via the multihop contract. 

If there is insufficient x or y balance or liquid in the target listing(s), the frontend presents a pop-up that reads; "Warning! This pool is not liquid enough to settle your order instantly! If you proceed your order will remain pending until your preferred price range is met, you can cancel this order later but with some caveats - you will lose to fees (0.05 - 0.1%) and if the listing does not have enough tokens to pay your order cancellation; you will have to wait until it becomes more liquid".

This error also occurs if the user's impact price is outside their max/min price range.

This error pop-up is followed by two buttons that read "Proceed" and "Cancel", the first pushes the transaction normally, the second aborts it.  

- **1k ; Order Summary**

A drop-down menu which comes out after `Swap Button` is clicked. 

This presents additional details about the user's order; 

- Token-A USD Price 

Displays Token-A's USD Price from its top listing address. Titled `TOKEN-A / USD`.
This section updates every 10 seconds. 

- Token-B Price

Displays Token-B's USD Price from its top listing address. Titled `TOKEN-B / USD`.
This section updates every 10 seconds. 

- Listing Balances 

Queries and displays the listing's total xBalance and yBalance, alongside xLiquid and yLiquid, these are displayed with the respective token tickers and are segregated based on balance type. 
This section updates every 10 seconds. 

**Unexecuted orders**

Displays all unexecuted orders the user may have made, is queried each time the user connects their wallet or opens the app with their wallet connected.
This uses `queryOrderByMaker` to get the user's index numbers, then `queryOrderByMakerIndex` with each individual index number to get the details of each order. 

- Order Status 

Displays text that reads; "pending" in a red rectangle next to each order. 

This section updates every 30 seconds, if a previously unexecuted order is filled this changes to text that reads; "filled" in a green rectangle.

- Multihop Progress 

A node progress bar that shows which stage the multihop is at, depending on the number of listings it has to go through. 

- Amount Outstanding 

This displays the expected output of the order and how much has been settled.  
Panel turns green once the order is filled.

 ...

- Cancel Button 

Displayed next to each pending order, if the order is a stalled multihop, this pushes 'cancelHop' with the order details. 

If the order is on a single listing; this pushes 'clearSingleOrder' at the respective controller.

If the listing's x or y balance is lower than the user's order amount, the frontend will present a pop-up that reads; "This listing only has (Balance) token units, your order can only be returned (Order Amount - Balance) at this time, note that you can cancel this amount and get the rest later if there is enough balance".

Above pop-up has two buttons that read "Proceed" and "Abort", the first pushes the transaction normally and the second aborts it. 

If the listing's (x or y)Balance has "0" token units then the above pop-up reads; "The listing has insufficient token units at this time, your order cannot be returned until more liquidity enters the listing through buys or sells, consult the documentation for more information". 

(Note; the frontend caches all order IDs and uses them when an individual order needs to be cleared). 

...

- Cancel All Button

If the orders are stalled multihops; this pushes; `cancelAll` at the Multihopper contract. 
While pending regular orders use `clearOrders` at the respective router. 

... 

- Settle Button

Displayed next to each pending order, only appears if the respective x or y `balance` or `liquid` at a multihop stage has enough assets to settle the order and if the order's stated price range is met. 
Uses 'continueHop' on the Multihopper contract. 
Updates data on balances and order status every 30 seconds. 

Uses `settleLiquid` or `settleOrders` if the order is on only one listing, chooses settle type based on which balance type has more tokens. 



- Fee Percent and Amount 

This calculates how much fees the user incurs. 
"n" being the number of listings used in the route. 

0.05 * n = fee percent 

Gives disclaimer `Fees may vary`. 

Fee amount is calculated as; 

Token-A amount USD Value / 100 * Fee Percent = fee amount



- Order Cost (USD) 
Displays Token-A amount USD Value if available. 



- Order Impact 
Shows the impact percent the order will have on each listing. 



(Note; All previously unexecuted orders that become executed are only cleared from this section when a new order is placed). 

(Note; each order entry has a brief and expanded version. Each unexecuted order can be expanded by clicking on them). 

...

- **1l ; List Button**

Opens the listing menu page. 

- **1m ; LP Button**

Opens the liquidity menu page. 

- **1n ; Chart button**

Has a "chart" symbol. Extends a panel above the swap menu to present a small price chart with - 1 week timeframe - current price - current marketcap and balances/liquids. Based on `Order-Flow` in Page 2. 

Clicking the chart takes the user to Page 2 with a query string to open `Order-Flow`. 

...

- **1o ; Links**

Text links to "Telegram", "GitHub", "Contract", "Projects". 

...

### **Page 2 : Liquidity Menu**
A menu for managing or visualizing liquidity. 

- **2a ; Connect Wallet Button**

Initiates wallet connect.

- **2b ; Dexhune Logo**

Is Dexhune logo. 

- **2c ; Positions Menu**

Token address - Name or Ticker
Allows the user to insert a token address - name or ticker to interact with, frontend searches the listing agent when this field is deselected or if the user hits "enter". Frontend returns all results in a closeable "results" pop-up menu.

(Note that "Liquidity Positions" onwards is hidden when this page is opened, and only expands when a listing is selected). 

Frontend recognizes a stated name/ticker is not an address by its length, queries up to (1000) listings on the validation contract.

Presents pop-up that reads; "Loading..." and prevents all interaction with the frontend until results are ready. 

"Results" menu returns a set of possible listings by their names, these names are links that can be clicked on to open "Liquidity Positions" with the intended listing address.  

- Search Button

Initiates search with details in "Positions Menu". 

- **2d ; Liquidity Positions**

Shows details from liquidity slots on the target listing contract, presents the token ticker up to 4 characters, presents the paired amount as TOKEN-0/TOKEN-1, all positions higher than (5) digits are formatted in scientific notation. This field lastly presents unclaimed fees. 

...

Liquidity positions can be clicked to highlight and prepare them for "Claim Fees" or "Withdraw".

- Yield Rate 

Queries and displays yield rate. 

- **2e ; Claim Fees**

Pushes a transaction to claim fees on a liquidity position highlighted in "Liquidity positions", index numbers for liquidity slots are stored by the frontend and updated before any transaction is pushed. 

- **2f ; Scroll Bar**

Allows the user to scroll up and down on their liquidity positions. 

- **2g ; Withdraw**

Pushes a transaction to withdraw the liquidity position highlighted in "Liquidity Positions". 

- **2h ; Deposit Menu Button**

Presents "Deposit Menu", temporarily hides "Positions Menu" until deposit menu is closed.

- **2i ; Order-Flow Button**

Changes "Liquidity Positions" to query and present the total [TOKEN-0] and [TOKEN-1] liquidity balance, along with x and y balances.  
Displays as opposing bar charts, updates every 30 seconds when open. 

Also queries and presents all pending orders for the listing. 
Returns order type, amount, and maker's address shortened. 
Displays as order flow chart, buys on left, sells on right. 
Updates every 30 seconds. 


- **Price Chart Button**

Presents a temporary pop-up over this pop-up that says "Warning! This menu is very hardware intensive! More data requires more compute! This frontend is running on your device, not a server!" 

Stores cookies on the user's device to never show the warning again. 

In addition to `Order-Flow`, this presents a price chart for the past day using "queryHistoricalPrice" and queries until it hits a price with a timestamp older than 00:00 of the current day, displays all price entries from after 00:00. 

- 1 day button 

Prompts the frontend to query and present all price data for the past day if not already displaying daily chart (all price data is cached). 

- 1 week button 

Same as "1 day button" but for 1 week. 

- 1 month button 

Same as "1 day button" but for 1 month. 

- 1 year chart 

Same as "1 day button" but for 1 year. 

- 10 years chart

Same as "1 day button" but for 10 years. 

- 100 years chart 

Same as "1 day button" but for 100 years. 



- 1 minute candles 

Prompts the frontend to display points on the chart as 1 minute candles. 

The chart arranges entries under a timeframe, the timeframe can be broken up into sections called "candles". 

Each candle represents price updates (or lack of) that occured within their duration. 

If no price changes occured then each subsequent candle is flat. 

Uses the price update closest to the end of the candle duration. 

Each candle has a "wick", which is the highest or lowest price that occured during the duration, while the "body" of the candle represents the change in price since the duration's "open" and "close". 

- 15 minute candles 

Same as "1 minute candles" but for 15 minutes. 

- 30 minute candles 

Same as "1 minute candles" but for 30 minutes. 

- 1 hour candles 

Same as "1 minute candles" but for 1 hour.

- 1 day candles 

 Same as "1 minute candles" but for 1 day. 

- 1 week candles 

Same as "1 minute candles" but for 1 week. 

- 1 month candles

Same as "1 minute candles" but for 1 month. 

- 1 year candles

Same as "1 minute candles" but for 1 year. 



(Note; if the candle duration exceeds the time frame then timeframe must be extended to match candle duration)

- Scroll bar 

A horizontal scroll for moving around the chart. 

- Historical volume 

Queries the listing's historical volume for the stated time period and arranges it to approximate points against price candles. Can return "0".
Is displayed as a 2-variable stacked bar chart. 

- Time stamp 

Displayed at intervals at the bottom of the chart, displays various time segments depending on the timeframe selected. 

- Current Market Cap

Fetches the latest marketcap entry using `queryHistoricalMarketCap` at the listing contract, takes the highest index data. 

- Market Cap Chart Button 

Replaces price data with historical marketcap data. 

- **2j ; Help button**

Presents "Help Menu", temporarily hides "Positions Menu" until help menu is closed.

- **2k ;  Close Button**

Closes this page, returns to Multihopper page. 

- **2l ; Deposit Menu**

 - Amount-A field

Allows the user to type or paste an amount to deposit, amount is parsed to uint256 based on the number of decimals the token has.

- Amount-B field 
Allows stating a deposit amount if "dual deposit" is selected. 

- Deposit type 

Determines if the user is depositing Token-0 or Token-1 or "dual deposit". 

- Deposit Button 

Pushes a transaction for `depositX` or `depositY` depending on the deposit type. Presents a pop-up that reads; "Amount not approved! Approve First!" and instead pushes a transaction to approve the amount before pushing the actual deposit. 

Pushes a transaction to deposit the stated amount 

- Close Button

Closes the Deposit Menu pop-up. 


- **2m ; Help Button**

Presents a simple help text pop-up;

"Insert the listing address - token name or ticker and click "Search" to begin.
"Claim" allows you to claim any fees on your top position. 
"Withdraw" allows you to withdraw your liquidity. 
"Deposit" allows you to deposit liquidity.
"Order-Flow" displays total Liquidity and pending orders."

Has a close button. 

- ** 2n ; Orders Button** 

Displays "Orders menu".

- **Orders Menu**

- Price 

Returns current price, is updated every 5 seconds when this menu is open. 

-  Orders 

Fetches and displays all orders created by the user.
Displays their; price and principal/pending.

- Cancel All Button 

Displayed at the top right, allows the user to call "clearOrders". 

- Cancel Order Button 

Displayed next to each order, allows the user to call "clearSingleOrder". 
Requires order ID.

- Close menu button 

Closes orders menu. 

...

- **2o ; Other Pages Button**

Shows text pop-up with links to;
"DAO" - "Markets" and "Landing". 
Has close button. 

- **2p ; Close Page 2 Button**

 Returns the user to the trade menu page. Reads "Close"



### **Page 3 : Listing**

- **3a ; Connect Wallet Button**

Initiates wallet connect. 

- **3b ; Dexhune Logo**

Is Dexhune logo. 

- **3c ; Listing Options**

Allows the user to specify what details their token should have. 

- Token-A Address

Specifies Token-A 

- Token-B Address 

Specifies Token-B 

- **3d ; List Button**

Pushes a transaction with the listing details and contract address to the respective listing agent. 

- **3e ; Help Button**

Presents a pop-up that says "Use this menu to list new tokens to Dexhune!". 

- **3h ; Close Page 3 Button**

Directs to Multihop Interface page. 
