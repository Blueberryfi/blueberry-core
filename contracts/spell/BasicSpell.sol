// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../utils/BlueBerryConst.sol" as Constants;
import "../utils/BlueBerryErrors.sol" as Errors;
import "../utils/ERC1155NaiveReceiver.sol";
import "../interfaces/IBank.sol";
import "../interfaces/IWERC20.sol";
import "../interfaces/IWETH.sol";

abstract contract BasicSpell is ERC1155NaiveReceiver, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IBank public bank;
    IWERC20 public werc20;
    address public weth;

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __BasicSpell_init(
        IBank _bank,
        address _werc20,
        address _weth
    ) internal onlyInitializing {
        __Ownable_init();

        bank = _bank;
        werc20 = IWERC20(_werc20);
        weth = _weth;

        IWERC20(_werc20).setApprovalForAll(address(_bank), true);
    }

    /// @dev Internal call to refund tokens to the current bank executor.
    /// @param token The token to perform the refund action.
    function doRefund(address token) internal {
        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20Upgradeable(token).safeTransfer(bank.EXECUTOR(), balance);
        }
    }

    /// @dev Internal call to refund tokens to the current bank executor.
    /// @param token The token to perform the refund action.
    function doRefundRewards(address token) internal {
        uint256 rewardsBalance = IERC20Upgradeable(token).balanceOf(
            address(this)
        );
        if (rewardsBalance > 0) {
            IERC20Upgradeable(token).safeApprove(
                address(bank.feeManager()),
                rewardsBalance
            );
            rewardsBalance -= bank.feeManager().doCutRewardsFee(
                token,
                rewardsBalance
            );
            doRefund(token);
        }
    }

    function doLend(address token, uint256 amount) internal {
        if (amount > 0) {
            bank.lend(token, amount);
        }
    }

    function doWithdraw(address token, uint256 amount) internal {
        if (amount > 0) {
            bank.withdrawLend(token, amount);
        }
    }

    /**
     * @dev Internal call to borrow tokens from the bank on behalf of the current executor.
     * @param token The token to borrow from the bank.
     * @param amount The amount to borrow.
     * @notice Do not use `amount` input argument to handle the received amount.
     */
    function doBorrow(address token, uint256 amount) internal {
        if (amount > 0) {
            bank.borrow(token, amount);
        }
    }

    /// @dev Internal call to repay tokens to the bank on behalf of the current executor.
    /// @param token The token to repay to the bank.
    /// @param amount The amount to repay.
    function doRepay(address token, uint256 amount) internal {
        if (amount > 0) {
            IERC20Upgradeable(token).safeApprove(address(bank), amount);
            bank.repay(token, amount);
        }
    }

    /// @dev Internal call to put collateral tokens in the bank.
    /// @param token The token to put in the bank.
    /// @param amount The amount to put in the bank.
    function doPutCollateral(address token, uint256 amount) internal {
        if (amount > 0) {
            IERC20Upgradeable(token).safeApprove(address(werc20), amount);
            werc20.mint(token, amount);
            bank.putCollateral(
                address(werc20),
                uint256(uint160(token)),
                amount
            );
        }
    }

    /// @dev Internal call to take collateral tokens from the bank.
    /// @param token The token to take back.
    /// @param amount The amount to take back.
    function doTakeCollateral(address token, uint256 amount) internal {
        if (amount > 0) {
            amount = bank.takeCollateral(amount);
            werc20.burn(token, amount);
        }
    }

    /// @dev Fallback function. Can only receive ETH from WETH contract.
    receive() external payable {
        if (msg.sender != weth) revert Errors.NOT_FROM_WETH(msg.sender);
    }
}
