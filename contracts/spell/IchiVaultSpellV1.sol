// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './WhitelistSpell.sol';
import '../utils/BBMath.sol';
import '../interfaces/ichi/IICHIVault.sol';
import '../interfaces/UniV3/IUniswapV3Pool.sol';

contract IchiVaultSpellV1 is WhitelistSpell {
    using BBMath for uint256;

    mapping(address => address) vaults;

    constructor(
        IBank _bank,
        address _werc20,
        address _weth
    ) WhitelistSpell(_bank, _werc20, _weth) {}

    function _isTokenA(address token) internal returns (bool) {
        IICHIVault vault = IICHIVault(vaults[token]);
        return vault.token0() == token;
    }

    function deposit(
        address token,
        uint256 amount,
        uint256 amtBorrow
    ) external {
        // 1. Get user input amounts
        doTransmit(token, amount);

        // 2. Borrow specific amounts
        doBorrow(token, amtBorrow);

        // 3. Add liquidity - Deposit on ICHI Vault
        IICHIVault vault = IICHIVault(vaults[token]);
        bool isTokenA = _isTokenA(token);
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (isTokenA) {
            vault.deposit(balance, 0, address(this));
        } else {
            vault.deposit(0, balance, address(this));
        }

        // 4. Put collateral
        doPutCollateral(
            address(vault),
            IERC20(address(vault)).balanceOf(address(this))
        );
    }

    function withdrawInternal(
        address token,
        address lp,
        uint256 amountRepay,
        uint256 amountLpRepay,
        uint256 amountLpWithdraw
    ) internal {
        require(whitelistedLpTokens[lp], 'lp token not whitelisted');
        uint256 positionId = bank.POSITION_ID();

        // 2. Compute repay amount if MAX_INT is supplied (max debt)
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.borrowBalanceCurrent(positionId, token);
        }
        if (amountLpRepay == type(uint256).max) {
            amountLpRepay = bank.borrowBalanceCurrent(positionId, lp);
        }

        // 3. Calculate actual amount to remove
        uint256 amtLPToRemove = IERC20(lp).balanceOf(address(this)) -
            amountLpWithdraw;

        // 4. Remove liquidity
        IICHIVault(lp).withdraw(amtLPToRemove, address(this));

        // 5. Swap tokens to deposited token
        IUniswapV3Pool(IICHIVault(lp).pool()).swap(
            address(this),
            swapQuantity > 0,
            swapQuantity > 0 ? swapQuantity : -swapQuantity,
            swapQuantity > 0
                ? UV3Math.MIN_SQRT_RATIO + 1
                : UV3Math.MAX_SQRT_RATIO - 1,
            abi.encode(address(this))
        );
    }

    function withdraw(
        address token,
        uint256 lpTakeAmt,
        uint256 amountRepay
    ) external {
        address vault = vaults[token];

        // 1. Take out collateral
        doTakeCollateral(vault, lpTakeAmt);

        // 2. Remove Liquidity - Withdraw from ICHI Vault
        withdrawInternal(vault);
    }
}
