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
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/* solhint-enable max-line-length */

import { IERC20Wrapper } from "./IERC20Wrapper.sol";
import { IIchiV2 } from "./ichi/IIchiV2.sol";
import { IIchiFarm } from "./ichi/IIchiFarm.sol";

/**
 * @title IWIchiFarm
 * @author BlueberryProtocol
 * @notice This is the interface for the WIchiFarm contract
 */
interface IWIchiFarm is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Emitted when a user stakes liquidity provider tokens and a new ERC1155 token is minted.
    event Minted(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a user burns an ERC1155 token to claim rewards and close their position.
    event Burned(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /**
     * @notice Encodes pool id and ICHI per share into an ERC1155 token id
     * @param pid The pool id (The first 16-bits)
     * @param ichiPerShare Amount of ICHI per share, multiplied by 1e18 (The last 240-bits)
     * @return id The resulting ERC1155 token id
     */
    function encodeId(uint256 pid, uint256 ichiPerShare) external pure returns (uint256);

    /**
     * @notice Decode an encoded ID into two separate uint values.
     * @param id The encoded uint ID to decode.
     * @return The two individual uint values decoded from the provided ID.
     */
    function decodeId(uint256 id) external pure returns (uint256, uint256);

    /**
     * @notice Mint an ERC1155 token corresponding to a staked amount in a specific ICHI farm.
     * @param pid The pool ID representing the specific ICHI farm.
     * @param amount The amount of liquidity provider tokens to stake.
     * @return id The ID of the newly minted ERC1155 token representing the staked position.
     */
    function mint(uint256 pid, uint256 amount) external returns (uint256 id);

    /**
     * @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
     * @param id The Id of the ERC1155 token representing the staked position.
     * @param amount The amount of ERC1155 tokens to burn.
     * @return rewardAmount Returns the amount of ICHI rewards claimed.
     */
    function burn(uint256 id, uint256 amount) external returns (uint256);

    /// @notice Fetch the address of the legacy ICHI token.
    function getIchiV1() external view returns (IERC20Upgradeable);

    /// @notice Fetch the address of the ICHIV2 token.
    function getIchiV2() external view returns (IIchiV2);

    /// @notice Fetch the address of the ICHI farming contract.
    function getIchiFarm() external view returns (IIchiFarm);
}
