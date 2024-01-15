// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBalancerV2Pool } from "./IBalancerV2Pool.sol";

interface IBalancerV2StablePool is IBalancerV2Pool {
    function getRate() external view returns (uint256);

    function getBptIndex() external view returns (uint256);

    function getRateProviders() external view returns (address[] memory);
}
