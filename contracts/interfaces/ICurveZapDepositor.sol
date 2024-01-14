// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */

/**
 * @title ICurveZapDepositor
 * @notice Interface for the Curve Zap Depositor contract.
 */
interface ICurveZapDepositor {
    function add_liquidity(address pool, uint256[4] memory amounts, uint256 minMint) external;

    function remove_liquidity(address pool, uint256 amount, uint256[4] memory minAmounts) external;

    function remove_liquidity_one_coin(address pool, uint256 amount, int128 i, uint256 minAmount) external;
}
