// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../libraries/UniV3/TickMath.sol';
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

    function _isTokenA(address token) internal view returns (bool) {
        IICHIVault vault = IICHIVault(vaults[token]);
        return vault.token0() == token;
    }

    /**
     * @notice External function to deposit assets on IchiVault
     * @param token Token address to deposit (e.g USDC)
     * @param amount Amount of user's collateral (e.g USDC)
     * @param amtBorrow Amount to borrow on Compound
     */
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

    /**
     * @notice External function to withdraw assets from ICHI Vault
     * @param token Token address to withdraw (e.g USDC)
     * @param lpTakeAmt Amount of ICHI Vault LP token to take out from Bank
     * @param amountRepay Amount to repay the loan
     * @param amountLpWithdraw Amount of ICHI Vault LP to withdraw from ICHI Vault
     */
    function withdraw(
        address token,
        uint256 lpTakeAmt,
        uint256 amountRepay,
        uint256 amountLpWithdraw
    ) external {
        IICHIVault vault = IICHIVault(vaults[token]);

        // 1. Take out collateral
        doTakeCollateral(address(vault), lpTakeAmt);

        // 2. Remove Liquidity - Withdraw from ICHI Vault
        require(
            whitelistedLpTokens[address(vault)],
            'lp token not whitelisted'
        );
        uint256 positionId = bank.POSITION_ID();

        // 2. Compute repay amount if MAX_INT is supplied (max debt)
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.borrowBalanceCurrent(positionId, token);
        }

        // 3. Calculate actual amount to remove
        uint256 amtLPToRemove = vault.balanceOf(address(this)) -
            amountLpWithdraw;

        // 4. Remove liquidity
        vault.withdraw(amtLPToRemove, address(this));

        // 5. Swap tokens to deposited token
        bool isTokenA = vault.token0() == token;
        uint256 amountToSwap = IERC20(
            isTokenA ? vault.token1() : vault.token0()
        ).balanceOf(address(this));

        IUniswapV3Pool(vault.pool()).swap(
            address(this),
            // if withdraw token is Token0, then token1 -> token0 (false)
            !isTokenA,
            int256(amountToSwap),
            isTokenA
                ? TickMath.MAX_SQRT_RATIO - 1 // Token0 -> Token1
                : TickMath.MIN_SQRT_RATIO + 1, // Token1 -> Token0
            abi.encode(address(this))
        );

        // 6. Repay
        doRepay(token, amountRepay);

        // 7. Refund
        doRefund(token);
    }
}
