// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/Ini.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPoolEscrow {
    using SafeERC20 for IERC20;

    struct Pool {
        uint256 PID;
        /// ...
    }

    /// @dev Initializes the pool escrow with the given PID.
    function initialize(address pid) public payable {}

    /// @notice Creates an escrow contract for a given PID
    /// @param pid The pool id (The first 16-bits)
    function createEscrow(
        uint256 pid
    ) external payable returns (address _escrow) {}
}
