// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import './UsingBaseOracle.sol';
import '../utils/BBMath.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/uniswap/v2/IUniswapV2Pair.sol';

contract UniswapV2Oracle is UsingBaseOracle, IBaseOracle {
    using BBMath for uint256;

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /// @dev Return the USD based price of the given input, multiplied by 10**18.
    /// @param pair The Uniswap pair to check the value.
    function getPrice(address pair) external view override returns (uint256) {
        IUniswapV2Pair pool = IUniswapV2Pair(pair);
        address token0 = pool.token0();
        address token1 = pool.token1();

        (uint256 r0, uint256 r1, ) = pool.getReserves();
        uint256 px0 = base.getPrice(token0); // in 2**112
        uint256 px1 = base.getPrice(token1); // in 2**112
        uint256 t0Decimal = IERC20Metadata(token0).decimals();
        uint256 t1Decimal = IERC20Metadata(token1).decimals();

        uint256 totalReserve = (r0 * px0) /
            10**t0Decimal +
            (r1 * px1) /
            10**t1Decimal;

        return (totalReserve * 1e18) / pool.totalSupply();
    }
}
