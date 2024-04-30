// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/convex/IRewarder.sol";

interface IDeposit {
    function isShutdown() external view returns (bool);

    function balanceOf(address _account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function poolInfo(uint256) external view returns (address, address, address, address, address, bool);

    function rewardClaimed(uint256, address, uint256) external;

    function withdrawTo(uint256, uint256, address) external;

    function claimRewards(uint256, address) external returns (bool);

    function rewardArbitrator() external returns (address);

    function setGaugeRedirect(uint256 _pid) external returns (bool);

    function owner() external returns (address);

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);
}

contract MockWrappedStashToken {
    IERC20 public baseToken;

    constructor(address _baseToken) {
        baseToken = IERC20(_baseToken);
    }
}

contract MockVirtualBalanceRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    MockWrappedStashToken private immutable _rewardToken;
    uint256 public constant duration = 7 days;

    IDeposit public immutable deposits;

    uint256 public rewardPerToken;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public queuedRewards = 0;
    uint256 public currentRewards = 0;
    uint256 public historicalRewards = 0;
    uint256 public constant newRewardRatio = 830;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @param deposit_  Parent deposit pool e.g cvxCRV staking in BaseRewardPool
     * @param reward_   The rewards token e.g 3Crv
     */
    constructor(address deposit_, address reward_) {
        deposits = IDeposit(deposit_);
        _rewardToken = new MockWrappedStashToken(reward_);
    }

    /**
     * @notice Update rewards earned by this account
     */
    modifier updateReward(address account) {
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function setRewardPerToken(uint256 _rewardPerToken) external {
        rewardPerToken = _rewardPerToken;
    }

    function setReward(address user, uint256 amount) external {
        rewards[user] = amount;
    }

    function totalSupply() public view returns (uint256) {
        return deposits.totalSupply();
    }

    function balanceOf(address account) public view returns (uint256) {
        return deposits.balanceOf(account);
    }

    function earned(address account) public view returns (uint256) {
        return rewards[account];
    }

    /**
     * @notice  Update reward, emit, call linked reward's stake
     * @dev     Callable by the deposits address which is the BaseRewardPool
     *          this updates the virtual balance of this user as this contract doesn't
     *          actually hold any staked tokens it just diributes reward tokens
     */
    function stake(address _account, uint256 amount) external updateReward(_account) {
        require(msg.sender == address(deposits), "!authorized");
        // require(amount > 0, 'VirtualDepositRewardPool: Cannot stake 0');
        emit Staked(_account, amount);
    }

    /**
     * @notice  Withdraw stake and update reward, emit, call linked reward's stake
     * @dev     See stake
     */
    function withdraw(address _account, uint256 amount) public updateReward(_account) {
        require(msg.sender == address(deposits), "!authorized");
        //require(amount > 0, 'VirtualDepositRewardPool : Cannot withdraw 0');

        emit Withdrawn(_account, amount);
    }

    /**
     * @notice  Get rewards for this account
     * @dev     This can be called directly but it is usually called by the
     *          BaseRewardPool getReward when the BaseRewardPool loops through
     *          it's extraRewards array calling getReward on all of them
     */
    function getReward(address _account) public updateReward(_account) {
        uint256 reward = earned(_account);
        if (reward > 0) {
            rewards[_account] = 0;
            _rewardToken.baseToken().safeTransfer(_account, reward);
            emit RewardPaid(_account, reward);
        }
    }

    function getReward() external {
        getReward(msg.sender);
    }

    function donate(uint256 _amount) external returns (bool) {
        IERC20(_rewardToken.baseToken()).safeTransferFrom(msg.sender, address(this), _amount);
        queuedRewards = queuedRewards.add(_amount);
    }

    function queueNewRewards(uint256 _rewards) external {
        _rewards = _rewards.add(queuedRewards);

        if (block.timestamp >= periodFinish) {
            _notifyRewardAmount(_rewards);
            queuedRewards = 0;
            return;
        }

        //et = now - (finish-duration)
        uint256 elapsedTime = block.timestamp.sub(periodFinish.sub(duration));
        //current at now: rewardRate * elapsedTime
        uint256 currentAtNow = rewardRate * elapsedTime;
        uint256 queuedRatio = currentAtNow.mul(1000).div(_rewards);
        if (queuedRatio < newRewardRatio) {
            _notifyRewardAmount(_rewards);
            queuedRewards = 0;
        } else {
            queuedRewards = _rewards;
        }
    }

    function rewardToken() external view returns (address) {
        return address(_rewardToken);
    }

    function baseToken() external view returns (address) {
        return address(_rewardToken.baseToken());
    }

    function _notifyRewardAmount(uint256 reward) internal updateReward(address(0)) {
        historicalRewards = historicalRewards.add(reward);
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(duration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            reward = reward.add(leftover);
            rewardRate = reward.div(duration);
        }
        currentRewards = reward;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(duration);
        emit RewardAdded(reward);
    }
}
