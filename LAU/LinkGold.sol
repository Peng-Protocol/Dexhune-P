/*
 SPDX-License-Identifier: BSD-3
 Changes:
 - 2025-10-15: Modified _distributeRewards to skip empty or fully exempt cells, resetting their cellCycle to wholeCycle to prevent reward system stall.
 - 2025-10-15: Modified _distributeRewards to increment wholeCycle only when all cells' cellCycle equals wholeCycle, ensuring fair reward distribution across cells.
 - 2025-10-15: Added TokenRegistry call in dispense to register recipient after minting.
 - 2025-10-15: Split _transfer into _transferWithRegistry and _transferBasic for distinct transfer/transferFrom logic
 - Added rewardExceptions array and mapping, with owner-only add/remove functions
 - Added paginated view function for rewardExceptions
 - 2025-10-02: Replaced setOracleAddress with setOracleAddresses to take [XAU/USD, ETH/USD] oracles. Updated dispense and getOraclePrice to calculate ETH/XAU price.
 - 2025-10-02: Removed ITokenRegistry interface, tokenRegistry state variable, setTokenRegistry function, TokenRegistryNotSet and TokenRegistryCallFailed events, and all related calls.
 - 2025-08-11: Removed TokenRegistry updates from _distributeRewards, keeping them only in transfer/transferFrom and dispense.
 - 2025-08-11: Created LAU (Link Gold) from LUSD, changed name to "Link Gold", ticker to "LAU", removed transfer fee.
 - 2025-05-20: Added try-catch for initializeBalances in _transfer and dispense, added TokenRegistryCallFailed event.
 - 2025-05-20: Updated ITokenRegistry interface to use initializeBalances(address token, address[] memory users).
 - 2025-05-20: Renamed totalSupply to _totalSupply, balances to _balances, allowances to _allowances to resolve naming conflicts with ERC20 functions.
 - 2025-05-19: Updated dispense to mint LUSD only to msg.sender, transfer ETH to feeClaimer, updated TokenRegistry calls to include only msg.sender.
 - 2025-05-19: Added ETH transfer to feeClaimer in dispense, added EthTransferred event.
*/

pragma solidity ^0.8.2;

interface IERC20 {
    function totalSupply() external view returns (uint256 total);
    function balanceOf(address account) external view returns (uint256 balance);
    function transfer(address to, uint256 amount) external returns (bool success);
    function allowance(address owner, address spender) external view returns (uint256 allowed);
    function approve(address spender, uint256 amount) external returns (bool success);
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
}

interface TokenRegistry {
    function initializeBalances(address token, address[] memory userAddresses) external;
}

interface IOracle {
    // Fetches price data for XAU/USD or ETH/USD (8 decimals)
    function latestAnswer() external view returns (int256 price);
}

