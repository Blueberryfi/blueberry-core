// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockParaswapTransferProxy {
    using SafeERC20 for IERC20;

    function safeTransferFrom(address from, address to, address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}
