// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IAuraExtraRewarder {
    function getReward() external;

    function rewardPerToken() external view returns (uint256);

    function rewardToken() external view returns (address);
}
