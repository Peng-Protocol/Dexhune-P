// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.5
// Changes:
// - Renamed tokenA to token0, tokenB to baseToken (Token-0 to Token-1).
// - Renamed xLiquid to xBalances for clarity, kept yBalances.
// - Added xVolume and yVolume, added updateVolume function.
// - Inlined IOracle interface for getPrice().

import "./imports/SafeERC20.sol";

contract OMFListingTemplate {
    using SafeERC20 for IERC20;

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
        uint256 maxPrice;
        uint256 minPrice;
    }

    struct Order {
        address makerAddress;
        address recipientAddress;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 pending;
        uint256 filled;
        uint256 timestamp;
        uint256 blockNumber;
        uint8 status; // 0 = inactive, 1 = active, 2 = settled
    }

    address public token0;    // Token-0 (listed token)
    address public baseToken; // Token-1 (reference token)
    address public oracle;
    uint8 public oracleDecimals;
    uint256 private orderCounter;
    mapping(uint256 => Order) public buyOrders;
    mapping(uint256 => Order) public sellOrders;
    mapping(uint256 => address) public liquidityAddresses;
    uint256 public xBalances; // Token-0 balances
    mapping(uint256 => uint256) public yBalances; // Token-1 balances
    uint256 public xVolume; // Token-0 volume
    uint256 public yVolume; // Token-1 volume
    uint256[] private pendingBuyOrderIds;
    uint256[] private pendingSellOrderIds;

    constructor(address _token0, address _baseToken, address _oracle, uint8 _oracleDecimals, address _liquidity) {
        require(_token0 != address(0) && _baseToken != address(0), "Invalid tokens");
        require(_oracle != address(0), "Invalid oracle");
        require(_liquidity != address(0), "Invalid liquidity address");
        token0 = _token0;
        baseToken = _baseToken;
        oracle = _oracle;
        oracleDecimals = _oracleDecimals;
        liquidityAddresses[0] = _liquidity;
    }

    function nextOrderId() external returns (uint256) {
        orderCounter++;
        return orderCounter;
    }

    function getPrice() external view returns (uint256) {
        // Inline IOracle interface
        (bool success, bytes memory returnData) = oracle.staticcall(abi.encodeWithSignature("latestPrice()"));
        require(success, "Price fetch failed");
        uint256 price = abi.decode(returnData, (uint256));
        return oracleDecimals == 8 ? price * 1e10 : price; // Scale to 18 decimals
    }

    function update(address caller, UpdateType[] memory updates) external {
        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 1) { // Buy order
                buyOrders[u.index] = Order(
                    caller, u.recipient, u.maxPrice, u.minPrice, u.value, 0, block.timestamp, block.number, u.value > 0 ? 1 : 0
                );
                if (u.value > 0) pendingBuyOrderIds.push(u.index);
                else removePendingBuyOrder(u.index);
            } else if (u.updateType == 2) { // Sell order
                sellOrders[u.index] = Order(
                    caller, u.recipient, u.maxPrice, u.minPrice, u.value, 0, block.timestamp, block.number, u.value > 0 ? 1 : 0
                );
                if (u.value > 0) pendingSellOrderIds.push(u.index);
                else removePendingSellOrder(u.index);
            } else if (u.updateType == 0) { // Balance update
                if (u.addr == token0) xBalances += u.value;
                else if (u.addr == baseToken) yBalances[0] += u.value;
            }
        }
    }

    function transact(address caller, address token, uint256 amount, address recipient) external {
        if (token == token0) {
            require(xBalances >= amount, "Insufficient Token-0 balances");
            xBalances -= amount;
        } else if (token == baseToken) {
            require(yBalances[0] >= amount, "Insufficient Token-1 balances");
            yBalances[0] -= amount;
        }
        IERC20(token).safeTransferFrom(caller, recipient, amount);
    }

    function updateVolume(bool isX, uint256 amount) external {
        if (isX) xVolume += amount;
        else yVolume += amount;
    }

    function pendingBuyOrdersView() external view returns (uint256[] memory) {
        return pendingBuyOrderIds;
    }

    function pendingSellOrdersView() external view returns (uint256[] memory) {
        return pendingSellOrderIds;
    }

    function listingVolumeBalancesView() external view returns (uint256, uint256, uint256, uint256) {
        return (xBalances, yBalances[0], xVolume, yVolume);
    }

    function removePendingBuyOrder(uint256 orderId) internal {
        for (uint256 i = 0; i < pendingBuyOrderIds.length; i++) {
            if (pendingBuyOrderIds[i] == orderId) {
                pendingBuyOrderIds[i] = pendingBuyOrderIds[pendingBuyOrderIds.length - 1];
                pendingBuyOrderIds.pop();
                break;
            }
        }
    }

    function removePendingSellOrder(uint256 orderId) internal {
        for (uint256 i = 0; i < pendingSellOrderIds.length; i++) {
            if (pendingSellOrderIds[i] == orderId) {
                pendingSellOrderIds[i] = pendingSellOrderIds[pendingSellOrderIds.length - 1];
                pendingSellOrderIds.pop();
                break;
            }
        }
    }
}