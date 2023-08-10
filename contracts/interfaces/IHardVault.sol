// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "./IERC20Wrapper.sol";

/// @title IHardVault
/// @notice Interface for the HardVault, which integrates ERC1155 tokens with the protocol's underlying assets.
/// @dev This interface facilitates the conversion between underlying ERC-20
///      tokens and corresponding ERC-1155 representations within the protocol.
interface IHardVault is IERC1155Upgradeable {
    /// @notice Retrieves the underlying ERC-20 token address corresponding to a specific ERC-1155 token ID.
    /// @param tokenId The ERC-1155 token ID to fetch the underlying ERC-20 token for.
    /// @return Address of the underlying ERC-20 token associated with the provided token ID.
    function getUnderlyingToken(
        uint256 tokenId
    ) external view returns (address);

    /// @notice Returns the balance of the underlying ERC-20 token for a specific user.
    /// @param uToken Address of the ERC-20 token to query.
    /// @param user Address of the user to query the balance for.
    /// @return Balance of the underlying ERC-20 token for the given user.
    function balanceOfERC20(
        address uToken,
        address user
    ) external view returns (uint256);

    /// @notice Deposit a certain amount of ERC-20 tokens to receive an equivalent amount of ERC-1155 representations.
    /// @param uToken The address of the ERC-20 token to be deposited.
    /// @param amount The quantity of ERC-20 tokens to be deposited.
    /// @return shareAmount The amount of ERC-1155 tokens minted in exchange for the deposited ERC-20 tokens.
    function deposit(
        address uToken,
        uint256 amount
    ) external returns (uint256 shareAmount);

    /// @notice Withdraw a certain amount of ERC-1155 tokens to 
    ///         receive an equivalent amount of underlying ERC-20 tokens.
    /// @param uToken The address of the underlying ERC-20 token to be withdrawn.
    /// @param shareAmount The quantity of ERC-1155 tokens to be withdrawn.
    /// @return withdrawAmount The amount of ERC-20 tokens returned in exchange for the withdrawn ERC-1155 tokens.
    function withdraw(
        address uToken,
        uint256 shareAmount
    ) external returns (uint256 withdrawAmount);
}
