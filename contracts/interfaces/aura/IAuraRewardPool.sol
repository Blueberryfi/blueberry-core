// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IAuraRewardPool {

    function getReward() external;

    function getReward(address _account) external;

    function rewardPerToken() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function rewards(address _account) external view returns (uint256);

    function earned(address _account) external view returns (uint256);
}
