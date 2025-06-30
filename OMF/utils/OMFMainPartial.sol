// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.65 (Updated)
// Changes:
// - v0.0.65: Moved all interfaces (IOMFListingTemplate, IOMFLiquidityTemplate, IOMFAgent) to OMFMainPartial.sol; retained Ownable, agent, setAgent, normalize, denormalize, _getTokenAndDecimals.
// - v0.0.64: Added Ownable, agent, setAgent; inlined IOMFAgent.
// - v0.0.63: Created OMFMainPartial.sol with normalize, denormalize, _getTokenAndDecimals.

import "../imports/Ownable.sol";
import "../imports/SafeERC20.sol";

interface IOMFAgent {
    function validateListing(address listingAddress) external view returns (bool, address, address, address);
}

interface IOMFListingTemplate {
    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId; // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index; // orderId or slot index
        uint256 value; // principal or amount (normalized) or price (for historical)
        address addr; // makerAddress
        address recipient; // recipientAddress
        uint256 maxPrice; // for Pricing struct or packed xBalance/yBalance (historical)
        uint256 minPrice; // for Pricing struct or packed xVolume/yVolume (historical)
        uint256 amountSent; // Amount of opposite token sent during settlement
    }
    struct PayoutUpdate {
        uint256 index; // payout order ID
        uint256 amount; // payout amount (denormalized)
        address recipient; // payout recipient
    }
    function liquidityAddressView(uint256 listingId) external view returns (address);
    function listingIdView() external view returns (uint256);
    function token0View() external view returns (address);
    function baseTokenView() external view returns (address);
    function decimals0View() external view returns (uint8);
    function baseTokenDecimalsView() external view returns (uint8);
    function update(address caller, UpdateType[] memory updates) external;
    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external;
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    function pendingSellOrdersView() external view returns (uint256[] memory);
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory); // Returns maker's pending orders 
    function buyOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status); // Returns buy order core
    function sellOrderCoreView(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status); // Returns sell order core
    function longPayoutByIndexView() external view returns (uint256[] memory);
    function shortPayoutByIndexView() external view returns (uint256[] memory);
    function longPayoutDetailsView(uint256 orderId) external view returns (address recipient, uint256 amount);
    function shortPayoutDetailsView(uint256 orderId) external view returns (address recipient, uint256 amount);
    function buyOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function sellOrderAmountsView(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    function buyOrderDetailsView(uint256 orderId) external view returns (address maker, address recipient, uint8 status);
    function sellOrderDetailsView(uint256 orderId) external view returns (address maker, address recipient, uint8 status);
    function volumeBalanceView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function getPrice() external view returns (uint256);
}

interface IOMFLiquidityTemplate {
    struct PreparedWithdrawal {
        uint256 amountA; // Token-A withdrawal amount
        uint256 amountB; // Token-B withdrawal amount
    }
    function routersView(address router) external view returns (bool);
    function transact(address caller, address token, uint256 amount, address recipient) external;
    function deposit(address caller, address token, uint256 amount) external;
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    function claimFees(address caller, address listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external;
    function addFees(address caller, bool isX, uint256 fee) external;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
}

contract OMFMainPartial is Ownable {
    using SafeERC20 for IERC20;

    address private agent; // Stores IOMFAgent address for listing validation

    modifier onlyValidListing(address listingAddress) {
        // Validates listing address using IOMFAgent
        (bool isValid, , , ) = IOMFAgent(agent).validateListing(listingAddress);
        require(isValid, "Invalid listing address");
        _;
    }

    modifier nonReentrant() {
        // Prevents reentrant calls
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    bool private locked; // Reentrancy lock

    function setAgent(address newAgent) external onlyOwner {
        // Sets new IOMFAgent address, restricted to owner
        require(newAgent != address(0), "Invalid agent address");
        agent = newAgent;
    }

    function agentView() external view returns (address) {
        // Returns agent address
        return agent;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Normalizes amount to 18 decimals
        return decimals == 18 ? amount : amount * (10 ** (18 - uint256(decimals)));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        // Denormalizes amount from 18 decimals to token decimals
        return decimals == 18 ? amount : amount / (10 ** (18 - uint256(decimals)));
    }

    function _getTokenAndDecimals(address listingAddress, bool isBuyOrder) internal view returns (address tokenAddr, uint8 tokenDec) {
        // Fetches token address and decimals for buy or sell order
        IOMFListingTemplate listingContract = IOMFListingTemplate(listingAddress);
        tokenAddr = isBuyOrder ? listingContract.baseTokenView() : listingContract.token0View();
        tokenDec = isBuyOrder ? listingContract.baseTokenDecimalsView() : listingContract.decimals0View();
        if (tokenAddr == address(0)) {
            tokenDec = 18;
        }
    }
}