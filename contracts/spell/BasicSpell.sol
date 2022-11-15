// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

import '../BlueBerryErrors.sol';
import '../utils/ERC1155NaiveReceiver.sol';
import '../interfaces/IBank.sol';
import '../interfaces/IWERC20.sol';
import '../interfaces/IWETH.sol';

abstract contract BasicSpell is ERC1155NaiveReceiver, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IBank public bank;
    IWERC20 public werc20;
    address public weth;

    /// @dev Mapping from token to (mapping from spender to approve status)
    mapping(address => mapping(address => bool)) public approved;

    /// @dev mapping from lp token to whitelist status
    mapping(address => bool) public whitelistedLpTokens;

    modifier onlyWhitelistedLp(address lpToken) {
        if (!whitelistedLpTokens[lpToken]) revert LP_NOT_WHITELISTED(lpToken);
        _;
    }

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

        ensureApprove(_weth, address(_bank));
        IWERC20(_werc20).setApprovalForAll(address(_bank), true);
    }

    /// @dev Ensure that the spell has approved the given spender to spend all of its tokens.
    /// @param token The token to approve.
    /// @param spender The spender to allow spending.
    /// NOTE: This is safe because spell is never built to hold fund custody.
    function ensureApprove(address token, address spender) internal {
        if (!approved[token][spender]) {
            IERC20Upgradeable(token).safeApprove(spender, type(uint256).max);
            approved[token][spender] = true;
        }
    }

    /// @dev Internal call to convert msg.value ETH to WETH inside the contract.
    function doTransmitETH() internal {
        if (msg.value > 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    /// @dev Internal call to transmit tokens from the bank if amount is positive.
    /// @param token The token to perform the transmit action.
    /// @param amount The amount to transmit.
    /// @notice Do not use `amount` input argument to handle the received amount.
    function doTransmit(address token, uint256 amount) internal {
        if (amount > 0) {
            bank.transmit(token, amount);
        }
    }

    /// @dev Internal call to refund tokens to the current bank executor.
    /// @param token The token to perform the refund action.
    function doRefund(address token) internal {
        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20Upgradeable(token).safeTransfer(bank.EXECUTOR(), balance);
        }
    }

    /// @dev Internal call to refund all WETH to the current executor as native ETH.
    function doRefundETH() internal {
        uint256 balance = IWETH(weth).balanceOf(address(this));
        if (balance > 0) {
            IWETH(weth).withdraw(balance);
            (bool success, ) = bank.EXECUTOR().call{value: balance}(
                new bytes(0)
            );
            if (!success) revert REFUND_ETH_FAILED(balance);
        }
    }

    /// @dev Internal call to refund tokens to the current bank executor.
    /// @param token The token to perform the refund action.
    function doCutRewardsFee(address token) internal {
        if (bank.config().treasury() == address(0)) revert NO_TREASURY_SET();

        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
        if (balance > 0) {
            uint256 fee = (balance * bank.config().depositFee()) / 10000;
            IERC20Upgradeable(token).safeTransfer(
                bank.config().treasury(),
                fee
            );

            balance -= fee;
            IERC20Upgradeable(token).safeTransfer(bank.EXECUTOR(), balance);
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
            ensureApprove(token, address(bank));
            bank.repay(token, amount);
        }
    }

    /// @dev Internal call to put collateral tokens in the bank.
    /// @param token The token to put in the bank.
    /// @param amount The amount to put in the bank.
    function doPutCollateral(address token, uint256 amount) internal {
        if (amount > 0) {
            ensureApprove(token, address(werc20));
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
            if (amount == type(uint256).max) {
                (, , , amount, ) = bank.getCurrentPositionInfo();
            }
            bank.takeCollateral(amount);
            werc20.burn(token, amount);
        }
    }

    /// @dev Set whitelist LP token statuses for spell
    /// @param lpTokens LP tokens to set whitelist statuses
    /// @param statuses Whitelist statuses
    function setWhitelistLPTokens(
        address[] calldata lpTokens,
        bool[] calldata statuses
    ) external onlyOwner {
        if (lpTokens.length != statuses.length) revert INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < lpTokens.length; idx++) {
            if (statuses[idx] && !bank.support(lpTokens[idx]))
                revert ORACLE_NOT_SUPPORT_LP(lpTokens[idx]);

            whitelistedLpTokens[lpTokens[idx]] = statuses[idx];
        }
    }

    /// @dev Fallback function. Can only receive ETH from WETH contract.
    receive() external payable {
        if (msg.sender != weth) revert NOT_FROM_WETH(msg.sender);
    }
}
