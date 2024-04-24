// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";
import { IWAuraBooster } from "../IWAuraBooster.sol";

/**
 * @title IAuraSpell
 * @notice Interface for the Aura Spell contract.
 */
interface IAuraSpell is IBasicSpell {
    /**
     * @notice Allows the owner to add a new strategy.
     * @param bpt Address of the Balancer Pool Token.
     * @param minCollSize, USD price of minimum isolated collateral for given strategy, based 1e18
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address bpt, uint256 minCollSize, uint256 maxPosSize) external;

    /**
     * @notice Adds liquidity to a Balancer pool and stakes the resultant tokens in Aura.
     * @param param Configuration for opening a position.
     * @param minimumBPT The minimum amount of BPT tokens to receive from the join.
     */
    function openPositionFarm(OpenPosParam calldata param, uint256 minimumBPT) external;

    /// @notice Returns the address of the wrapped Aura Booster contract.
    function getWAuraBooster() external view returns (IWAuraBooster);

    /// @notice Returns the address of the AURA token.
    function getAuraToken() external view returns (address);

    /**
     * @notice Closes a position from Balancer pool and exits the Aura farming.
     * @param param Parameters for closing the position
     * @param expectedRewards Expected reward amounts for each reward token
     * @param swapDatas Data required for swapping reward tokens to the debt token
     */
    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata expectedRewards,
        bytes[] calldata swapDatas
    ) external;
}
