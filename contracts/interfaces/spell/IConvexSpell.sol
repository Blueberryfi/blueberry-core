// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";
import { ICurveOracle } from "../ICurveOracle.sol";
import { IWConvexBooster } from "../IWConvexBooster.sol";

/**
 * @title IConvexSpell
 * @notice Interface for the Convex Spell contract.
 */
interface IConvexSpell is IBasicSpell {
    struct ClosePositionFarmParam {
        ClosePosParam param;
        uint256[] amounts;
        bytes[] swapDatas;
    }

    /**
     * @notice Closes an existing liquidity position, unstakes from Curve gauge, and swaps rewards.
     * @param closePosParam Struct containing all required parameters for closing a position.
     */
    function closePositionFarm(ClosePositionFarmParam calldata closePosParam) external;

    /**
     * @notice Adds liquidity to a Curve pool with two underlying tokens and stakes in Curve gauge.
     * @param param Struct containing all required parameters for opening a position.
     * @param minLPMint Minimum LP tokens expected to mint for slippage control.
     */
    function openPositionFarm(OpenPosParam calldata param, uint256 minLPMint) external;

    /**
     * @notice Adds a new strategy to the spell.
     * @param crvLp Address of the Curve LP token for the strategy.
     * @param minCollSize Minimum isolated collateral in USD for the strategy (with 1e18 precision).
     * @param maxPosSize Maximum position size in USD for the strategy (with 1e18 precision).
     */
    function addStrategy(address crvLp, uint256 minCollSize, uint256 maxPosSize) external;

    /// @notice Returns the address of the Cvx oracle.
    function getCrvOracle() external view returns (ICurveOracle);

    /// @notice Returns the address of the Cvx token.
    function getCvxToken() external view returns (address);

    /// @notice Returns the address of the wrapped Aura Booster contract.
    function getWConvexBooster() external view returns (IWConvexBooster);
}