contract LinkGold {
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
    address[2] public oracleAddresses; // [0]: XAU/USD, [1]: ETH/USD
    address public feeClaimer;
    uint256 private contractBalance;
    bool private locked;

    // Constants
    uint256 private constant CELL_SIZE = 100;
    uint256 private constant SWAPS_PER_CYCLE = 10;
    uint8 private constant DECIMALS = 18;
    string private constant NAME = "Link Gold";
    string private constant SYMBOL = "LAU";
    
    mapping(address => bool isExempt) private rewardExceptions;
    address[] private rewardExceptionList;
    address public tokenRegistry;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Dispense(address indexed recipient, address indexed feeClaimer, uint256 lauAmount);
    event RewardsDistributed(uint256 indexed cellIndex, uint256 amount);
    event OracleAddressesSet(address indexed xauUsdOracle, address indexed ethUsdOracle);
    event FeeClaimerSet(address indexed feeClaimer);
    event EthTransferred(address indexed to, uint256 amount);
    // Token registry events
event TokenRegistryCallFailed(address indexed user, address indexed token);
event TokenRegistrySet(address indexed tokenRegistry);

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
    
   function addRewardExceptions(address[] memory accounts) external onlyOwner {
    // Adds addresses to reward exclusion list
    for (uint256 i = 0; i < accounts.length; i++) {
        if (accounts[i] != address(0) && !rewardExceptions[accounts[i]]) {
            rewardExceptions[accounts[i]] = true;
            rewardExceptionList.push(accounts[i]);
        }
    }
}

function removeRewardExceptions(address[] memory accounts) external onlyOwner {
    // Removes addresses from reward exclusion list
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

// Add to external functions
function setTokenRegistry(address _tokenRegistry) external onlyOwner {
    // Sets TokenRegistry address
    require(_tokenRegistry != address(0), "Invalid registry address");
    tokenRegistry = _tokenRegistry;
    emit TokenRegistrySet(_tokenRegistry);
}

    // External functions
    function dispense() external payable nonReentrant {
    require(msg.value > 0, "No ETH sent");
    require(oracleAddresses[0] != address(0) && oracleAddresses[1] != address(0), "Oracles not set");
    require(feeClaimer != address(0), "Fee claimer not set");

    int256 xauUsdPrice = IOracle(oracleAddresses[0]).latestAnswer();
    int256 ethUsdPrice = IOracle(oracleAddresses[1]).latestAnswer();
    require(xauUsdPrice > 0 && ethUsdPrice > 0, "Invalid oracle prices");
    
    uint256 ethXauPrice = (uint256(ethUsdPrice) * 10**8) / uint256(xauUsdPrice);
    uint256 lauAmount = (msg.value * ethXauPrice) / 10**8;

    _mint(msg.sender, lauAmount);

    // Register recipient in TokenRegistry
    if (tokenRegistry != address(0)) {
        address[] memory users = new address[](1);
        users[0] = msg.sender;
        try TokenRegistry(tokenRegistry).initializeBalances(address(this), users) {} catch {
            emit TokenRegistryCallFailed(msg.sender, address(this));
        }
    }

    // Transfers ETH to feeClaimer
    (bool success, ) = feeClaimer.call{value: msg.value}("");
    require(success, "ETH transfer failed");
    emit EthTransferred(feeClaimer, msg.value);

    emit Dispense(msg.sender, feeClaimer, lauAmount);
}

    // Modified transfer and transferFrom to use new internal functions
function transfer(address to, uint256 amount) external returns (bool success) {
    _transferWithRegistry(msg.sender, to, amount);
    return true;
}

    function transferFrom(address from, address to, uint256 amount) external returns (bool success) {
    uint256 allowed = _allowances[from][msg.sender];
    require(allowed >= amount, "Insufficient allowance");
    unchecked { _allowances[from][msg.sender] = allowed - amount; }
    _transferBasic(from, to, amount);
    return true;
}

    function approve(address spender, uint256 amount) external returns (bool success) {
        // Sets allowance for spender
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function setOracleAddresses(address[2] memory _oracleAddresses) external onlyOwner {
        // Sets XAU/USD and ETH/USD oracle addresses
        require(_oracleAddresses[0] != address(0) && _oracleAddresses[1] != address(0), "Invalid oracle addresses");
        oracleAddresses = _oracleAddresses;
        emit OracleAddressesSet(_oracleAddresses[0], _oracleAddresses[1]);
    }

    function setFeeClaimer(address _feeClaimer) external onlyOwner {
        // Sets fee claimer address
        require(_feeClaimer != address(0), "Invalid fee claimer");
        feeClaimer = _feeClaimer;
        emit FeeClaimerSet(_feeClaimer);
    }

    function getCell(uint256 cellIndex) external view returns (address[100] memory cell) {
        // Returns cell addresses
        return cells[cellIndex];
    }

    function getAddressCell(address account) external view returns (uint256 cellIndex) {
        // Returns cell index for account
        return addressToCell[account];
    }

    function getCellBalances(uint256 cellIndex) external view returns (address[] memory addresses, uint256[] memory balances_) {
        // Retrieves non-zero balances in cell
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
        // Retrieves top holders by balance
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
    function balanceOf(address account) external view returns (uint256 balance) {
        // Returns account balance
        return _balances[account];
    }

    function allowance(address owner_, address spender) external view returns (uint256 allowed) {
        // Returns allowance for spender
        return _allowances[owner_][spender];
    }

    function totalSupply() external view returns (uint256 total) {
        // Returns total token supply
        return _totalSupply;
    }

    function decimals() external pure returns (uint8 dec) {
        // Returns token decimals
        return DECIMALS;
    }

    function name() external pure returns (string memory tokenName) {
        // Returns token name
        return NAME;
    }

    function symbol() external pure returns (string memory tokenSymbol) {
        // Returns token symbol
        return SYMBOL;
    }

    function getOraclePrice() external view returns (uint256 ethXauPrice) {
        // Returns ETH/XAU price using XAU/USD and ETH/USD oracles
        if (oracleAddresses[0] == address(0) || oracleAddresses[1] == address(0)) return 0;
        int256 xauUsdPrice = IOracle(oracleAddresses[0]).latestAnswer();
        int256 ethUsdPrice = IOracle(oracleAddresses[1]).latestAnswer();
        if (xauUsdPrice <= 0 || ethUsdPrice <= 0) return 0;
        // Calculate ETH/XAU: (ETH/USD ÷ XAU/USD) * 10^8
        return (uint256(ethUsdPrice) * 10**8) / uint256(xauUsdPrice);
    }
    
    function getRewardExceptions(uint256 start, uint256 maxIterations) external view returns (address[] memory exceptions) {
    // Returns paginated list of reward-exempt addresses
    uint256 end = start + maxIterations < rewardExceptionList.length ? start + maxIterations : rewardExceptionList.length;
    exceptions = new address[](end - start);
    for (uint256 i = start; i < end; i++) {
        exceptions[i - start] = rewardExceptionList[i];
    }
}

    // Internal functions
    function _transferWithRegistry(address from, address to, uint256 amount) private {
    // Transfers tokens and registers in TokenRegistry
    require(from != address(0), "Transfer from zero address");
    require(to != address(0), "Transfer to zero address");
    require(_balances[from] >= amount, "Insufficient balance");

    unchecked {
        _balances[from] -= amount;
        _balances[to] += amount;
    }

    _updateCells(from, _balances[from]);
    _updateCells(to, _balances[to]);

    // Register sender and receiver in TokenRegistry with dynamic array
    if (tokenRegistry != address(0)) {
        address[] memory users = new address[](2);
        users[0] = from;
        users[1] = to;
        try TokenRegistry(tokenRegistry).initializeBalances(address(this), users) {} catch {
            emit TokenRegistryCallFailed(from, address(this));
        }
    }

    emit Transfer(from, to, amount);

    swapCount++;
    if (swapCount % SWAPS_PER_CYCLE == 0) {
        wholeCycle++;
        _distributeRewards();
    }
}

function _transferBasic(address from, address to, uint256 amount) private {
    // Transfers tokens without TokenRegistry calls
    require(from != address(0), "Transfer from zero address");
    require(to != address(0), "Transfer to zero address");
    require(_balances[from] >= amount, "Insufficient balance");

    unchecked {
        _balances[from] -= amount;
        _balances[to] += amount;
    }

    _updateCells(from, _balances[from]);
    _updateCells(to, _balances[to]);

    emit Transfer(from, to, amount);

    swapCount++;
    if (swapCount % SWAPS_PER_CYCLE == 0) {
        wholeCycle++;
        _distributeRewards();
    }
}

    function _mint(address account, uint256 amount) private {
        // Mints new tokens
        require(account != address(0), "Mint to zero address");
        _totalSupply += amount;
        unchecked { _balances[account] += amount; }
        _updateCells(account, _balances[account]);
        emit Transfer(address(0), account, amount);
    }

    function _updateCells(address account, uint256 newBalance) private {
        // Updates cell structure for account
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

    // Modified _distributeRewards to ensure fairness and eligibility 
function _distributeRewards() private {
    // Distributes rewards only if a cell has cellCycle < wholeCycle
    if (contractBalance == 0 || cellHeight == 0) return;

    // Check if all cells have cellCycle equal to wholeCycle
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
                cellCycle[i] = wholeCycle; // Reset ineligible cell
            }
        }
    }

    if (allCellsSynced) {
        wholeCycle++;
        return; // No distribution, wait for next cycle
    }

    // Find a cell with cellCycle < wholeCycle
    uint256 selectedCell = uint256(keccak256(abi.encode(blockhash(block.number - 1), block.timestamp))) % (cellHeight + 1);
    uint256 attempts = 0;
    while (cellCycle[selectedCell] >= wholeCycle && attempts < cellHeight + 1) {
        selectedCell = (selectedCell + 1) % (cellHeight + 1);
        attempts++;
    }
    if (cellCycle[selectedCell] >= wholeCycle) return; // No eligible cell found

    // Check if selected cell is eligible
    bool isCellEligible = false;
    for (uint256 i = 0; i < CELL_SIZE; i++) {
        address account = cells[selectedCell][i];
        if (account != address(0) && !rewardExceptions[account] && _balances[account] > 0) {
            isCellEligible = true;
            break;
        }
    }
    if (!isCellEligible) {
        cellCycle[selectedCell] = wholeCycle; // Reset ineligible cell
        return;
    }

    uint256 rewardAmount = contractBalance / 10000;
    if (rewardAmount == 0) return;

    uint256 cellBalance;
    for (uint256 i = 0; i < CELL_SIZE; i++) {
        address account = cells[selectedCell][i];
        if (account == address(0) || rewardExceptions[account]) continue;
        cellBalance += _balances[account];
    }
    if (cellBalance == 0) return;

    contractBalance -= rewardAmount;

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