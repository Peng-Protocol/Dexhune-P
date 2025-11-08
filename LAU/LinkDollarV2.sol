/*
 SPDX-License-Identifier: BSD-3
 Changes:
 - 2025-11-08: Removed cellHeight == 0 check in _distributeRewards (allows single-cell rewards).
 - 2025-11-08: Changed rewardAmount = rewardPool / 10000 (removes FEE_BPS multiplier).
 - 2025-10-19: Fixed _distributeRewards isCellEligible loop to check cells[selectedCell][i] instead of cells[i][i].
 - 2025-10-19: Updated _transferWithRegistry, _transferBasic, and _distributeRewards to use _balances[address(this)] instead of contractBalance, removed contractBalance.
 - 2025-10-15: Modified _distributeRewards to skip empty or fully exempt cells, resetting their cellCycle to wholeCycle.
 - 2025-10-15: Modified _distributeRewards to increment wholeCycle only when all cells' cellCycle equals wholeCycle.
 - 2025-10-15: Added TokenRegistry call in dispense to register recipient after minting.
 - 2025-10-15: Split _transfer into _transferWithRegistry and _transferBasic for distinct transfer/transferFrom logic.
 - Added rewardExceptions array and mapping, with owner-only add/remove functions.
 - Added paginated view function for rewardExceptions.
 - 2025-10-02: Removed ITokenRegistry interface, tokenRegistry state variable, setTokenRegistry function, TokenRegistryNotSet and TokenRegistryCallFailed events, and all related calls.
 - 2025-05-20: Added try-catch for initializeBalances in _transfer and dispense, added TokenRegistryCallFailed event.
 - 2025-05-20: Updated ITokenRegistry interface to use initializeBalances(address token, address[] memory users).
 - 2025-05-20: Renamed totalSupply to _totalSupply, balances to _balances, allowances to _allowances.
 - 2025-05-19: Updated dispense to mint LUSD only to msg.sender, transfer ETH to feeClaimer.
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

interface TokenRegistry {
    function initializeBalances(address token, address[] memory userAddresses) external;
}

interface IOracle {
    function latestAnswer() external view returns (int256);
}

contract LinkDollarV2 {
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
    bool private locked;
    mapping(address => bool isExempt) public rewardExceptions;
    address[] private rewardExceptionList;
    address public tokenRegistry;

    uint256 private constant FEE_BPS = 5;
    uint256 private constant CELL_SIZE = 100;
    uint256 private constant SWAPS_PER_CYCLE = 10;
    uint8 private constant DECIMALS = 18;
    string private constant NAME = "Link Dollar v2";
    string private constant SYMBOL = "LUSD";

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Dispense(address indexed recipient, address indexed feeClaimer, uint256 lusdAmount);
    event RewardsDistributed(uint256 indexed cellIndex, uint256 amount);
    event OracleAddressSet(address indexed oracleAddress);
    event FeeClaimerSet(address indexed feeClaimer);
    event EthTransferred(address indexed to, uint256 amount);
    event TokenRegistryCallFailed(address indexed user, address indexed token);
    event TokenRegistrySet(address indexed tokenRegistry);

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

    function addRewardExceptions(address[] memory accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] != address(0) && !rewardExceptions[accounts[i]]) {
                rewardExceptions[accounts[i]] = true;
                rewardExceptionList.push(accounts[i]);
            }
        }
    }

    function removeRewardExceptions(address[] memory accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (rewardExceptions[accounts[i]]) {
                rewardExceptions[accounts[i]] = false;
                for (uint256 j = 0; j < rewardExceptionList.length; j++) {
                    if (rewardExceptionList[j] == accounts[i]) {
                        rewardExceptionList[j] = rewardExceptionList[rewardExceptionList.length - 1];
                        rewardExceptionList.pop();
                        break;
                    }
                }
            }
        }
    }

    function setTokenRegistry(address _tokenRegistry) external onlyOwner {
        require(_tokenRegistry != address(0), "Invalid registry address");
        tokenRegistry = _tokenRegistry;
        emit TokenRegistrySet(_tokenRegistry);
    }

    function dispense() external payable nonReentrant {
        require(msg.value > 0, "No ETH sent");
        require(oracleAddress != address(0), "Oracle not set");
        require(feeClaimer != address(0), "Fee claimer not set");

        int256 priceInt = IOracle(oracleAddress).latestAnswer();
        require(priceInt > 0, "Invalid oracle price");
        uint256 price = uint256(priceInt);
        uint256 lusdAmount = (msg.value * price) / 10**8;

        _mint(msg.sender, lusdAmount);

        if (tokenRegistry != address(0)) {
            address[] memory users = new address[](1);
            users[0] = msg.sender;
            try TokenRegistry(tokenRegistry).initializeBalances(address(this), users) {} catch {
                emit TokenRegistryCallFailed(msg.sender, address(this));
            }
        }

        (bool success, ) = feeClaimer.call{value: msg.value}("");
        require(success, "ETH transfer failed");
        emit EthTransferred(feeClaimer, msg.value);

        emit Dispense(msg.sender, feeClaimer, lusdAmount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transferWithRegistry(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= amount, "Insufficient allowance");
        unchecked { _allowances[from][msg.sender] = allowed - amount; }
        _transferBasic(from, to, amount);
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

    function getRewardExceptions(uint256 start, uint256 maxIterations) external view returns (address[] memory exceptions) {
        uint256 end = start + maxIterations < rewardExceptionList.length ? start + maxIterations : rewardExceptionList.length;
        exceptions = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            exceptions[i - start] = rewardExceptionList[i];
        }
    }

    function _transferWithRegistry(address from, address to, uint256 amount) private {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(_balances[from] >= amount, "Insufficient balance");

        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 amountAfterFee = amount - fee;

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amountAfterFee;
            _balances[address(this)] += fee;
        }

        _updateCells(from, _balances[from]);
        _updateCells(to, _balances[to]);

        if (tokenRegistry != address(0)) {
            address[] memory users = new address[](2);
            users[0] = from;
            users[1] = to;
            try TokenRegistry(tokenRegistry).initializeBalances(address(this), users) {} catch {
                emit TokenRegistryCallFailed(from, address(this));
            }
        }

        emit Transfer(from, to, amountAfterFee);
        emit Transfer(from, address(this), fee);

        swapCount++;
        if (swapCount % SWAPS_PER_CYCLE == 0) {
            wholeCycle++;
            _distributeRewards();
        }
    }

    function _transferBasic(address from, address to, uint256 amount) private {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(_balances[from] >= amount, "Insufficient balance");

        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 amountAfterFee = amount - fee;

        unchecked {
            _balances[from] -= amount;
            _balances[to] += amountAfterFee;
            _balances[address(this)] += fee;
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
            uint256 indexInCell;
            for (uint256 i = 0; i < CELL_SIZE; i++) {
                if (cells[cellIndex][i] == account) {
                    indexInCell = i;
                    break;
                }
            }
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
        // Distributes 0.01% of contract balance to a random eligible cell.
        uint256 rewardPool = _balances[address(this)];
        if (rewardPool == 0) return;

        bool allCellsSynced = true;
        for (uint256 i = 0; i <= cellHeight; i++) {
            if (cellCycle[i] < wholeCycle) {
                bool isEligible = false;
                for (uint256 j = 0; j < CELL_SIZE; j++) {
                    address account = cells[i][j];
                    if (account != address(0) && !rewardExceptions[account] && _balances[account] > 0) {
                        isEligible = true;
                        break;
                    }
                }
                if (isEligible) {
                    allCellsSynced = false;
                    break;
                } else {
                    cellCycle[i] = wholeCycle;
                }
            }
        }

        if (allCellsSynced) {
            wholeCycle++;
            return;
        }

        uint256 selectedCell = uint256(keccak256(abi.encode(blockhash(block.number - 1), block.timestamp))) % (cellHeight + 1);
        uint256 attempts = 0;
        while (cellCycle[selectedCell] >= wholeCycle && attempts < cellHeight + 1) {
            selectedCell = (selectedCell + 1) % (cellHeight + 1);
            attempts++;
        }
        if (cellCycle[selectedCell] >= wholeCycle) return;

        bool isCellEligible = false;
        for (uint256 i = 0; i < CELL_SIZE; i++) {
            address account = cells[selectedCell][i];
            if (account != address(0) && !rewardExceptions[account] && _balances[account] > 0) {
                isCellEligible = true;
                break;
            }
        }
        if (!isCellEligible) {
            cellCycle[selectedCell] = wholeCycle;
            return;
        }

        uint256 rewardAmount = rewardPool / 10000;
        if (rewardAmount == 0) return;

        uint256 cellBalance;
        for (uint256 i = 0; i < CELL_SIZE; i++) {
            address account = cells[selectedCell][i];
            if (account == address(0) || rewardExceptions[account]) continue;
            cellBalance += _balances[account];
        }
        if (cellBalance == 0) return;

        _balances[address(this)] -= rewardAmount;

        for (uint256 i = 0; i < CELL_SIZE; i++) {
            address account = cells[selectedCell][i];
            if (account == address(0) || rewardExceptions[account]) continue;
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