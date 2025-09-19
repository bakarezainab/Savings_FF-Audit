// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TimeLockSavings {
    IERC20 public immutable token;

    struct Deposit {
        uint256 amount;
        uint256 depositTime;
        bool withdrawn;
    }

    mapping(address => Deposit[]) public userDeposits;
    mapping(address => uint256) public totalDeposited;

    uint256 public constant MIN_LOCK_PERIOD = 60 days;
    uint256 public constant BONUS_PERIOD = 30 days;
    uint256 public constant BASE_REWARD_RATE = 200; // 2% = 200/10000
    uint256 public constant BONUS_REWARD_RATE = 100; // 1% = 100/10000
    uint256 public constant EARLY_PENALTY_RATE = 1000; // 10% = 1000/10000
    uint256 public constant BASIS_POINTS = 10000;

    address public owner;
    uint256 public totalLocked;
    uint256 public totalRewardsPaid;

    event Deposited(address indexed user, uint256 amount, uint256 depositId);
    event Withdrawn(address indexed user, uint256 amount, uint256 reward, uint256 depositId);
    event EarlyWithdrawn(address indexed user, uint256 amount, uint256 penalty, uint256 depositId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        // @audit-info there should be a check here to ensure the user is not an address 0
        _;
    } 

    constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
    }

    function deposit(uint256 _amount) external {        
        
        require(_amount > 0, "Amount must be greater than 0");
        // BUG Low. There should also be a check to check the balance of the user before transferring
         
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        // BUG: To use this transferFrom, the token should have approved an amount or have allowance

        userDeposits[msg.sender].push(Deposit({amount: _amount, depositTime: block.timestamp, withdrawn: false}));    
        // @audit-info what if same user with a specific id wants to deposit again and add to its savings?

        totalDeposited[msg.sender] += _amount; 
        totalLocked += _amount;
        
        emit Deposited(msg.sender, userDeposits[msg.sender].length - 1, _amount);
        // BUG: why is the amount and depositId swapped in the emit?
    }

    function withdraw(uint256 _depositId) external {
        require(_depositId < userDeposits[msg.sender].length, "Invalid deposit ID"); 
        // this check above ensures that the user that wants to withdraw has a deposit id
        
        Deposit storage userDeposit = userDeposits[msg.sender][_depositId]; 
        require(userDeposit.amount > 0, "No deposit found");

        uint256 timeElapsed = block.timestamp - userDeposit.depositTime;
        uint256 amount = userDeposit.amount;

        if (timeElapsed < MIN_LOCK_PERIOD) {
            // Early withdrawal with penalty
            uint256 penalty = (amount * EARLY_PENALTY_RATE) / BASIS_POINTS;
            uint256 withdrawAmount = amount - penalty;

            userDeposit.withdrawn = true;
            // BUG: No check to check when a user withdraws again
            totalLocked -= amount;
            totalDeposited[msg.sender] -= amount;

            require(token.transfer(msg.sender, withdrawAmount), "Transfer failed"); 
            // BUG: Critical. The above check should be done before updating state
            //BUG: Also, amount is not updated in the balance of the user, abi na my eye?
            
            emit EarlyWithdrawn(msg.sender, withdrawAmount, penalty, _depositId);
            // @audit-issue why is it emitting withdrawAmount instead of amount?
        } else {
            // Normal withdrawal with rewards
            uint256 reward = calculateReward(timeElapsed, amount);
            // BUG: Critical. There is a swap in the calculateReward parameters
            uint256 totalAmount = amount + reward;

            userDeposit.withdrawn = true;
            totalLocked -= amount;
            totalDeposited[msg.sender] -= amount;
            totalRewardsPaid += reward;

            require(token.transfer(msg.sender, totalAmount), "Transfer failed");
            // BUG: Reentrancy can occur here because the transfer is called after updating state
            emit Withdrawn(msg.sender, amount, reward, _depositId);
        }
    }

    function calculateReward(uint256 _amount, uint256 _timeElapsed) public pure returns (uint256) {
        
        if (_timeElapsed < MIN_LOCK_PERIOD) {
            return 0;
        }

        // Base reward for minimum lock period
        uint256 reward = (_amount * BASE_REWARD_RATE) / BASIS_POINTS;

        // Additional rewards for extra periods beyond minimum
        if (_timeElapsed > MIN_LOCK_PERIOD) {
            uint256 extraPeriods = (_timeElapsed - MIN_LOCK_PERIOD) / BONUS_PERIOD;
            // BUG: Critical, the above line can lead to overflow if extraPeriods is too high
            uint256 bonusReward = (_amount * BONUS_REWARD_RATE * extraPeriods) / BASIS_POINTS;
            // @audit-issue : is there not suppose to be a check here to ensure that extraPeriods is not zero?
            
            reward += bonusReward;
        }

        return reward;
    }

    function getUserDeposits(address _user) external view returns (Deposit[] memory) {
        return userDeposits[_user];
    }

    function getUserDepositCount(address _user) external view returns (uint256) {
        return userDeposits[_user].length;
    }

    function getDepositInfo(address _user, uint256 _depositId)
        external
        view
        returns (uint256 amount, uint256 depositTime, bool withdrawn, uint256 currentReward, bool canWithdraw)
    {
        require(_depositId < userDeposits[_user].length, "Invalid deposit ID");
        Deposit memory userDeposit = userDeposits[_user][_depositId];

        uint256 timeElapsed = block.timestamp - userDeposit.depositTime;
        uint256 reward = calculateReward(userDeposit.amount, timeElapsed);

        return
            (userDeposit.amount, userDeposit.depositTime, userDeposit.withdrawn, reward, timeElapsed >= MIN_LOCK_PERIOD);
    }

    function emergencyWithdraw() external onlyOwner {
        // @audit-info : there should be a check here to ensure that the user is not an address 0
        uint256 balance = token.balanceOf(address(this));
        
        require(token.transfer(owner, balance), "Transfer failed");
    }

    function updateOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        owner = _newOwner;
    }

    function getContractStats()
        external
        view
        returns (uint256 _totalLocked, uint256 _totalRewardsPaid, uint256 _contractBalance)
    {
        return (totalLocked, totalRewardsPaid, token.balanceOf(address(this)));
    }
}
