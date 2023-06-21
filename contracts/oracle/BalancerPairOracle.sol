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
    uint256 private constant DECIMALS = 12;

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /**
     * @notice convert decimal parameter to 64x64 fixed point representation
     * @param value parameter to convert
     * @return 64x64 fixed point representation of parameter
     */
    function _toParameter64x64(uint256 value) private pure returns (int128) {
        return ABDKMath64x64.divu(value, 10 ** DECIMALS);
    }

    /**
     * @notice convert 64x64 fixed point representation to decimal parameter
     * @param value parameter to convert
     * @return
     */
    function _toUint256(int128 value) private pure returns (uint256) {
        return ABDKMath64x64.mulu(value, 10 ** DECIMALS);
    }

    /// @notice Return fair reserve amounts given spot reserves, weights, and fair prices.
    /// @param resA Reserve of the first asset
    /// @param resB Reserve of the second asset
    /// @param wA Weight of the first asset
    /// @param wB Weight of the second asset
    /// @param pxA Fair price of the first asset
    /// @param pxB Fair price of the second asset
    function computeFairReserves(
        int128 resA,
        int128 resB,
        uint256 wA,
        uint256 wB,
        int128 pxA,
        int128 pxB
    ) internal view returns (uint256 fairResA, uint256 fairResB) {
        // NOTE: wA + wB = 1 (normalize weights)
        // constant product = resA^wA * resB^wB
        // constraints:
        // - fairResA^wA * fairResB^wB = constant product
        // - fairResA * pxA / wA = fairResB * pxB / wB
        // Solving equations:
        // --> fairResA^wA * (fairResA * (pxA * wB) / (wA * pxB))^wB = constant product
        // --> fairResA / r1^wB = constant product
        // --> fairResA = resA^wA * resB^wB * r1^wB
        // --> fairResA = resA * (resB/resA)^wB * r1^wB = resA * (r1/r0)^wB

        int128 r0 = ABDKMath64x64.div(resA, resB);
        int128 r1 = ABDKMath64x64.div(
            ABDKMath64x64.mul(pxB, _toParameter64x64(wA)),
            ABDKMath64x64.mul(pxA, _toParameter64x64(wB))
        );

        // fairResA = resA * (r1 / r0) ^ wB
        // fairResB = resB * (r0 / r1) ^ wA
        if (r0 > r1) {
            int128 ratio = ABDKMath64x64.div(r1, r0);

            fairResA = _toUint256(
                ABDKMath64x64.mul(resA, ABDKMath64x64.pow(ratio, wB))
            );
            fairResB = _toUint256(
                ABDKMath64x64.div(resB, ABDKMath64x64.pow(ratio, wA))
            );
        } else {
            int128 ratio = ABDKMath64x64.div(r0, r1);

            fairResA = _toUint256(
                ABDKMath64x64.div(resA, ABDKMath64x64.pow(ratio, wB))
            );
            fairResB = _toUint256(
                ABDKMath64x64.mul(resB, ABDKMath64x64.pow(ratio, wA))
            );
        }
    }

    /// @notice Return the USD value of given Curve Lp, with 18 decimals of precision.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external override returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);
        IBalancerVault vault = IBalancerVault(pool.getVault());

        // Reentrancy guard to prevent flashloan attack
        checkReentrancy(vault);

        (address[] memory tokens, uint256[] memory balances, ) = vault
            .getPoolTokens(pool.getPoolId());
        uint256[] memory weights = pool.getNormalizedWeights();
        require(tokens.length == 2, "num tokens must be 2");
        address tokenA = tokens[0];
        address tokenB = tokens[1];
        uint8 decimalsA = IERC20Metadata(tokenA).decimals();
        uint8 decimalsB = IERC20Metadata(tokenB).decimals();

        uint256 price0 = base.getPrice(tokenA);
        uint256 price1 = base.getPrice(tokenB);

        (uint256 fairResA, uint256 fairResB) = computeFairReserves(
            _toParameter64x64(balances[0] * (10 ** (18 - uint256(decimalsA)))),
            _toParameter64x64(balances[1] * (10 ** (18 - uint256(decimalsB)))),
            weights[0] / (10 ** 16),
            weights[1] / (10 ** 16),
            _toParameter64x64(price0),
            _toParameter64x64(price1)
        );

        // use fairReserveA and fairReserveB to compute LP token price
        // LP price = (fairResA * pxA + fairResB * pxB) / totalLPSupply
        return (fairResA * price0 + fairResB * price1) / pool.totalSupply();
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
