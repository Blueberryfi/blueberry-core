pragma solidity ^0.8.9;

import './IStakingRewards.sol';

interface IStakingRewardsEx is IStakingRewards {
    function rewardsToken() external view returns (address);

    function stakingToken() external view returns (address);
}
