// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/// @dev Slimmed down interface for the BaseRewardPool contract used by Aura
/// the full interface can be found here: 
interface IAuraRewarder {
    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256, bool) external;

    function extraRewards(uint256) external view returns (address);

    function extraRewardsLength() external view returns (uint256);

    function stakingToken() external view returns (address);

    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function getReward(
        address _account,
        bool _claimExtras
    ) external returns (bool);

    function getReward() external returns (bool);
}
