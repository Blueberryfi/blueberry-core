// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {ICvxBooster} from "../../interfaces/convex/ICvxBooster.sol";

interface IAuraBooster is ICvxBooster{

    function getRewardMultipliers(address rewarder) external view returns (uint256);
    
    function REWARD_MULTIPLIER_DENOMINATOR() external view returns (uint256);
}