// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./UsingBaseOracle.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/ichi/IICHIVault.sol";

/**
 * @author gmspacex
 * @title Ichi Vault Oracle
 * @notice Oracle contract provides price feeds of Ichi Vault tokens
 * @dev The logic of this oracle is using legacy & traditional mathematics of Uniswap V2 Lp Oracle.
 *      However, it is strong at flash loan attack and price manipulations.
 *      The minting logics of Ichi Vault when you deposit underlying assets on the vault
 *      depends on the price of token1 of the vault.
 *      Ichi Vault is already using secured Uni V3 Price Oracle. and here is the minting logics
 *      uint256 price = _fetchSpot(token0, token1, currentTick(), PRECISION);                       MockIchiVault#L239
 *      uint256 twap = _fetchTwap(pool, token0, token1, twapPeriod, PRECISION);                     MockIchiVault#L243
 *      uint256 deposit0PricedInToken1 = (deposit0 * ((price < twap) ? price : twap)) / PRECISION;  MockIchiVault#L255
 *      shares = deposit1 + deposit0PricedInToken1;                                                 MockIchiVault#L273
 *      _mint(to, shares);                                                                          MockIchiVault#L280
 */
contract IchiVaultOracle is UsingBaseOracle, IBaseOracle {
    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /**
     * @notice Return vault token price in USD, with 18 decimals of precision.
     * @param token The vault token to get the price of.
     * @return price USD price of token in 18 decimal
     */
    function getPrice(address token) external view override returns (uint256) {
        IICHIVault vault = IICHIVault(token);
        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return 0;

        address token0 = vault.token0();
        address token1 = vault.token1();

        (uint256 r0, uint256 r1) = vault.getTotalAmounts();
        uint256 px0 = base.getPrice(address(token0));
        uint256 px1 = base.getPrice(address(token1));
        uint256 t0Decimal = IERC20Metadata(token0).decimals();
        uint256 t1Decimal = IERC20Metadata(token1).decimals();

        uint256 totalReserve = (r0 * px0) /
            10**t0Decimal +
            (r1 * px1) /
            10**t1Decimal;

        return (totalReserve * 1e18) / totalSupply;
    }
}
