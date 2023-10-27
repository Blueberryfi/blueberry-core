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

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PoolEscrow.sol";
import "./interfaces/IPoolEscrow.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {LibClone} from "./utils/LibClone.sol";

contract PoolEscrowFactory is Initializable, Ownable {
    using SafeERC20 for IERC20;

    event EscrowCreated(address);

    /// @dev The caller is not authorized to call the function.
    error Unauthorized();

    /// @dev Address of the escrow implementation.
    address public implementation;

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Unauthorized();
        }
        _;
    }

    /// @param _escrow The escrow contract implementation
    constructor(address _escrow) payable Ownable() {
        implementation = _escrow;
    }

    /// @dev used once wrapper contract has been deployed to avoid circular dependency
    /// @param _wrapper The address of the pool wrapper contract.
    function initialize(address _wrapper) public payable initializer onlyOwner {
        wrapper = _wrapper;
    }

    /// @notice Creates an escrow contract for a given PID
    /// @param _pid The pool id (The first 16-bits)
    function createEscrow(
        uint256 _pid
    ) external payable onlyWrapper returns (address _escrow) {
        _escrow = LibClone.clone(implementation);
        IPoolEscrow(_escrow).initialize(_pid, wrapper);
        emit EscrowCreated(_escrow);
    }
}
