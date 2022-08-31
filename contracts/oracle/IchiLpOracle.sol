// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import './UsingBaseOracle.sol';
import '../utils/BBMath.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/IUniswapV2Pair.sol';

contract IchiLpOracle is UsingBaseOracle, IBaseOracle {
    using BBMath for uint256;

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /// @dev Return the value of the given input as ETH per unit, multiplied by 2**112.
    /// @param pair The Uniswap pair to check the value.
    function getETHPx(address pair) external view override returns (uint256) {
        return 2**112 * 10**10;
    }
}
