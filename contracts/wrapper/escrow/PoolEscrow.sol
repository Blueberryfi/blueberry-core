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
import { UniversalERC20, IERC20 } from "../../libraries/UniversalERC20.sol";

import "../../utils/BlueberryErrors.sol" as Errors;

import { ICvxBooster } from "../../interfaces/convex/ICvxBooster.sol";
import { IRewarder } from "../../interfaces/convex/IRewarder.sol";
import { IPoolEscrow } from "./interfaces/IPoolEscrow.sol";

contract PoolEscrow is IPoolEscrow {
    using SafeERC20 for IERC20;
    using UniversalERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

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
    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Errors.UNAUTHORIZED();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(uint256 _pid, address _wrapper, address _booster, address _rewarder, address _lpToken) {
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

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
    /// @inheritdoc IPoolEscrow
    function transferTokenFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external virtual onlyWrapper {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    /// @inheritdoc IPoolEscrow
    function transferToken(address _token, address _to, uint256 _amount) external virtual onlyWrapper {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @inheritdoc IPoolEscrow
    function deposit(uint256 _amount) external virtual onlyWrapper {
        IERC20(address(lpToken)).universalApprove(address(booster), _amount);
        booster.deposit(pid, _amount, true);
    }

    /// @inheritdoc IPoolEscrow
    function withdrawLpToken(uint256 amount, address user) external virtual onlyWrapper {
        rewarder.withdrawAndUnwrap(amount, false);
        IERC20(lpToken).safeTransfer(user, amount);
    }
}
