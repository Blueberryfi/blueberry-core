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
import "abdk-libraries-solidity/ABDKMath64x64.sol";

import "./UsingBaseOracle.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IBalancerVault.sol";

/**
 * @author BlueberryProtocol
 * @title Balancer Pair Oracle
 * @notice Oracle contract which privides price feeds of Balancer Pair tokens
 * @dev Implented Fair Lp Pricing
 *      Ref: https://blog.alphaventuredao.io/fair-lp-token-pricing/
 */
contract BalancerPairOracle is UsingBaseOracle, IBaseOracle {
    using ABDKMath64x64 for int128;
    uint256 private constant DECIMALS = 12;

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /// @notice Return the USD value of given Curve Lp, with 18 decimals of precision.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external override returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);
        IBalancerVault vault = IBalancerVault(pool.getVault());

        // Reentrancy guard to prevent flashloan attack
        checkReentrancy(vault);

        (address[] memory tokens, , ) = vault.getPoolTokens(pool.getPoolId());
        uint256[] memory weights = pool.getNormalizedWeights();

        require(tokens.length == 2, "num tokens must be 2");

        // This solution is from Balancer team
        // Ref: https://twitter.com/0xa9a/status/1539554145048395777/photo/1
        //
        // BPT price of weighted pool = k/s * exp(w1 * log(p1/w1)) * exp(w2 * log(p2/w2))
        //
        // k: invariant of pool => pool.getInvariant()
        // s: supply of pool => pool.totalSupply()
        // w1: weight of token1
        // w2: weight of token2
        // p1: price of token1
        // p2: price of token2

        uint256 k = pool.getInvariant();
        uint256 s = pool.totalSupply();
        int128 w1 = ABDKMath64x64.divu(weights[0], 1e18);
        int128 w2 = ABDKMath64x64.divu(weights[1], 1e18);
        int128 p1 = ABDKMath64x64.divu(base.getPrice(tokens[0]), 1e18);
        int128 p2 = ABDKMath64x64.divu(base.getPrice(tokens[1]), 1e18);

        return
            (1e18 *
                k *
                (
                    ABDKMath64x64.mul(
                        ((w1.mul((p1.div(w1)).ln()))).exp(),
                        ((w2.mul((p2.div(w2)).ln()))).exp()
                    )
                ).toUInt()) / s;
    }

    /// @dev makes a no-op call to the Balancer Vault using the manageUserBalance function.
    /// Calling this function with no argument has absolutely no effect on the state but has
    /// the benefit of ensuring that the reentrancy guard has not been engaged.
    /// In the case of this exploit, this checkReentrancy() call would revert the getPrice() call and block this attack.
    /// Following the suggestion from Sentiment protocol verfied on Apr-05-2023.
    function checkReentrancy(IBalancerVault vault) internal {
        vault.manageUserBalance(new IBalancerVault.UserBalanceOp[](0));
    }
}
