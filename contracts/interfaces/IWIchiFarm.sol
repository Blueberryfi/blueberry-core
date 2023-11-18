// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "./IERC20Wrapper.sol";
import "./ichi/IIchiV2.sol";
import "./ichi/IIchiFarm.sol";


/// @title IWIchiFarm
/// @notice This is the interface for the WIchiFarm contract
/// @dev WIchiFarm contract integrates both ERC1155 and ERC20Wrapper functionalities.
interface IWIchiFarm is IERC1155Upgradeable, IERC20Wrapper {
    
    /// @notice Fetch the address of the legacy ICHI token.
    /// @return A IIchiV2 interface representing the legacy ICHI token.
    function ICHI() external view returns (IIchiV2);

    /// @notice Fetch the address of the ICHI farming contract.
    /// @return A IIchiFarm interface representing the ICHI farming contract.
    function ichiFarm() external view returns (IIchiFarm);

    /// @notice Decode the given ID to obtain its constituent values.
    /// @param id The encoded ID.
    /// @return Two uint256 values derived from the given ID.
    function decodeId(uint256 id) external pure returns (uint256, uint256);

    /// @notice Mint the corresponding ERC1155 tokens based on a given pid and amount.
    /// @param pid The product id, representing a specific token.
    /// @param amount The amount of tokens to be minted.
    /// @return A uint256 representing the minted token's ID.
    function mint(uint256 pid, uint256 amount) external returns (uint256);

    /// @notice Burn the ERC1155 tokens based on a given id and amount.
    /// @param id The ID of the ERC1155 token to be burned.
    /// @param amount The amount of tokens to be burned.
    function burn(uint256 id, uint256 amount) external returns (uint256 pid);
}
