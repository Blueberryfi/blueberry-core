// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IRewardManager {
    struct RewardState {
        uint128 index;
        uint128 lastBalance;
    }

    function rewardState(address token) external view returns (RewardState memory);
}
