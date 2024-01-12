// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface ICvxExtraRewarder {
    function getReward() external;

    function getReward(address account) external;

    function rewardToken() external view returns (address);

    function rewardPerToken() external view returns (uint256);
}
