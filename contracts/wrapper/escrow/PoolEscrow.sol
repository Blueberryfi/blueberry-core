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
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract PoolEscrow is Initializable {
    using SafeERC20 for IERC20;

    /// @dev The caller is not authorized to call the function.
    error Unauthorized();

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev PID of this escrow contract.
    uint256 public pid;

    /// @dev The balance for a given token for a given user
    /// e.g userBalance[msg.sender][0x23523...]
    mapping(address => mapping(address => uint256)) public userBalance;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Initializes the pool escrow with the given PID.
    /// @param _pid The pool id (The first 16-bits)
    /// @param _wrapper The wrapper contract address
    function initialize(
        uint256 _pid,
        address _wrapper
    ) public payable initializer {
        pid = _pid;
        wrapper = _wrapper;
    }

    /**
     * @notice Transfers tokens to a specified address
     * @param _token The address of the token to be transferred
     * @param _from The address from which the tokens will be transferred
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferTokenFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external virtual onlyWrapper {
        if (_amount > 0) {
            IERC20(_token).safeTransferFrom(_from, _to, _amount);
        }
    }

    /**
     * @notice Deposits tokens for a given user
     * @param _token The address of the token to be deposited
     * @param _for The address for which the tokens will be deposited
     * @param _amount The amount of tokens to be deposited
     */
    function deposit(
        address _token,
        address _for,
        uint256 _amount
    ) external virtual onlyWrapper {
        userBalance[_for][_token] += _amount;
        IERC20(_token).safeTransferFrom(_for, address(this), _amount);
    }

    /**
     * @notice Withdraws tokens for a given user
     * @param _token The address of the token to be withdrawn
     * @param _to The address to which the tokens will be withdrawn
     * @param _amount The amount of tokens to be withdrawn
     */
    function withdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external virtual onlyWrapper {
        userBalance[_to][_token] -= _amount;
        IERC20(_token).safeTransferFrom(address(this), _to, _amount);
    }
}
