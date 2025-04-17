// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.16 (Updated)
// Changes:
// - From v0.0.15: Updated IMFPOrderLibrary.clearOrders to include caller parameter; modified clearOrders to pass msg.sender as caller (new in v0.0.16).
// - From v0.0.15: Side effect: Aligns with MFPOrderLibrary v0.0.10’s clearOrders, ensuring only caller’s orders are cleared.
// - From v0.0.14: Added support for tax-on-transfer tokens in buyOrder and sellOrder.
// - From v0.0.13: Updated to align with MFPListingTemplate’s implicit listingId.
// - From v0.0.12: Added claimFees and liquidity functions.

import "./imports/SafeERC20.sol";
import "./imports/Ownable.sol";

interface IMFP {
    function isValidListing(address listingAddress) external view returns (bool);
}

interface IMFPListing {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }
    function update(address caller, UpdateType[] memory updates) external;
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function liquidityAddresses() external view returns (address);
}

interface IMFPOrderLibrary {
    struct BuyOrderDetails {
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct SellOrderDetails {
        address recipient;
        uint256 amount;
        uint256 maxPrice;
        uint256 minPrice;
    }
    struct OrderPrep {
        uint256 orderId;
        uint256 principal;
        uint256 fee;
        IMFPListing.UpdateType[] updates;
        address token;
        address recipient;
    }
    function prepBuyOrder(
        address listingAddress,
        BuyOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory);
    function prepSellOrder(
        address listingAddress,
        SellOrderDetails memory details,
        address listingAgent,
        address proxy,
        uint256 orderId
    ) external view returns (OrderPrep memory);
    function executeBuyOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;
    function executeSellOrder(
        address listingAddress,
        OrderPrep memory prep,
        address listingAgent,
        address proxy
    ) external;
    function clearSingleOrder(
        address listingAddress,
        uint256 orderId,
        bool isBuy,
        address listingAgent,
        address proxy
    ) external;
    function clearOrders(
        address listingAddress,
        address listingAgent,
        address proxy,
        address caller
    ) external;
}

contract MFPProxyRouter is Ownable {
    using SafeERC20 for IERC20;

    address public listingAgent;
    address public orderLibrary;

    constructor() {}

    function setListingAgent(address _listingAgent) external onlyOwner {
        require(listingAgent == address(0), "ListingAgent already set");
        listingAgent = _listingAgent;
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        require(_orderLibrary != address(0), "Zero address");
        orderLibrary = _orderLibrary;
    }

    function buyOrder(address listingAddress, IMFPOrderLibrary.BuyOrderDetails memory details) external payable {
        require(orderLibrary != address(0), "Order library not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");

        IMFPOrderLibrary.OrderPrep memory prep = IMFPOrderLibrary(orderLibrary).prepBuyOrder{value: msg.value}(
            listingAddress, details, listingAgent, address(this), block.number
        );
        IMFPOrderLibrary(orderLibrary).executeBuyOrder(listingAddress, prep, listingAgent, address(this));
    }

    function sellOrder(address listingAddress, IMFPOrderLibrary.SellOrderDetails memory details) external payable {
        require(orderLibrary != address(0), "Order library not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");

        IMFPOrderLibrary.OrderPrep memory prep = IMFPOrderLibrary(orderLibrary).prepSellOrder{value: msg.value}(
            listingAddress, details, listingAgent, address(this), block.number
        );
        IMFPOrderLibrary(orderLibrary).executeSellOrder(listingAddress, prep, listingAgent, address(this));
    }

    function clearSingleOrder(address listingAddress, uint256 orderId, bool isBuy) external {
        require(orderLibrary != address(0), "Order library not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");

        IMFPOrderLibrary(orderLibrary).clearSingleOrder(listingAddress, orderId, isBuy, listingAgent, address(this));
    }

    function clearOrders(address listingAddress) external {
        require(orderLibrary != address(0), "Order library not set");
        require(IMFP(listingAgent).isValidListing(listingAddress), "Invalid listing");

        IMFPOrderLibrary(orderLibrary).clearOrders(listingAddress, listingAgent, address(this), msg.sender);
    }
}