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

    /// @dev Return the value of the given input as ETH per unit, multiplied by 2**112.
    /// @param pair The Uniswap pair to check the value.
    function getETHPx(address pair) external view override returns (uint256) {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();

        uint256 px0 = base.getETHPx(token0); // in 2**112
        uint256 px1 = base.getETHPx(token1); // in 2**112

        uint256 t0Decimal = IERC20Metadata(token0).decimals();
        uint256 t1Decimal = IERC20Metadata(token1).decimals();

        uint256 totalReserve = (r0 * px0) /
            10**t0Decimal +
            (r1 * px1) /
            10**t1Decimal;

        return (totalReserve * 10**18) / totalSupply;
    }
}
