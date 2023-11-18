// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

/// @title IBaseOracle
/// @notice Interface for a basic oracle that provides price data for assets.
interface IBaseOracle {
    /// @notice Returns the USD value of a given ERC-20 token, normalized to 1e18 decimals.
    /// @dev The value returned is multiplied by 10**18 to maintain precision.
    /// @param token Address of the ERC-20 token for which the price is requested.
    /// @return The USD price of the given token, multiplied by 10**18.
    function getPrice(address token) external returns (uint256);
}
