// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { IERC4626, IERC20 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/* solhint-enable max-line-length */

import { IERC20Wrapper } from "./IERC20Wrapper.sol";
import "./IApxETH.sol";

/**
 * @title IWERC4626
 * @author BlueberryProtocol
 * @notice This is the interface for the WApxEth contract
 */
interface IWERC4626 is IERC20Wrapper, IERC1155Upgradeable {
    /// @notice Emitted when a user stakes liquidity provider tokens and a new ERC1155 token is minted.
    event Minted(uint256 indexed id, uint256 amount);

    /// @notice Emitted when a user burns an ERC1155 token to claim rewards and close their position.
    event Burned(uint256 indexed id, uint256 amount);

    /**
     * @notice Mint an ERC1155 token corresponding to a staked amount in the ApxETH contract.
     * @param amount The amount of liquidity provider tokens to stake.
     * @return id The ID of the newly minted ERC1155 token representing the staked position.
     */
    function mint(uint256 amount) external returns (uint256 id);

    /**
     * @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
     * @param id The position id of the collateral
     * @param amount The amount of ERC1155 tokens to burn.
     * @return rewardAmount Returns the amount of rewards claimed.
     */
    function burn(uint256 id, uint256 amount) external returns (uint256 rewardAmount);

    /**
     * @notice Get the base asset of the vault.
     * @return The address of the base asset.
     */
    function getAsset() external view returns (IERC20);
}
