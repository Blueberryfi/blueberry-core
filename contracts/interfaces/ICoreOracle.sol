// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBaseOracle } from "./IBaseOracle.sol";

/**
 *  @title ICoreOracle
 *  @notice Interface for the CoreOracle contract which provides price feed data for assets in the Blueberry protocol.
 */
interface ICoreOracle is IBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Event emitted when the owner sets a new oracle route for a given token.
     * @param token The ERC20 token for which the oracle route is set.
     * @param route The address of the oracle route.
     */
    event SetRoute(address indexed token, address route);

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if the given ERC20 token is supported by the oracle.
     * @param token The ERC20 token to check support for.
     * @return A boolean indicating whether the token is supported or not.
     */
    function isTokenSupported(address token) external view returns (bool);

    /**
     * @notice Check if the oracle supports the underlying token of a given ERC1155 wrapper.
     * @dev Only meant to validate wrappers of the Blueberry protocol, such as WERC20.
     * @param token ERC1155 token address to check support for.
     * @param tokenId ERC1155 token id to check support for.
     * @return A boolean indicating whether the wrapped token is supported or not.
     */
    function isWrappedTokenSupported(address token, uint256 tokenId) external view returns (bool);

    /**
     * @notice Returns the USD value of a specific wrapped ERC1155 token.
     * @param token ERC1155 token address.
     * @param id ERC1155 token id.
     * @param amount Amount of the token for which to get the USD value, normalized to 1e18 decimals.
     * @return The USD value of the given wrapped token amount.
     */
    function getWrappedTokenValue(address token, uint256 id, uint256 amount) external view returns (uint256);

    /**
     * @notice Returns the USD value of a given amount of a specific ERC20 token.
     * @param token ERC20 token address.
     * @param amount Amount of the ERC20 token for which to get the USD value.
     * @return The USD value of the given token amount.
     */
    function getTokenValue(address token, uint256 amount) external view returns (uint256);

    /**
     * @notice Fetches the oracle route for the given token.
     * @param token Address of the token to get the route for.
     * @return The address of the oracle route for the given token.
     */
    function getRoute(address token) external view returns (address);
}
