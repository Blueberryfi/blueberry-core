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

    /// @dev Address cannot be zero.
    error AddressZero();

    /// @dev Address of the escrow implementation.
    address public implementation;

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev Address of the aura pools contract.
    address public auraPools;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Unauthorized();
        }
        _;
    }

    /// @param _escrowBase The escrow contract implementation
    constructor(address _escrowBase) payable Ownable() {
        if (_escrowBase == address(0)) {
            revert AddressZero();
        }
        implementation = _escrowBase;
    }

    /// @dev used once wrapper contract has been deployed to avoid circular dependency
    /// @param _wrapper The address of the pool wrapper contract.
    function initialize(
        address _wrapper,
        address _auraPools
    ) public payable initializer onlyOwner {
        if (_wrapper == address(0) || _auraPools == address(0)) {
            revert AddressZero();
        }
        wrapper = _wrapper;
        auraPools = _auraPools;
    }

    /// @notice Creates an escrow contract for a given PID
    /// @param _pid The pool id (The first 16-bits)
    function createEscrow(
        uint256 _pid,
        address _rewards,
        address _lpToken
    ) external payable onlyWrapper returns (address _escrow) {
        _escrow = LibClone.clone(implementation);
        IPoolEscrow(_escrow).initialize(
            _pid,
            wrapper,
            auraPools,
            _rewards,
            _lpToken
        );
        emit EscrowCreated(_escrow);
    }
}
