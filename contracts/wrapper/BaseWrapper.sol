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

import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

import "../utils/BlueberryErrors.sol" as Errors;

/**
 * @title BaseWrapper
 * @author BlueberryProtocol
 * @notice Contains validation logic for all wrappers along with ERC1155 instance.
 * @dev This contract must be inherited by all wrapper contracts.
 */
abstract contract BaseWrapper is ERC1155Upgradeable {
    /**
     * @notice Verifies that the provided token id is unique and has not been minted yet
     * @param id The token id to validate
     */
    function _validateTokenId(uint256 id) internal view {
        if (balanceOf(msg.sender, id) != 0) {
            revert Errors.DUPLICATE_TOKEN_ID(id);
        }
    }
}
