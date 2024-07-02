// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";

/**
 * @title IPendleSpell
 * @notice Interface for the Pendle Spell contract.
 */
interface IPendleSpell is IBasicSpell {
    /**
     * @notice Allows the owner to add a new strategy.
     * @param token Address of the PT.
     * @param market Address of the Pendle market.
     * @param minCollSize, USD price of minimum isolated collateral for given strategy, based 1e18
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address token, address market, uint256 minCollSize, uint256 maxPosSize) external;

    /**
     * @notice Swaps the debt token to a Pendle PT token
     * @param param Configuration for opening a position.
     * @param data Data required for swapping the debt token to the PT token.
     */
    function openPosition(OpenPosParam calldata param, bytes memory data) external;

    /**
     * @notice Swaps the debt token to a Pendle PT token
     * @param param Configuration for closing a position.
     * @param data Data required for swapping the debt token to the PT token.
     */
    function closePosition(ClosePosParam calldata param, bytes memory data) external;

    /// @notice Returns the address of the Pendle Router
    function getPendleRouter() external view returns (address);

    /// @notice Returns the address of the Pendle token.
    function getPendle() external view returns (address);
}
