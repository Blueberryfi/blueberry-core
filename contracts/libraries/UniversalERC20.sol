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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title UniversalERC20
 * @dev UniversalERC20 is a helper contract that allows to work around ERC20
 *      limitations when dealing with missing return values.
 *      UniversalERC20 executes a low level call to the token contract.
 *      If it fails, it assumes that the token does not implement the method.
 *      If it succeeds, it returns the value returned by the method.
 *      Also supports if the token address is native ETH.
 */
library UniversalERC20 {
    using SafeERC20 for IERC20;

    address private constant _ZERO_ADDRESS = address(0);
    address private constant _ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @notice UniversalERC20's safeTransfer function that is similar to ERC20's transfer function.
    /// @dev Works around non-standard ERC20's that throw on 0 transfer and supports Native ETH.
    function universalTransfer(IERC20 token, address to, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return true;
        }
        if (isETH(token)) {
            (bool success, ) = to.call{ value: amount }("");
            require(success, "ETH transfer failed");
            return true;
        } else {
            token.safeTransfer(to, amount);
            return true;
        }
    }

    /// @notice UniversalERC20's safeTransferFrom function that is similar to ERC20's transferFrom function.
    /// @dev Works around non-standard ERC20's that throw on 0 transfer and supports native ETH.
    function universalTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (isETH(token)) {
            require(from == msg.sender && msg.value == amount, "Wrong useage of ETH.universalTransferFrom()");
            if (to != address(this)) {
                (bool success, ) = to.call{ value: amount }("");
                require(success, "ETH transfer failed");
            }
        } else {
            token.safeTransferFrom(from, to, amount);
        }
    }

    function universalApprove(IERC20 token, address to, uint256 amount) internal {
        if (!isETH(token)) {
            token.forceApprove(to, amount);
        }
    }

    /// @notice UniversalBalanceOf returns the balance of a token for an address.
    /// @dev Is able to tell the balance of a token or natie ETH.
    function universalBalanceOf(IERC20 token, address who) internal view returns (uint256) {
        if (isETH(token)) {
            return who.balance;
        } else {
            return token.balanceOf(who);
        }
    }

    /// @notice returns if the token is ETH or not.
    function isETH(IERC20 token) internal pure returns (bool) {
        return (address(token) == address(_ZERO_ADDRESS) || address(token) == address(_ETH_ADDRESS));
    }
}
