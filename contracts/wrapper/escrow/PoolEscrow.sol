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

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UniversalERC20, IERC20 } from "../../libraries/UniversalERC20.sol";

import "../../utils/BlueberryErrors.sol" as Errors;

import { ICvxBooster } from "../../interfaces/convex/ICvxBooster.sol";
import { IRewarder } from "../../interfaces/convex/IRewarder.sol";

contract PoolEscrow is Initializable {
    using SafeERC20 for IERC20;
    using UniversalERC20 for IERC20;

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev PID of this escrow contract.
    uint256 public pid;

    /// @dev address of the aura pools contract.
    ICvxBooster public booster;

    /// @dev address of the rewarder contract.
    IRewarder public rewarder;

    /// @dev address of the lptoken for this escrow.
    IERC20 public lpToken;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Errors.UNAUTHORIZED();
        }
        _;
    }

    /// @dev Initializes the pool escrow with the given parameters
    /// @param _pid The pool id (The first 16-bits)
    /// @param _wrapper The wrapper contract address
    function initialize(
        uint256 _pid,
        address _wrapper,
        address _booster,
        address _rewarder,
        address _lpToken
    ) public payable initializer {
        if (_wrapper == address(0) || _booster == address(0) || _rewarder == address(0) || _lpToken == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        pid = _pid;
        wrapper = _wrapper;
        booster = ICvxBooster(_booster);
        rewarder = IRewarder(_rewarder);
        lpToken = IERC20(_lpToken);

        UniversalERC20.universalApprove(lpToken, wrapper, type(uint256).max);
    }

    /**
     * @notice Transfers tokens to and from a specified address
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
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    /**
     * @notice Transfers tokens to a specified address
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferToken(address _token, address _to, uint256 _amount) external virtual onlyWrapper {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /**
     * @notice Deposits tokens to pool
     * @param _amount The amount of tokens to be deposited
     */
    function deposit(uint256 _amount) external virtual onlyWrapper {
        IERC20(address(lpToken)).universalApprove(address(booster), _amount);
        booster.deposit(pid, _amount, true);
    }

    /**
     * @notice Closes the position from the booster contract
     *         adn transfers the LP token to the user
     * @param amount Amount of LP tokens to withdraw
     * @param user Address of the user that will receive the LP tokens
     */
    function withdrawLpToken(uint256 amount, address user) external virtual onlyWrapper {
        rewarder.withdrawAndUnwrap(amount, false);
        IERC20(lpToken).safeTransfer(user, amount);
    }
}
