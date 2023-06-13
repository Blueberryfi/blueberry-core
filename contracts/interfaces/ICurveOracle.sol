// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./IBaseOracle.sol";

interface ICurveOracle is IBaseOracle {
    function getPoolInfo(
        address crvLp
    )
        external
        returns (address pool, address[] memory coins, uint256 virtualPrice);
}
