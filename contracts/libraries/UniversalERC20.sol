// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library UniversalERC20 {
    using SafeERC20 for IERC20;

    address private constant ZERO_ADDRESS = address(0);
    address private constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function universalTransfer(IERC20 token, address to, uint256 amount) internal returns (bool) {
        if (amount == 0) {
            return true;
        }
        if (isETH(token)) {
            (bool success,) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
            return true;
        } else {
            token.safeTransfer(to, amount);
            return true;
        }
    }

    function universalTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (isETH(token)) {
            require(from == msg.sender && msg.value == amount, "Wrong useage of ETH.universalTransferFrom()");
            if (to != address(this)) {
                (bool success,) = to.call{value: amount}("");
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

    function universalBalanceOf(IERC20 token, address who) internal view returns (uint256) {
        if (isETH(token)) {
            return who.balance;
        } else {
            return token.balanceOf(who);
        }
    }

    function isETH(IERC20 token) internal pure returns (bool) {
        return (address(token) == address(ZERO_ADDRESS) || address(token) == address(ETH_ADDRESS));
    }
}
