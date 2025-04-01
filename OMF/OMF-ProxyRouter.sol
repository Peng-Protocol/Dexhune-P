// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.8
// Changes:
// - Updated tokenA to token0, using baseToken from OMFAgent.
// - Added volume updates to OMFListingTemplate, added withdrawLiquidity.
// - Inlined OMFAgent, IOMFOrderLibrary, IOMFSettlementLibrary, IOMFListing, IOMFLiquidity interfaces.

import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

contract OMFProxyRouter is Ownable {
    using SafeERC20 for IERC20;

    address public agent;
    address public orderLibrary;
    address public settlementLibrary;
    address public liquidLibrary;

    constructor(address _agent) {
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function setOrderLibrary(address _orderLibrary) external onlyOwner {
        orderLibrary = _orderLibrary;
    }

    function setSettlementLibrary(address _settlementLibrary) external onlyOwner {
        settlementLibrary = _settlementLibrary;
    }

    function setLiquidLibrary(address _liquidLibrary) external onlyOwner {
        liquidLibrary = _liquidLibrary;
    }

    function buy(address token0, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFOrderLibrary interface
        (uint256 principal, uint256 fee, uint256 orderId);
        {
            (bool success, bytes memory returnData) = orderLibrary.call(
                abi.encodeWithSignature(
                    "prep$Order(address,bool,uint256,uint256,uint256,address)",
                    listing,
                    true,
                    amount,
                    maxPrice,
                    minPrice,
                    recipient
                )
            );
            require(success, "Prep order failed");
            (principal, fee, orderId) = abi.decode(returnData, (uint256, uint256, uint256));
        }

        uint256 preBalance = IERC20(token0).balanceOf(listing);
        IERC20(token0).safeTransferFrom(msg.sender, listing, principal);
        uint256 actualReceived = IERC20(token0).balanceOf(listing) - preBalance;
        if (actualReceived < principal) {
            // Inline IOMFListing interface for updateVolume
            (bool success, ) = listing.call(
                abi.encodeWithSignature("updateVolume(bool,uint256)", true, principal - actualReceived)
            );
            require(success, "Update volume failed");
        }

        // Inline IOMFListing interface for liquidityAddresses
        address liquidity;
        {
            (bool success, bytes memory returnData) = listing.staticcall(
                abi.encodeWithSignature("liquidityAddresses(uint256)", 0)
            );
            require(success, "Liquidity address fetch failed");
            liquidity = abi.decode(returnData, (address));
        }

        if (fee > 0) IERC20(token0).safeTransferFrom(msg.sender, liquidity, fee);
    }

    function sell(address token0, uint256 amount, uint256 maxPrice, uint256 minPrice, address recipient) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFOrderLibrary interface
        (uint256 principal, uint256 fee, uint256 orderId);
        {
            (bool success, bytes memory returnData) = orderLibrary.call(
                abi.encodeWithSignature(
                    "prep$Order(address,bool,uint256,uint256,uint256,address)",
                    listing,
                    false,
                    amount,
                    maxPrice,
                    minPrice,
                    recipient
                )
            );
            require(success, "Prep order failed");
            (principal, fee, orderId) = abi.decode(returnData, (uint256, uint256, uint256));
        }

        uint256 preBalance = IERC20(token0).balanceOf(listing);
        IERC20(token0).safeTransferFrom(msg.sender, listing, principal);
        uint256 actualReceived = IERC20(token0).balanceOf(listing) - preBalance;
        if (actualReceived < principal) {
            // Inline IOMFListing interface for updateVolume
            (bool success, ) = listing.call(
                abi.encodeWithSignature("updateVolume(bool,uint256)", true, principal - actualReceived)
            );
            require(success, "Update volume failed");
        }

        // Inline IOMFListing interface for liquidityAddresses
        address liquidity;
        {
            (bool success, bytes memory returnData) = listing.staticcall(
                abi.encodeWithSignature("liquidityAddresses(uint256)", 0)
            );
            require(success, "Liquidity address fetch failed");
            liquidity = abi.decode(returnData, (address));
        }

        if (fee > 0) IERC20(token0).safeTransferFrom(msg.sender, liquidity, fee);
    }

    function deposit(address token0, bool isX, uint256 amount) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        address token = isX ? token0 : this.baseToken();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Inline IOMFListing interface for liquidityAddresses
        address liquidity;
        {
            (bool success, bytes memory returnData) = listing.staticcall(
                abi.encodeWithSignature("liquidityAddresses(uint256)", 0)
            );
            require(success, "Liquidity address fetch failed");
            liquidity = abi.decode(returnData, (address));
        }

        IERC20(token).approve(liquidity, amount);

        // Inline IOMFLiquidity interface
        {
            (bool success, ) = liquidity.call(
                abi.encodeWithSignature("deposit(address,bool,uint256)", address(this), isX, amount)
            );
            require(success, "Deposit failed");
        }
    }

    function withdrawLiquidity(address token0, bool isX, uint256 slotIndex, uint256 amount) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFListing interface for liquidityAddresses
        address liquidity;
        {
            (bool success, bytes memory returnData) = listing.staticcall(
                abi.encodeWithSignature("liquidityAddresses(uint256)", 0)
            );
            require(success, "Liquidity address fetch failed");
            liquidity = abi.decode(returnData, (address));
        }

        // Inline IOMFLiquidity interface
        {
            (bool success, ) = liquidity.call(
                abi.encodeWithSignature("withdrawLiquidity(bool,uint256,uint256)", isX, slotIndex, amount)
            );
            require(success, "Withdraw liquidity failed");
        }
    }

    function settleBuy(address token0, uint256[] memory orderIds) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFSettlementLibrary interface
        {
            (bool success, ) = settlementLibrary.call(
                abi.encodeWithSignature(
                    "settleBuyOrders(address,uint256[],address,address)",
                    listing,
                    orderIds,
                    agent,
                    address(this)
                )
            );
            require(success, "Settle buy failed");
        }
    }

    function settleSell(address token0, uint256[] memory orderIds) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFSettlementLibrary interface
        {
            (bool success, ) = settlementLibrary.call(
                abi.encodeWithSignature(
                    "settleSellOrders(address,uint256[],address,address)",
                    listing,
                    orderIds,
                    agent,
                    address(this)
                )
            );
            require(success, "Settle sell failed");
        }
    }

    function settleBuyLiquid(address token0, uint256[] memory orderIds) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline OMFLiquidLibrary interface (SettlementData struct assumed available)
        bytes memory prepData;
        {
            (bool success, bytes memory returnData) = liquidLibrary.staticcall(
                abi.encodeWithSignature(
                    "prepBuyLiquid(address,uint256[],address,address)",
                    listing,
                    orderIds,
                    agent,
                    address(this)
                )
            );
            require(success, "Prep buy liquid failed");
            prepData = returnData;
        }

        {
            (bool success, ) = liquidLibrary.call(
                abi.encodeWithSignature(
                    "executeBuyLiquid(address,(uint256,uint256[],(uint256,uint256,address)[],address,address),address,address)",
                    listing,
                    abi.decode(prepData, (uint256, uint256[], (uint256, uint256, address)[], address, address)),
                    agent,
                    address(this)
                )
            );
            require(success, "Execute buy liquid failed");
        }
    }

    function settleSellLiquid(address token0, uint256[] memory orderIds) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline OMFLiquidLibrary interface (SettlementData struct assumed available)
        bytes memory prepData;
        {
            (bool success, bytes memory returnData) = liquidLibrary.staticcall(
                abi.encodeWithSignature(
                    "prepSellLiquid(address,uint256[],address,address)",
                    listing,
                    orderIds,
                    agent,
                    address(this)
                )
            );
            require(success, "Prep sell liquid failed");
            prepData = returnData;
        }

        {
            (bool success, ) = liquidLibrary.call(
                abi.encodeWithSignature(
                    "executeSellLiquid(address,(uint256,uint256[],(uint256,uint256,address)[],address,address),address,address)",
                    listing,
                    abi.decode(prepData, (uint256, uint256[], (uint256, uint256, address)[], address, address)),
                    agent,
                    address(this)
                )
            );
            require(success, "Execute sell liquid failed");
        }
    }

    function clearSingleOrder(address token0, uint256 orderId, bool isBuy) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFSettlementLibrary interface
        {
            (bool success, ) = settlementLibrary.call(
                abi.encodeWithSignature(
                    "clearSingleOrder(address,uint256,bool,address,address)",
                    listing,
                    orderId,
                    isBuy,
                    agent,
                    address(this)
                )
            );
            require(success, "Clear single order failed");
        }
    }

    function clearOrders(address token0) external {
        // Inline OMFAgent interface
        address listing;
        {
            (bool success, bytes memory returnData) = agent.staticcall(
                abi.encodeWithSignature("getListing(address,address)", token0, this.baseToken())
            );
            require(success, "Get listing failed");
            listing = abi.decode(returnData, (address));
        }

        // Inline IOMFSettlementLibrary interface
        {
            (bool success, ) = settlementLibrary.call(
                abi.encodeWithSignature(
                    "clearOrders(address,address,address)",
                    listing,
                    agent,
                    address(this)
                )
            );
            require(success, "Clear orders failed");
        }
    }

    // Helper function to inline OMFAgent baseToken()
    function baseToken() public view returns (address) {
        (bool success, bytes memory returnData) = agent.staticcall(abi.encodeWithSignature("baseToken()"));
        require(success, "Base token fetch failed");
        return abi.decode(returnData, (address));
    }
}