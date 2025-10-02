/*
 SPDX-License-Identifier: BSD-3
 Changes:
 - 2025-10-02: Removed ITokenRegistry interface, tokenRegistry state variable, setTokenRegistry function, TokenRegistryNotSet and TokenRegistryCallFailed events, and all related calls.
 - 2025-05-20: Added try-catch for initializeBalances in _transfer and dispense, added TokenRegistryCallFailed event.
 - 2025-05-20: Updated ITokenRegistry interface to use initializeBalances(address token, address[] memory users).
 - 2025-05-20: Renamed totalSupply to _totalSupply, balances to _balances, allowances to _allowances to resolve naming conflicts with ERC20 functions.
 - 2025-05-19: Updated dispense to mint LUSD only to msg.sender, transfer ETH to feeClaimer, updated TokenRegistry calls to include only msg.sender.
 - 2025-05-19: Added ETH transfer to feeClaimer in dispense, added EthTransferred event.
*/

pragma solidity ^0.8.2;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}

contract LinkDollarV2 {
    // State variables
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(uint256 => address[100]) private cells;
    mapping(address => uint256) private addressToCell;
    mapping(uint256 => uint256) private cellCycle;
    uint256 private _totalSupply;
    uint256 private wholeCycle;
    uint256 private swapCount;
    uint256 public cellHeight;
    address public owner;
    address public oracleAddress;
    address public feeClaimer;
    uint256 private contractBalance;
    bool private locked;

    // Constants
    uint256 private constant FEE_BPS = 5; // 0.05% = 5 basis points
    uint256 private constant CELL_SIZE = 100;
    uint256 private constant SWAPS_PER_CYCLE = 10;
    uint8 private constant DECIMALS = 18;
    string private constant NAME = "Link Dollar v2";
    string private constant SYMBOL = "LUSD";

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Dispense(address indexed recipient, address indexed feeClaimer, uint256 lusdAmount);
    event RewardsDistributed(uint256 indexed cellIndex, uint256 amount);
    event OracleAddressSet(address indexed oracleAddress);
    event FeeClaimerSet(address indexed feeClaimer);
    event EthTransferred(address indexed to, uint256 amount);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "ReentrancyGuard: reentrant call");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        owner = msg.sender;
        _totalSupply = 5 * 10**uint256(DECIMALS);
        _balances[msg.sender] = _totalSupply;
        cells[0][0] = msg.sender;
        addressToCell[msg.sender] = 0;
        cellHeight = 0;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    // External functions
    function dispense() external payable nonReentrant {
        require(msg.value > 0, "No ETH sent");
        require(oracleAddress != address(0), "Oracle not set");
        require(feeClaimer != address(0), "Fee claimer not set");

        int256 priceInt = IOracle(oracleAddress).latestAnswer();
        require(priceInt > 0, "Invalid oracle price");
        uint256 price = uint256(priceInt);
        uint256 lusdAmount = (msg.value * price) / 10**8;

        _mint(msg.sender, lusdAmount);

        // Transfer ETH to feeClaimer
        (bool success, ) = feeClaimer.call{value: msg.value}("");
        require(success, "ETH transfer failed");
        emit EthTransferred(feeClaimer, msg.value);

        emit Dispense(msg.sender, feeClaimer, lusdAmount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= amount, "Insufficient allowance");
        unchecked { _allowances[from][msg.sender] = allowed - amount; }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function setOracleAddress(address _oracleAddress) external onlyOwner {
        require(_oracleAddress != address(0), "Invalid oracle address");
        oracleAddress = _oracleAddress;
        emit OracleAddressSet(_oracleAddress);
    }

    function setFeeClaimer(address _feeClaimer) external onlyOwner {
        require(_feeClaimer != address(0), "Invalid fee claimer");
        feeClaimer = _feeClaimer;
        emit FeeClaimerSet(_feeClaimer);
    }

    function getCell(uint256 cellIndex) external view returns (address[100] memory) {
        return cells[cellIndex];
    }

    function getAddressCell(address account) external view returns (uint256) {
        return addressToCell[account];
    }

    function getCellBalances(uint256 cellIndex) external view returns (address[] memory addresses, uint256[] memory balances_) {
        address[] memory tempAddresses = new address[](CELL_SIZE);
        uint256[] memory tempBalances = new uint256[](CELL_SIZE);
        uint256 count = 0;

        for (uint256 i = 0; i < CELL_SIZE; i++) {
            address account = cells[cellIndex][i];
            if (account == address(0)) continue;
            uint256 balance = _balances[account];
            if (balance == 0) continue;
            tempAddresses[count] = account;
            tempBalances[count] = balance;
            count++;
        }

        addresses = new address[](count);
        balances_ = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            addresses[i] = tempAddresses[i];
            balances_[i] = tempBalances[i];
        }
    }

    function getTopHolders(uint256 count) external view returns (address[] memory holders, uint256[] memory holderBalances) {
        address[] memory tempHolders = new address[](count);
        uint256[] memory tempBalances = new uint256[](count);
        uint256 found = 0;

        for (uint256 i = 0; i <= cellHeight; i++) {
            for (uint256 j = 0; j < CELL_SIZE; j++) {
                address addr = cells[i][j];
                if (addr == address(0)) continue;
                uint256 bal = _balances[addr];
                if (bal == 0) continue;

                if (found < count) {
                    tempHolders[found] = addr;
                    tempBalances[found] = bal;
                    found++;
                } else {
                    uint256 minIndex = 0;
                    for (uint256 k = 1; k < count; k++) {
                        if (tempBalances[k] < tempBalances[minIndex]) {
                            minIndex = k;
                        }
                    }
                    if (bal > tempBalances[minIndex]) {
                        tempHolders[minIndex] = addr;
                        tempBalances[minIndex] = bal;
                    }
                }
            }
        }

        holders = new address[](found);
        holderBalances = new uint256[](found);
        for (uint256 i = 0; i < found; i++) {
            holders[i] = tempHolders[i];
            holderBalances[i] = tempBalances[i];
        }
    }

    // View functions
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function name() external pure returns (string memory) {
        return NAME;
    }

    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    function getOraclePrice() external view returns (uint256) {
        if (oracleAddress == address(0)) return 0;
        int256 price = IOracle(oracleAddress).latestAnswer();
        return price > 0 ? uint256(price) : 0;
    }

    // Internal functions
    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(_balances[from] >= amount, "Insufficient balance");

        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 amountAfterFee = amount - fee;

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amountAfterFee;
            contractBalance += fee;
        }

        _updateCells(from, _balances[from]);
        _updateCells(to, _balances[to]);

        emit Transfer(from, to, amountAfterFee);
        emit Transfer(from, address(this), fee);

        swapCount++;
        if (swapCount % SWAPS_PER_CYCLE == 0) {
            wholeCycle++;
            _distributeRewards();
        }
    }

    function _mint(address account, uint256 amount) private {
        require(account != address(0), "Mint to zero address");
        _totalSupply += amount;
        unchecked { _balances[account] += amount; }
        _updateCells(account, _balances[account]);
        emit Transfer(address(0), account, amount);
    }

    function _updateCells(address account, uint256 newBalance) private {
        uint256 cellIndex = addressToCell[account];
        bool isInCell = addressToCell[account] != 0 || cells[0][0] == account;

        if (newBalance == 0 && isInCell) {
            // Remove from cell
            uint256 indexInCell;
            for (uint256 i = 0; i < CELL_SIZE; i++) {
                if (cells[cellIndex][i] == account) {
                    indexInCell = i;
                    break;
                }
            }
            // Gap closing: move last non-zero address to this spot
            uint256 lastIndex = CELL_SIZE - 1;
            while (lastIndex > 0 && cells[cellIndex][lastIndex] == address(0)) {
                lastIndex--;
            }
            if (lastIndex != indexInCell && cells[cellIndex][lastIndex] != address(0)) {
                cells[cellIndex][indexInCell] = cells[cellIndex][lastIndex];
                addressToCell[cells[cellIndex][lastIndex]] = cellIndex;
            }
            cells[cellIndex][lastIndex] = address(0);
            delete addressToCell[account];
            // Cell gap-closing: decrement cellHeight if cell is empty and highest
            if (lastIndex == 0 && cellIndex == cellHeight) {
                while (cellHeight > 0) {
                    bool isEmpty = true;
                    for (uint256 i = 0; i < CELL_SIZE; i++) {
                        if (cells[cellHeight][i] != address(0)) {
                            isEmpty = false;
                            break;
                        }
                    }
                    if (!isEmpty) break;
                    cellHeight--;
                }
            }
        } else if (newBalance > 0 && !isInCell) {
            // Add to cell
            if (cells[cellHeight][CELL_SIZE - 1] != address(0)) {
                cellHeight++;
            }
            uint256 indexInCell;
            for (uint256 i = 0; i < CELL_SIZE; i++) {
                if (cells[cellHeight][i] == address(0)) {
                    indexInCell = i;
                    break;
                }
            }
            cells[cellHeight][indexInCell] = account;
            addressToCell[account] = cellHeight;
        }
    }

    function _distributeRewards() private {
        if (contractBalance == 0 || cellHeight == 0) return;

        uint256 selectedCell = uint256(keccak256(abi.encode(blockhash(block.number - 1), block.timestamp))) % (cellHeight + 1);
        if (cellCycle[selectedCell] >= wholeCycle) return;

        uint256 rewardAmount = (contractBalance * FEE_BPS) / 10000;
        if (rewardAmount == 0) return;

        uint256 cellBalance;
        for (uint256 i = 0; i < CELL_SIZE; i++) {
            address account = cells[selectedCell][i];
            if (account == address(0)) continue;
            cellBalance += _balances[account];
        }
        if (cellBalance == 0) return;

        contractBalance -= rewardAmount;

        for (uint256 i = 0; i < CELL_SIZE; i++) {
            address account = cells[selectedCell][i];
            if (account == address(0)) continue;
            uint256 accountBalance = _balances[account];
            if (accountBalance == 0) continue;
            uint256 accountReward = (rewardAmount * accountBalance) / cellBalance;
            unchecked { _balances[account] += accountReward; }
            _updateCells(account, _balances[account]);
            emit Transfer(address(this), account, accountReward);
        }

        cellCycle[selectedCell]++;
        emit RewardsDistributed(selectedCell, rewardAmount);
    }
}