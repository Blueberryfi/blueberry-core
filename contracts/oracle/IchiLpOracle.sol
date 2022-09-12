// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import './UsingBaseOracle.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/ichi/IICHIVault.sol';

contract IchiLpOracle is UsingBaseOracle, IBaseOracle {
    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /**
     * @notice Fetches the token/ETH price, with 18 decimals of precision.
     * @param underlying The underlying token address for which to get the price.
     * @return Price denominated in ETH (scaled by 1e18)
     */
    function getETHPx(address underlying)
        external
        view
        override
        returns (uint256)
    {
        return _price(underlying);
    }

    /**
     * @notice Fetches the token/ETH price, with 18 decimals of precision.
     * @param token an ICHI oneToken
     * @return uint price in ETH
     */
    function _price(address token) internal view returns (uint256) {
        IICHIVault vault = IICHIVault(token);
        IERC20Metadata token0 = IERC20Metadata(vault.token0());
        IERC20Metadata token1 = IERC20Metadata(vault.token1());
        (uint256 amount0, uint256 amount1) = vault.getTotalAmounts();
        uint256 token0EthPrice = base.getETHPx(address(token0));
        uint256 token1EthPrice = base.getETHPx(address(token1));

        // (amount0 * price0 + amount1 * price1) / totalSupply
        return
            (((amount0 * token0EthPrice) /
                10**uint256(token0.decimals()) +
                (amount1 * token1EthPrice) /
                10**uint256(token1.decimals())) * 1e18) / vault.totalSupply();
    }
}
