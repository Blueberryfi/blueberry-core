// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IRewarder {
    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256, bool) external;

    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    function extraRewards(uint256) external view returns (address);

    function extraRewardsLength() external view returns (uint256);

    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function stakeFor(address _for, uint256 _amount) external returns (bool);

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function getReward() external returns (bool);

    function queueNewRewards(uint256 _rewards) external returns (bool);

    function addExtraReward(address _reward) external returns (bool);

    function clearExtraRewards() external;

    function rewardManager() external view returns (address);

    function notifyRewardAmount(uint256 reward) external;
}
