// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";

/**
 * @title IShortLongSpell
 * @notice Interface for the Short/Long Spell contract.
 */
interface IShortLongSpell is IBasicSpell {
    /**
     * @notice Add strategy to the spell
     * @param swapToken Address of token for given strategy
     * @param minCollSize USD price of minimum isolated collateral for given strategy, based 1e18
     * @param maxPosSize USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address swapToken, uint256 minCollSize, uint256 maxPosSize) external;

    /**
     * @notice Opens a position using provided parameters and swap data.
     * @dev This function first deposits an isolated underlying asset to Blueberry Money Market,
     * then borrows tokens from it. The borrowed tokens are swapped for another token using
     * ParaSwap and the resulting tokens are deposited into the softvault.
     *
     * Pre-conditions:
     * - Strategy for `param.strategyId` must exist.
     * - Collateral for `param.strategyId` and `param.collToken` must exist.
     *
     * @param param Parameters required to open the position, described in the `OpenPosParam` struct from {BasicSpell}.
     * @param swapData Specific data needed for the ParaSwap swap, structured in the `bytes` format from {PSwapLib}.
     */
    function openPosition(OpenPosParam calldata param, bytes calldata swapData) external;

    /**
     * @notice Externally callable function to close a position using provided parameters and swap data.
     * @dev This function is a higher-level action that internally calls `_withdraw` to manage the closing
     * of a position. It ensures the given strategy and collateral exist, and then carries out the required
     * operations to close the position.
     *
     * Pre-conditions:
     * - Strategy for `param.strategyId` must exist.
     * - Collateral for `param.strategyId` and `param.collToken` must exist.
     *
     * @param param Parameters required to close the position, described in the `ClosePosParam` struct.
     * @param swapData Specific data needed for the ParaSwap swap.
     */
    function closePosition(ClosePosParam calldata param, bytes calldata swapData) external;
}
