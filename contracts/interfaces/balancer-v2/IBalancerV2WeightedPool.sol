// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBalancerV2Pool } from "./IBalancerV2Pool.sol";

interface IBalancerV2WeightedPool is IBalancerV2Pool {
    function getNormalizedWeights() external view returns (uint256[] memory);

    function getInvariant() external view returns (uint256);
}
