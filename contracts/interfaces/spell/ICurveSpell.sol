// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";
import { ICurveOracle } from "../ICurveOracle.sol";
import { IWCurveGauge } from "../IWCurveGauge.sol";

/**
 * @title ICurveSpell
 * @notice Interface for the Curve Spell contract.
 */
interface ICurveSpell is IBasicSpell {
    /**
     * @notice Add strategy to the spell
     * @param crvLp Address of crv lp token for given strategy
     * @param minPosSize, USD price of minimum position size for given strategy, based 1e18
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address crvLp, uint256 minPosSize, uint256 maxPosSize) external;

    /**
     * @notice Add liquidity to Curve pool with 2 underlying tokens, with staking to Curve gauge
     * @param minLPMint Desired LP token amount (slippage control)
     */
    function openPositionFarm(OpenPosParam calldata param, uint256 minLPMint) external;

    /**
     * @notice Closes a position from a Curve Gauge
     * @param param Parameters for closing the position
     * @param amounts Expected reward amounts for each reward token
     * @param swapDatas Data required for swapping reward tokens to the debt token
     * @param deadline Deadline for the transaction to be executed
     */
    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata amounts,
        bytes[] calldata swapDatas,
        uint256 deadline
    ) external;

    /// @notice Returns the Wrapped Curve Gauge contract address.
    function getWCurveGauge() external view returns (IWCurveGauge);

    /// @notice Returns the address of the Crv token.
    function getCrvToken() external view returns (address);

    /// @notice Returns the address of the Curve Oracle.
    function getCurveOracle() external view returns (ICurveOracle);
}
