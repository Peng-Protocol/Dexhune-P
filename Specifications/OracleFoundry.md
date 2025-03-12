# **Premise**
A version of `PairingFoundry` but for creating oracle priced assets. 

# **General**
The only notable difference is listing data and oracle related functions. The associated contracts are called; `OMF-Listing`, `OMF-Liquidity`, `OMF-Router`, `OMF-Agent`. 

---

## **OMF-Listing**

### **Data**

- Listing Data (11) 

Contract Name : (string),
Base Token : (address), 
Token-B address : (address),
Price : (uint256),
Oracle Address : (address), 
Oracle Decimals : (uint256),
Price Function : (string), 
Liquidity Address : (address),
xBalance : (uint256),
yBalance : (uint256),
xVolume : (uint256),
yVolume : (uint256),

`Price Function` defines what read function or data entry to query at the oracle address, this either queries or fetches. 

`Price` is normalized to 18 decimals from how ever many the oracle uses. 

`Base Token` is `Link Dollar`, is set by the agent during deployment. 

---

- price 
Price is derived from the oracle. 

## **OMF-Agent**

### **Data**

- Base Token 

Stores the address of the base token.

### **Functions**

- listToken 

Searches Listing validation for the exact token pair,
Cannot list existing pair,
Requires a Token-1,
Token-1 cannot be `NATIVE`,
Requires an oracle address, oracle decimals and oracle function,
Fetches the supply of Token-1, 
Attempts to bill the caller 1% of the token supply, 
Sends billed amount to `taxCollector`, 
Creates a new listing and liquidity contract,
Verifies contracts,
Writes listing contract details,
Writes liquidity contract details,

- setBaseToken (ownerOnly) 
Determines the base token all listings will use. 

