// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IAuraExtraRewarder {
    function getReward() external;

    function getReward(address account) external;

    function rewardPerToken() external view returns (uint256);

    function rewardToken() external view returns (address);
}
