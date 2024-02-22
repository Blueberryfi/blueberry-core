// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/paraswap/IParaswap.sol";
import "../../libraries/UniversalERC20.sol";
import "./Utils.sol";

library PSwapLib {
    function _approve(
        IERC20 inToken,
        address spender,
        uint256 amount
    ) internal {
        // approve zero before reset allocation
        UniversalERC20.universalApprove(inToken, spender, 0);
        UniversalERC20.universalApprove(inToken, spender, amount);
    }

    function swap(
        address augustusSwapper,
        address tokenTransferProxy,
        address fromToken,
        uint256 fromAmount,
        bytes calldata data
    ) internal returns (bool success) {
        _approve(IERC20(fromToken), tokenTransferProxy, fromAmount);

        bytes memory returndata;

        (success, returndata) = augustusSwapper.call(data);

        UniversalERC20.universalApprove(IERC20(fromToken), tokenTransferProxy, 0);
    }

    function megaSwap(
        address augustusSwapper,
        address tokenTransferProxy,
        Utils.MegaSwapSellData calldata data
    ) internal returns (uint256) {
        _approve(IERC20(data.fromToken), tokenTransferProxy, data.fromAmount);

        uint256 result = IParaswap(augustusSwapper).megaSwap(data);

        UniversalERC20.universalApprove(IERC20(data.fromToken), tokenTransferProxy, 0);

        return result;
    }
}
