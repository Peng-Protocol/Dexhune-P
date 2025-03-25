// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.20;

// Version: 0.0.1

import "./imports/Ownable.sol";

contract MFPAgent is Ownable {
    address public routerAddress;
    address public listingTemplate;
    address public liquidityTemplate;
    uint256 public listingCount;

    // Mappings
    mapping(uint256 => ListingValidation) public listingValidationByIndex; // listingId -> validation
    mapping(address => ListingValidation) public listingValidationByAddress; // listingAddress -> validation
    mapping(address => uint256[]) public listingIndex; // token -> listingIds
    mapping(bytes32 => bool) public listedPairs; // keccak256(tokenA, tokenB) -> exists

    // Structs
    struct ListingValidation {
        address listingAddress;
        address tokenA;
        address tokenB;
        uint256 xBalance;
        uint256 yBalance;
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 index;
    }

    // Events
    event ListingCreated(uint256 listingId, address listingAddress, address liquidityAddress);

    constructor() {
        _transferOwnership(msg.sender);
    }

    function initialize(address _listingTemplate, address _liquidityTemplate) external onlyOwner {
        require(listingTemplate == address(0) && liquidityTemplate == address(0), "Already initialized");
        listingTemplate = _listingTemplate;
        liquidityTemplate = _liquidityTemplate;
    }

    function setRouter(address _router) external onlyOwner {
        require(routerAddress == address(0), "Router already set");
        routerAddress = _router;
    }

    function writeValidationSlot(
        uint256 listingId,
        address listingAddress,
        address tokenA,
        address tokenB,
        uint256 xBalance,
        uint256 yBalance,
        uint256 xLiquid,
        uint256 yLiquid
    ) external {
        require(msg.sender == routerAddress, "Router only");
        ListingValidation memory validation = ListingValidation(
            listingAddress,
            tokenA,
            tokenB,
            xBalance,
            yBalance,
            xLiquid,
            yLiquid,
            listingId
        );
        listingValidationByIndex[listingId] = validation;
        listingValidationByAddress[listingAddress] = validation;
    }

    function listToken(address tokenA, address tokenB) external {
        require(tokenA != tokenB, "Identical tokens");
        bytes32 pairHash = keccak256(abi.encodePacked(tokenA, tokenB));
        require(!listedPairs[pairHash], "Pair already listed");

        // Deploy MFP-ListingTemplate
        bytes memory listingCreationCode = abi.encodePacked(
            type(MFPListingTemplate).creationCode,
            abi.encode()
        );
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingCount));
        address listingAddress;
        assembly {
            listingAddress := create2(0, add(listingCreationCode, 0x20), mload(listingCreationCode), listingSalt)
            if iszero(extcodesize(listingAddress)) { revert(0, 0) }
        }

        // Deploy MFPLiquidityTemplate
        bytes memory liquidityCreationCode = abi.encodePacked(
            type(MFPLiquidityTemplate).creationCode,
            abi.encode()
        );
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingCount));
        address liquidityAddress;
        assembly {
            liquidityAddress := create2(0, add(liquidityCreationCode, 0x20), mload(liquidityCreationCode), liquiditySalt)
            if iszero(extcodesize(liquidityAddress)) { revert(0, 0) }
        }

        // Initialize contracts
        IMFPListing(listingAddress).setRouter(routerAddress);
        IMFPListing(listingAddress).setLiquidityAddress(listingCount, liquidityAddress);
        IMFPListing(listingAddress).setTokens(tokenA, tokenB);
        IMFPLiquidity(liquidityAddress).setRouter(routerAddress);
        IMFPLiquidity(liquidityAddress).setListingAddress(listingCount, listingAddress);
        IMFPLiquidity(liquidityAddress).setTokens(tokenA, tokenB);

        // Update state
        ListingValidation memory validation = ListingValidation(
            listingAddress,
            tokenA,
            tokenB,
            0,
            0,
            0,
            0,
            listingCount
        );
        listingValidationByIndex[listingCount] = validation;
        listingValidationByAddress[listingAddress] = validation;
        listingIndex[tokenA].push(listingCount);
        listingIndex[tokenB].push(listingCount);
        listedPairs[pairHash] = true;

        emit ListingCreated(listingCount, listingAddress, liquidityAddress);
        listingCount++;
    }

    function isValidListing(address listingAddress) external view returns (bool) {
        return listingValidationByAddress[listingAddress].listingAddress == listingAddress;
    }

    function getListingId(address listingAddress) external view returns (uint256) {
        ListingValidation memory validation = listingValidationByAddress[listingAddress];
        require(validation.listingAddress == listingAddress, "Invalid listing");
        return validation.index;
    }

    function getListingIndexes(address token, uint256 start) external view returns (uint256[] memory) {
        uint256[] storage indexes = listingIndex[token];
        uint256 length = indexes.length > start + 1000 ? 1000 : indexes.length - start;
        uint256[] memory result = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = indexes[start + i];
        }
        return result;
    }
}

// Interfaces (matching MFP-Router)
interface IMFPListing {
    function setRouter(address _router) external;
    function setLiquidityAddress(uint256 listingId, address _liquidity) external;
    function setTokens(address _tokenA, address _tokenB) external;
}

interface IMFPLiquidity {
    function setRouter(address _router) external;
    function setListingAddress(uint256 listingId, address _listing) external;
    function setTokens(address _tokenA, address _tokenB) external;
}