// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../interfaces/paraswap/IParaswap.sol";

library PSwapLib {
    function _approve(
        IERC20 inToken,
        address spender,
        uint256 amount
    ) internal {
        // approve zero before set allocation
        inToken.approve(spender, 0);
        inToken.approve(spender, amount);
    }

    function simpleSwap(
        IERC20 inToken,
        uint256 amountIn,
        address augustusSwapper,
        address tokenTransferProxy,
        Utils.SimpleData calldata data
    ) external returns (uint256 receivedAmount) {
        _approve(inToken, tokenTransferProxy, amountIn);

        return IParaswap(augustusSwapper).simpleSwap(data);
    }

    function megaSwap(
        IERC20 inToken,
        uint256 amountIn,
        address augustusSwapper,
        address tokenTransferProxy,
        Utils.MegaSwapSellData calldata data
    ) external returns (uint256) {
        _approve(inToken, tokenTransferProxy, amountIn);

        return IParaswap(augustusSwapper).megaSwap(data);
    }
}
