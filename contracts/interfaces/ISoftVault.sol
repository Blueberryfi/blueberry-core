// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IBErc20 } from "./money-market/IBErc20.sol";

import { IProtocolConfig } from "./IProtocolConfig.sol";

/**
 * @title ISoftVault
 * @notice Interface for the SoftVault, allowing deposits and withdrawals of assets.
 * @dev The SoftVault is responsible for handling user deposits,
 *      withdrawals, and interactions with underlying Blueberry Money Market bTokens.
 */
interface ISoftVault is IERC20Upgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Event emitted when an account deposits assets.
     * @param account Address of the account that deposited.
     * @param amount The amount of underlying assets deposited.
     * @param shareAmount The corresponding amount of vault shares minted.
     */
    event Deposited(address indexed account, uint256 amount, uint256 shareAmount);

    /**
     * @notice Event emitted when an account withdraws assets.
     * @param account Address of the account that withdrew.
     * @param amount The amount of underlying assets withdrawn.
     * @param shareAmount The corresponding amount of vault shares burned.
     */
    event Withdrawn(address indexed account, uint256 amount, uint256 shareAmount);

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the corresponding Blueberry Money Market bToken for this vault.
     * @return A Blueberry Money Market bToken interface.
     */
    function getBToken() external view returns (IBErc20);

    /**
     * @notice Get the underlying ERC20 token for this vault.
     * @return An ERC20 interface of the underlying token.
     */
    function getUnderlyingToken() external view returns (IERC20Upgradeable);

    /**
     * @notice Retrieves the protocol configuration for this vault.
     * @return Address of the protocol configuration.
     */
    function getConfig() external view returns (IProtocolConfig);

    /**
     * @notice Deposit a specified amount of the underlying asset into the vault.
     * @dev This function will convert the deposited assets into the corresponding bToken.
     * @param amount The amount of the underlying asset to deposit.
     * @return shareAmount The amount of vault shares minted for the deposit.
     */
    function deposit(uint256 amount) external returns (uint256 shareAmount);

    /**
     * @notice Withdraw a specified amount of the underlying asset from the vault.
     * @dev This function will convert the corresponding bToken back into the underlying asset.
     * @param amount The amount of vault shares to redeem.
     * @return withdrawAmount The amount of the underlying asset withdrawn.
     */
    function withdraw(uint256 amount) external returns (uint256 withdrawAmount);
}
