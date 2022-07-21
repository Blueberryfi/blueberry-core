// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IStakingRewards {
    function rewardPerToken() external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;
}
