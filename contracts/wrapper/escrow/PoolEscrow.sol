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

/**
 * @title PoolEscrow
 * @author BlueberryProtocol
 * @notice This contracts acts as an escrow for rewards for wrapper contracts associated with
 *        Convex and Aura Spells.
 * @dev There will be a new PoolEscrow contract for each wrapper contract.
 */
contract PoolEscrow is IPoolEscrow {
    using SafeERC20 for IERC20;
    using UniversalERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the wrapper contract.
    address private _wrapper;

    /// @dev PID of this escrow contract.
    uint256 private _pid;

    /// @dev address of the booster contract.
    ICvxBooster private _booster;

    /// @dev address of the rewarder contract.
    IRewarder private _rewarder;

    /// @dev address of the lptoken for this escrow.
    IERC20 private _lpToken;
    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != _wrapper) {
            revert Errors.UNAUTHORIZED();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(uint256 pid, address wrapper, address booster, address rewarder, address lpToken) {
        if (wrapper == address(0) || booster == address(0) || rewarder == address(0) || lpToken == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _pid = pid;
        _wrapper = wrapper;
        _booster = ICvxBooster(booster);
        _rewarder = IRewarder(rewarder);
        _lpToken = IERC20(lpToken);

        UniversalERC20.universalApprove(IERC20(lpToken), wrapper, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
    /// @inheritdoc IPoolEscrow
    function transferTokenFrom(address token, address from, address to, uint256 amount) external virtual onlyWrapper {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    /// @inheritdoc IPoolEscrow
    function transferToken(address token, address to, uint256 amount) external virtual onlyWrapper {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @inheritdoc IPoolEscrow
    function deposit(uint256 amount) external virtual onlyWrapper {
        IERC20(address(_lpToken)).universalApprove(address(_booster), amount);
        _booster.deposit(_pid, amount, true);
    }

    /// @inheritdoc IPoolEscrow
    function withdrawLpToken(uint256 amount, address user) external virtual onlyWrapper {
        _rewarder.withdrawAndUnwrap(amount, false);
        IERC20(_lpToken).safeTransfer(user, amount);
    }

    function getWrapper() external view override returns (address) {
        return _wrapper;
    }

    function getPid() external view override returns (uint256) {
        return _pid;
    }

    function getBooster() external view override returns (ICvxBooster) {
        return _booster;
    }

    function getRewarder() external view override returns (IRewarder) {
        return _rewarder;
    }

    function getLpToken() external view override returns (IERC20) {
        return _lpToken;
    }
}
