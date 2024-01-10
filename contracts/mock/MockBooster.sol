// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/convex/IRewarder.sol";
import "./MockERC20.sol";

contract MockBooster {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    uint256 public constant REWARD_MULTIPLIER_DENOMINATOR = 10000;

    //index(pid) -> pool
    PoolInfo[] public poolInfo;

    mapping(address => uint256) public getRewardMultipliers;

    bool public isShutdown;

    function setShutdown(bool _isShutdown) external {
        isShutdown = _isShutdown;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //create a new pool
    function addPool(
        address _lptoken,
        address _token,
        address _gauge,
        address _crvRewards,
        address _stash
    ) external returns (bool) {
        //add the new pool
        poolInfo.push(
            PoolInfo({
                lptoken: _lptoken,
                token: _token,
                gauge: _gauge,
                crvRewards: _crvRewards,
                stash: _stash,
                shutdown: false
            })
        );
        return true;
    }

    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool) {
        require(!isShutdown, "shutdown");
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.shutdown == false, "pool is closed");

        //send to proxy to stake
        address lptoken = pool.lptoken;
        IERC20(lptoken).safeTransferFrom(msg.sender, address(this), _amount);

        address token = pool.token;
        if (_stake) {
            //mint here and send to rewards on user behalf
            MockERC20(token).mintWithAmount(_amount);
            address rewardContract = pool.crvRewards;
            IERC20(token).safeApprove(rewardContract, 0);
            IERC20(token).safeApprove(rewardContract, _amount);
            IRewarder(rewardContract).stakeFor(msg.sender, _amount);
        } else {
            //add user balance directly
            MockERC20(token).mintWithAmount(_amount);
        }

        return true;
    }

    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external returns (bool) {
        _withdraw(_pid, _amount, msg.sender, _to);
        return true;
    }

    function withdraw(uint256 _pid, uint256 _amount) public returns (bool) {
        _withdraw(_pid, _amount, msg.sender, msg.sender);
        return true;
    }

    //withdraw lp tokens
    function _withdraw(uint256 _pid, uint256 _amount, address _from, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        address lptoken = pool.lptoken;

        //remove lp balance
        address token = pool.token;

        MockERC20(token).burn(_from, _amount);

        //return lp tokens
        IERC20(lptoken).safeTransfer(_to, _amount);
    }

    function setRewardMultipliers(address rewarder, uint256 multiplier) external {
        getRewardMultipliers[rewarder] = multiplier;
    }
}
