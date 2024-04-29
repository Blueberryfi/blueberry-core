// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBasicSpell } from "./IBasicSpell.sol";
import { IUniswapV3Router } from "../uniswap/IUniswapV3Router.sol";
import { IWIchiFarm } from "../IWIchiFarm.sol";

/**
 * @title IIchiSpell
 * @notice Interface for the Ichi Spell contract.
 */
interface IIchiSpell is IBasicSpell {
    /**
     * @notice Adds a strategy to the contract.
     * @param vault Address of the vault linked to the strategy.
     * @param minCollSize Minimum isolated collateral in USD, normalized to 1e18.
     * @param maxPosSize Maximum position size in USD, normalized to 1e18.
     */
    function addStrategy(address vault, uint256 minCollSize, uint256 maxPosSize) external;

    /**
     * @notice Deposits assets into an IchiVault.
     * @param param Parameters required for the open position operation.
     */
    function openPosition(OpenPosParam calldata param) external;

    /**
     * @notice Deposits assets into an IchiVault and then farms them in Ichi Farm.
     * @param param Parameters required for the open position operation.
     */
    function openPositionFarm(OpenPosParam calldata param) external;

    /**
     * @notice Withdraws assets from an ICHI Vault.
     * @param param Parameters required for the close position operation.
     */
    function closePosition(ClosePosParam calldata param) external;

    /**
     * @notice Withdraws assets from an ICHI Vault and from Ichi Farm.
     * @param param Parameters required for the close position operation.
     */
    function closePositionFarm(ClosePosParam calldata param) external;

    /// @notice Returns the Uniswap V3 router.
    function getUniswapV3Router() external view returns (IUniswapV3Router);

    /// @notice Returns the ICHI Farm wrapper.
    function getWIchiFarm() external view returns (IWIchiFarm);

    /// @notice Returns the address of the ICHIV2 token.
    function getIchiV2() external view returns (address);
}
