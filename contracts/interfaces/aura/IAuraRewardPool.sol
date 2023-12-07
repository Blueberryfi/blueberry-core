// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IAuraRewardPool {

    function getReward() external;

    function getReward(address _account) external;

    function rewardPerToken() external view returns (uint256);
}
