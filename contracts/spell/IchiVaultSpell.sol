// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './WhitelistSpell.sol';
import '../libraries/UniV3/TickMath.sol';
import '../utils/BBMath.sol';
import '../interfaces/IWIchiFarm.sol';
import '../interfaces/ichi/IICHIVault.sol';
import '../interfaces/uniswap/v3/IUniswapV3Pool.sol';
import '../interfaces/uniswap/v3/IUniswapV3SwapCallback.sol';

contract IchiVaultSpell is WhitelistSpell, IUniswapV3SwapCallback {
    using BBMath for uint256;
    using SafeERC20 for IERC20;

    /// @dev temperory state used to store uni v3 pool when swapping on uni v3
    IUniswapV3Pool swapPool;
    mapping(address => address) vaults;

    IWIchiFarm public immutable wIchiFarm;
    address public immutable ICHI;

    constructor(
        IBank _bank,
        address _werc20,
        address _weth,
        address _wichiFarm
    ) WhitelistSpell(_bank, _werc20, _weth) {
        wIchiFarm = IWIchiFarm(_wichiFarm);
        ICHI = address(wIchiFarm.ICHI());
        IWIchiFarm(_wichiFarm).setApprovalForAll(address(_bank), true);
    }

    function addVault(address token, address vault) external onlyOwner {
        vaults[token] = vault;
    }

    function _isTokenA(address token) internal view returns (bool) {
        IICHIVault vault = IICHIVault(vaults[token]);
        return vault.token0() == token;
    }

    function depositInternal(
        address token,
        uint256 amount,
        uint256 amtBorrow
    ) internal {
        // 1. Get user input amounts
        doLend(token, amount);
        // doTransmit(token, amount);

        // 2. Borrow specific amounts
        doBorrow(token, amtBorrow);

        // 3. Add liquidity - Deposit on ICHI Vault
        IICHIVault vault = IICHIVault(vaults[token]);
        bool isTokenA = vault.token0() == token;
        uint256 balance = IERC20(token).balanceOf(address(this));
        ensureApprove(token, address(vault));
        if (isTokenA) {
            vault.deposit(balance, 0, address(this));
        } else {
            vault.deposit(0, balance, address(this));
        }
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
        address vault = vaults[token];
        // 1-3 Deposit on ichi vault
        depositInternal(token, amount, amtBorrow);

        // 4. Put collateral - ICHI Vault Lp Token
        doPutCollateral(vault, IERC20(vault).balanceOf(address(this)));
    }

    function depositFarm(
        address token,
        uint256 amount,
        uint256 amtBorrow,
        uint256 pid
    ) external {
        address vaultAddr = vaults[token];
        address lpToken = wIchiFarm.ichiFarm().lpToken(pid);
        require(vaultAddr == lpToken, 'incorrect lp token');

        // 1-3 Deposit on ichi vault
        depositInternal(token, amount, amtBorrow);

        // 4. Take out collateral
        (, address collToken, uint256 collId, uint256 collSize, ) = bank
            .getCurrentPositionInfo();
        if (collSize > 0) {
            (uint256 decodedPid, ) = wIchiFarm.decodeId(collId);
            require(pid == decodedPid, 'incorrect pid');
            require(
                collToken == address(wIchiFarm),
                'collateral token & wmasterchef mismatched'
            );
            bank.takeCollateral(address(wIchiFarm), collId, collSize);
            wIchiFarm.burn(collId, collSize);
        }

        // 5. Deposit on farming pool, put collateral
        ensureApprove(vaultAddr, address(wIchiFarm));
        uint256 lpAmount = IERC20(vaultAddr).balanceOf(address(this));
        uint256 id = wIchiFarm.mint(pid, lpAmount);
        bank.putCollateral(address(wIchiFarm), id, lpAmount);
    }

    function withdrawInternal(
        address token,
        uint256 amountRepay,
        uint256 amountLpWithdraw,
        uint256 amountUWithdraw
    ) internal {
        IICHIVault vault = IICHIVault(vaults[token]);
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

        swapPool = IUniswapV3Pool(vault.pool());
        swapPool.swap(
            address(this),
            // if withdraw token is Token0, then swap token1 -> token0 (false)
            !isTokenA,
            int256(amountToSwap),
            isTokenA
                ? TickMath.MAX_SQRT_RATIO - 1 // Token0 -> Token1
                : TickMath.MIN_SQRT_RATIO + 1, // Token1 -> Token0
            abi.encode(address(this))
        );

        // 6. Withdraw isolated collateral from Bank
        doWithdraw(token, amountUWithdraw);

        // 7. Repay
        doRepay(token, amountRepay);

        // 8. Refund
        doRefund(token);
    }

    /**
     * @notice External function to withdraw assets from ICHI Vault
     * @param token Token address to withdraw (e.g USDC)
     * @param lpTakeAmt Amount of ICHI Vault LP token to take out from Bank
     * @param amountRepay Amount to repay the loan
     * @param amountLpWithdraw Amount of ICHI Vault LP to withdraw from ICHI Vault
     * @param amountUWithdraw Amount of Isolated collateral to withdraw from Compound
     */
    function withdraw(
        address token,
        uint256 lpTakeAmt,
        uint256 amountRepay,
        uint256 amountLpWithdraw,
        uint256 amountUWithdraw
    ) external {
        IICHIVault vault = IICHIVault(vaults[token]);

        // 1. Take out collateral
        doTakeCollateral(address(vault), lpTakeAmt);

        withdrawInternal(token, amountRepay, amountLpWithdraw, amountUWithdraw);
    }

    function withdrawFarm(
        address token,
        uint256 lpTakeAmt,
        uint256 amountRepay,
        uint256 amountLpWithdraw,
        uint256 amountUWithdraw
    ) external {
        address vault = vaults[token];
        (, address collToken, uint256 collId, , ) = bank
            .getCurrentPositionInfo();
        require(
            IWIchiFarm(collToken).getUnderlyingToken(collId) == vault,
            'incorrect underlying'
        );
        require(
            collToken == address(wIchiFarm),
            'collateral token & wmasterchef mismatched'
        );

        // 1. Take out collateral
        bank.takeCollateral(address(wIchiFarm), collId, lpTakeAmt);
        wIchiFarm.burn(collId, lpTakeAmt);

        // 2-8. remove liquidity
        withdrawInternal(token, amountRepay, amountLpWithdraw, amountUWithdraw);

        // 9. Refund sushi
        doRefund(ICHI);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(swapPool), 'cb2');
        address payer = abi.decode(data, (address));

        if (amount0Delta > 0) {
            if (payer == address(this)) {
                IERC20(swapPool.token0()).safeTransfer(
                    msg.sender,
                    uint256(amount0Delta)
                );
            } else {
                IERC20(swapPool.token0()).safeTransferFrom(
                    payer,
                    msg.sender,
                    uint256(amount0Delta)
                );
            }
        } else if (amount1Delta > 0) {
            if (payer == address(this)) {
                IERC20(swapPool.token1()).safeTransfer(
                    msg.sender,
                    uint256(amount1Delta)
                );
            } else {
                IERC20(swapPool.token1()).safeTransferFrom(
                    payer,
                    msg.sender,
                    uint256(amount1Delta)
                );
            }
        }
    }
}
