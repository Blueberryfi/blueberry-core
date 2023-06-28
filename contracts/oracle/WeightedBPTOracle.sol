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
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IBalancerVault.sol";
import "../libraries/balancer/FixedPoint.sol";

/**
 * @author BlueberryProtocol
 * @title Weighted Balancer LP Oracle
 * @notice Oracle contract which privides price feeds of Weighted Balancer LP tokens
 */
contract WeightedBPTOracle is UsingBaseOracle, IBaseOracle {
    using FixedPoint for uint256;

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /// @notice Return the USD value of given Balancer Lp, with 18 decimals of precision.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external override returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);
        IBalancerVault vault = IBalancerVault(pool.getVault());

        // Reentrancy guard to prevent flashloan attack
        checkReentrancy(vault);

        (address[] memory tokens, uint256[] memory balances, ) = vault
            .getPoolTokens(pool.getPoolId());

        uint256[] memory weights = pool.getNormalizedWeights();

        uint256 length = weights.length;
        uint256 temp = 1e18;
        uint256 invariant = 1e18;
        for(uint256 i; i < length; i++) {
            temp = temp.mulDown(
                (base.getPrice(tokens[i]).divDown(weights[i]))
                .powDown(weights[i])
            );
            invariant = invariant.mulDown(
                (balances[i] * 10 ** (18 - IERC20Metadata(tokens[i]).decimals()))
                .powDown(weights[i])
            );
        }
        return invariant
            .mulDown(temp)
            .divDown(IBalancerPool(token).totalSupply());
    }

    function checkReentrancy(IBalancerVault vault) internal {
        vault.manageUserBalance(new IBalancerVault.UserBalanceOp[](0));
    }
}
