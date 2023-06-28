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

import "./UsingBaseOracle.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IBalancerVault.sol";
import "../libraries/FixedPointMathLib.sol";

/**
 * @author BlueberryProtocol
 * @title Composable Stable Balancer LP Oracle
 * @notice Oracle contract which privides price feeds of Composable Stable Balancer LP tokens
 */
contract CompStableBPTOracle is UsingBaseOracle, IBaseOracle {
    using FixedPointMathLib for uint256;

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /// @notice Return the USD value of given Balancer Lp, with 18 decimals of precision.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external override returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);
        IBalancerVault vault = IBalancerVault(pool.getVault());

        // Reentrancy guard to prevent flashloan attack
        checkReentrancy(vault);

        (address[] memory tokens, , ) = vault
            .getPoolTokens(pool.getPoolId());

        uint256 length = tokens.length;
        uint256 minPrice = type(uint256).max;
        for(uint256 i; i != length; ++i) {
            if (tokens[i] == token) continue;
            uint256 price = base.getPrice(tokens[i]);
            minPrice = (price < minPrice) ? price : minPrice;
        }
        return minPrice.mulWadDown(pool.getRate());
    }

    function checkReentrancy(IBalancerVault vault) internal {
        vault.manageUserBalance(new IBalancerVault.UserBalanceOp[](0));
    }
}
