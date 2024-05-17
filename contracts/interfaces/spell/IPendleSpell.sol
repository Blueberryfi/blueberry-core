// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";
import { IWPendleGauge } from "../IWPendleGauge.sol";

/**
 * @title IPendleSpell
 * @notice Interface for the Pendle Spell contract.
 */
interface IPendleSpell is IBasicSpell {
    /**
     * @notice Allows the owner to add a new strategy.
     * @param token Address of the PT or LP token.
     * @param minCollSize, USD price of minimum isolated collateral for given strategy, based 1e18
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address token, uint256 minCollSize, uint256 maxPosSize) external;

    /**
     * @notice Swaps the debt token to a Pendle PT token
     * @param param Configuration for opening a position.
     * @param minimumPt The minimum amount of PT tokens to receive from the swap.
     * @param data Data required for swapping the debt token to the PT token.
     */
    function openPosition(OpenPosParam calldata param, uint256 minimumPt, bytes memory data) external;

    // /**
    //  * @notice Adds liquidity to a Pendle Pool and stakes it within PenPie.
    //  * @param param Configuration for opening a position.
    //  * @param minimumLP The minimum amount of LP tokens to receive from the join.
    //  * @param data Data required for adding liquidity to the Pendle Pool.
    //  */
    // function openPositionFarm(OpenPosParam calldata param, uint256 minimumLP, bytes memory data) external;

    /**
     * @notice Swaps the debt token to a Pendle PT token
     * @param param Configuration for closing a position.
     * @param data Data required for swapping the debt token to the PT token.
     */
    function closePosition(ClosePosParam calldata param, bytes memory data) external;

    // /**
    //  * @notice Closes a position from Pendle pool and exits the PenPie farming.
    //  * @param param Parameters for closing the position
    //  * @param expectedRewards Expected reward amounts for each reward token
    //  * @param swapDatas Data required for swapping reward tokens to the debt token
    //  */
    // function closePositionFarm(
    //     ClosePosParam calldata param,
    //     uint256[] calldata expectedRewards,
    //     bytes[] calldata swapDatas
    // ) external;

    /// @notice Returns the address of the Pendle token.
    function getPendle() external view returns (address);

    // /// @notice Returns the address of the PNP token.
    // function getPenPie() external view returns (address);
}
