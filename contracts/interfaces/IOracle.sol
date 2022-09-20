// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IOracle {
    /// @dev Return whether the ERC-20 token is supported
    /// @param token The ERC-20 token to check for support
    function support(address token) external view returns (bool);

    /// @dev Return whether the oracle supports evaluating collateral value of the given address.
    /// @param token The ERC-1155 token to check the acceptence.
    /// @param id The token id to check the acceptance.
    function supportWrappedToken(address token, uint256 id)
        external
        view
        returns (bool);

    /// @dev Return the value of the given input for collateral purpose.
    /// @param token The ERC-1155 token to check the value.
    /// @param id The id of the token to check the value.
    /// @param amount The amount of tokens to check the value
    function getCollateralValue(
        address token,
        uint256 id,
        uint256 amount
    ) external view returns (uint256);

    /// @dev Return the value of the given input for borrow purpose.
    /// @param token The ERC-20 token to check the value.
    /// @param amount The amount of tokens to check the value.
    function getDebtValue(address token, uint256 amount)
        external
        view
        returns (uint256);
}
