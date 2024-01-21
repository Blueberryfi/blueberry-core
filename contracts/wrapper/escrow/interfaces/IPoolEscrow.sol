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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICvxBooster } from "../../../interfaces/convex/ICvxBooster.sol";
import { IRewarder } from "../../../interfaces/convex/IRewarder.sol";

interface IPoolEscrow {
    /**
     * @notice Transfers tokens to and from a specified address
     * @param token The address of the token to be transferred
     * @param from The address from which the tokens will be transferred
     * @param to The address to which the tokens will be transferred
     * @param amount The amount of tokens to be transferred
     */
    function transferTokenFrom(address token, address from, address to, uint256 amount) external;

    /**
     * @notice Transfers tokens to a specified address
     * @param token The address of the token to be transferred
     * @param to The address to which the tokens will be transferred
     * @param amount The amount of tokens to be transferred
     */
    function transferToken(address token, address to, uint256 amount) external;

    /**
     * @notice Deposits tokens to pool
     * @param amount The amount of tokens to be deposited
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Closes the Aura/Convex position and withdraws the underlying
     *     LP token from the booster.
     * @param amount Amount of LP tokens to withdraw
     * @param user Address of the recipient of LP tokens
     */
    function withdrawLpToken(uint256 amount, address user) external;

    /// @notice Returns the address of the wrapper contract associated with the escrow.
    function getWrapper() external view returns (address);

    /// @notice Returns the PID of the Curve Gauge or Aura Pool associated with the escrow.
    function getPid() external view returns (uint256);

    /// @notice Returns the address of the Booster associated with the escrow.
    function getBooster() external view returns (ICvxBooster);

    /// @notice Returns the address of the Rewarder associated with the escrow.
    function getRewarder() external view returns (IRewarder);

    /// @notice Returns the address of the LP token associated with the escrow.
    function getLpToken() external view returns (IERC20);
}
