// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IRewarder {
    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256, bool) external;

    function extraRewards(uint256) external view returns (address);

    function extraRewardsLength() external view returns (uint256);

    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function stakeFor(address _for, uint256 _amount) external returns (bool);
}
