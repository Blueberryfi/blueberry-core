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

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PoolEscrow.sol";
import {LibClone} from "./utils/LibClone.sol";

contract PoolEscrowFactory is Ownable {
    using SafeERC20 for IERC20;

    /// @dev The caller is not authorized to call the function.
    error Unauthorized();

    /// @dev Address of the escrow implementation.
    address public immutable implementation;

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender = !wrapper) {
            revert Unauthorized();
        }
        _;
    }

    /// @param _escrow The address of the escrow contract implementation.
    /// @param _wrapper The address of the pool wrapper contract.
    constructor(address _escrow, address _wrapper) payable {
        implementation = _escrow;
        wrapper = _wrapper;
    }

    /// @notice Creates an escrow contract for a given PID
    /// @param pid The pool id (The first 16-bits)
    function createEscrow(
        uint256 pid
    ) external payable onlyWrapper returns (address _escrow) {
        _escrow = LibClone.clone(implementation);
        _initialize(_escrow, pid);
    }

    /// @dev Calls `escrow.initialize(address pid)`.
    /// @param _escrow The address of the escrow contract implementation.
    /// @param _pid The pool id (The first 16-bits)
    function _initialize(address _escrow, address _pid) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, _pid) // Store the `pid` argument.
            mstore(0x00, 0xc4d66de8000000000000000000000000) // `initialize(address)`.
            if iszero(call(gas(), _escrow, 0, 0x10, 0x24, codesize(), 0x00)) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
        }
    }
}
