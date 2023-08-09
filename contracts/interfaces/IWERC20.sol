// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "./IERC20Wrapper.sol";

/// @title IWERC20
/// @notice This interface defines the functionality of the Wrapped ERC20 (WERC20) token.
/// @dev WERC20 tokens enable ERC20 tokens to be represented 
///      as ERC1155 tokens, providing batch transfer capabilities and more.
interface IWERC20 is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Fetch the balance of `user` for a specific underlying ERC20 token.
    /// @param token The address of the underlying ERC20 token.
    /// @param user The address of the user whose balance will be retrieved.
    /// @return The balance of the given user's address in terms of the underlying ERC20 token.
    function balanceOfERC20(
        address token,
        address user
    ) external view returns (uint256);

    /// @notice Mint a new ERC1155 token corresponding to a given ERC20 token.
    /// @param token The address of the ERC20 token being wrapped.
    /// @param amount The amount of ERC20 tokens to wrap into the new ERC1155 token.
    /// @return id The ID of the newly minted ERC1155 token.
    function mint(address token, uint256 amount) external returns (uint256 id);

    /// @notice Burn an ERC1155 token to redeem the underlying ERC20 token.
    /// @param token The address of the underlying ERC20 token to redeem.
    /// @param amount The amount of ERC1155 tokens to burn.
    /// @dev This function redeems the ERC20 tokens and sends them back to the caller.
    function burn(address token, uint256 amount) external;
}
