// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/**
 * @title IBaseOracle
 * @author BlueberryProtocol
 * @notice Interface for a basic oracle that provides price data for assets.
 */
interface IBaseOracle {
    /**
     * @notice Event emitted when a new LP token is registered within its respective implementation.
     * @param token Address of the LP token being registered
     */
    event RegisterLpToken(address token);

    /**
     * @notice Fetches the price of the given token in USD with 18 decimals precision.
     * @param token Address of the ERC-20 token for which the price is requested.
     * @return The USD price of the given token, multiplied by 10**18.
     */
    function getPrice(address token) external view returns (uint256);
}
