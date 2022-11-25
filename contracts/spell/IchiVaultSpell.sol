// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

import './BasicSpell.sol';
import '../libraries/UniV3/TickMath.sol';
import '../interfaces/IWIchiFarm.sol';
import '../interfaces/ichi/IICHIVault.sol';
import '../interfaces/uniswap/v3/IUniswapV3Pool.sol';
import '../interfaces/uniswap/v3/IUniswapV3SwapCallback.sol';

import 'hardhat/console.sol';

contract IchiVaultSpell is BasicSpell, IUniswapV3SwapCallback {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev temperory state used to store uni v3 pool when swapping on uni v3
    IUniswapV3Pool private swapPool;
    /// @dev underlying token => ichi vault
    mapping(address => address) public vaults;

    /// @dev address of ICHI farm wrapper
    IWIchiFarm public wIchiFarm;
    /// @dev address of ICHI token
    address public ICHI;

    function initialize(
        IBank _bank,
        address _werc20,
        address _weth,
        address _wichiFarm
    ) external initializer {
        __BasicSpell_init(_bank, _werc20, _weth);

        wIchiFarm = IWIchiFarm(_wichiFarm);
        ICHI = address(wIchiFarm.ICHI());
        IWIchiFarm(_wichiFarm).setApprovalForAll(address(_bank), true);
    }

    /**
     * @notice Owner privileged function to add vault
     * @param token Underlying asset address of vault
     * @param vault Address of ICHI angel vault
     */
    function addVault(address token, address vault) external onlyOwner {
        if (token == address(0) || vault == address(0)) revert ZERO_ADDRESS();
        vaults[token] = vault;
    }

    /**
     * @notice Internal function to deposit assets on ICHI Vault
     * @param collToken Isolated collateral token address
     * @param collAmount Amount of isolated collateral
     * @param borrowToken Token address to borrow
     * @param borrowAmount amount to borrow from Bank
     */
    function depositInternal(
        address collToken,
        address borrowToken,
        uint256 collAmount,
        uint256 borrowAmount
    ) internal {
        // 1. Lend isolated collaterals on compound
        doLend(collToken, collAmount);

        // 2. Borrow specific amounts
        doBorrow(borrowToken, borrowAmount);

        // 3. Add liquidity - Deposit on ICHI Vault
        IICHIVault vault = IICHIVault(vaults[borrowToken]);
        bool isTokenA = vault.token0() == borrowToken;
        uint256 balance = IERC20(borrowToken).balanceOf(address(this));
        ensureApprove(borrowToken, address(vault));
        if (isTokenA) {
            vault.deposit(balance, 0, address(this));
        } else {
            vault.deposit(0, balance, address(this));
        }
    }

    /**
     * @notice External function to deposit assets on IchiVault
     * @param collToken Collateral Token address to deposit (e.g USDC)
     * @param collAmount Amount of user's collateral (e.g USDC)
     * @param borrowToken Address of token to borrow
     * @param borrowAmount Amount to borrow from Bank
     */
    function openPosition(
        address collToken,
        address borrowToken,
        uint256 collAmount,
        uint256 borrowAmount
    ) external {
        // 1-3 Deposit on ichi vault
        depositInternal(collToken, borrowToken, collAmount, borrowAmount);

        // 4. Put collateral - ICHI Vault Lp Token
        address vault = vaults[borrowToken];
        doPutCollateral(vault, IERC20(vault).balanceOf(address(this)));
    }

    /**
     * @notice External function to deposit assets on IchiVault and farm in Ichi Farm
     * @param collToken Collateral Token address to deposit (e.g USDC)
     * @param collAmount Amount of user's collateral (e.g USDC)
     * @param borrowToken Address of token to borrow
     * @param borrowAmount Amount to borrow from Bank
     * @param pid Pool Id of vault lp on ICHI Farm
     */
    function openPositionFarm(
        address collToken,
        address borrowToken,
        uint256 collAmount,
        uint256 borrowAmount,
        uint256 pid
    ) external {
        address vaultAddr = vaults[borrowToken];
        address lpToken = wIchiFarm.ichiFarm().lpToken(pid);
        if (vaultAddr != lpToken) revert INCORRECT_LP(lpToken);

        // 1-3 Deposit on ichi vault
        depositInternal(collToken, borrowToken, collAmount, borrowAmount);

        // 4. Take out collateral
        (, address posCollToken, uint256 collId, uint256 collSize, ) = bank
            .getCurrentPositionInfo();
        if (collSize > 0) {
            (uint256 decodedPid, ) = wIchiFarm.decodeId(collId);
            if (pid != decodedPid) revert INCORRECT_PID(pid);
            if (posCollToken != address(wIchiFarm))
                revert INCORRECT_COLTOKEN(posCollToken);
            bank.takeCollateral(collSize);
            wIchiFarm.burn(collId, collSize);
        }

        // 5. Deposit on farming pool, put collateral
        ensureApprove(vaultAddr, address(wIchiFarm));
        uint256 lpAmount = IERC20(vaultAddr).balanceOf(address(this));
        uint256 id = wIchiFarm.mint(pid, lpAmount);
        bank.putCollateral(address(wIchiFarm), id, lpAmount);
    }

    /**
     * @dev Increase isolated collateral of position
     * @param token Isolated collateral token address
     * @param amount Amount of token to increase position
     */
    function increasePosition(address token, uint256 amount) external {
        // 1. Get user input amounts
        doLend(token, amount);
    }

    /**
     * @dev Reduce isolated collateral of position
     * @param token Isolated collateral token address
     * @param amount Amount of token to reduce position
     */
    function reducePosition(address token, uint256 amount) external {
        doWithdraw(token, amount);
        doRefund(token);
    }

    function withdrawInternal(
        address collToken,
        address borrowToken,
        uint256 amountRepay,
        uint256 amountLpWithdraw,
        uint256 amountUWithdraw
    ) internal {
        IICHIVault vault = IICHIVault(vaults[borrowToken]);
        // 2. Remove Liquidity - Withdraw from ICHI Vault
        if (address(vault) == address(0))
            revert LP_NOT_WHITELISTED(address(vault));
        uint256 positionId = bank.POSITION_ID();

        // 2. Compute repay amount if MAX_INT is supplied (max debt)
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.borrowBalanceCurrent(positionId, borrowToken);
        }

        // 3. Calculate actual amount to remove
        uint256 amtLPToRemove = vault.balanceOf(address(this)) -
            amountLpWithdraw;

        // 4. Remove liquidity
        vault.withdraw(amtLPToRemove, address(this));

        // 5. Swap withdrawn tokens to initial deposit token
        bool isTokenA = vault.token0() == borrowToken;
        uint256 amountToSwap = IERC20(
            isTokenA ? vault.token1() : vault.token0()
        ).balanceOf(address(this));
        if (amountToSwap > 0) {
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
        }

        // 6. Withdraw isolated collateral from Bank
        doWithdraw(collToken, amountUWithdraw);

        // 7. Repay
        doRepay(borrowToken, amountRepay);

        // 8. Refund
        doRefund(borrowToken);
        doRefund(collToken);
    }

    /**
     * @notice External function to withdraw assets from ICHI Vault
     * @param collToken Token address to withdraw (e.g USDC)
     * @param borrowToken Token address to withdraw (e.g USDC)
     * @param lpTakeAmt Amount of ICHI Vault LP token to take out from Bank
     * @param amountRepay Amount to repay the loan
     * @param amountLpWithdraw Amount of ICHI Vault LP to withdraw from ICHI Vault
     * @param amountUWithdraw Amount of Isolated collateral to withdraw from Compound
     */
    function closePosition(
        address collToken,
        address borrowToken,
        uint256 lpTakeAmt,
        uint256 amountRepay,
        uint256 amountLpWithdraw,
        uint256 amountUWithdraw
    ) external {
        IICHIVault vault = IICHIVault(vaults[borrowToken]);

        // 1. Take out collateral
        doTakeCollateral(address(vault), lpTakeAmt);

        withdrawInternal(
            collToken,
            borrowToken,
            amountRepay,
            amountLpWithdraw,
            amountUWithdraw
        );
    }

    function closePositionFarm(
        address collToken,
        address borrowToken,
        uint256 lpTakeAmt,
        uint256 amountRepay,
        uint256 amountLpWithdraw,
        uint256 amountUWithdraw
    ) external {
        address vault = vaults[borrowToken];
        (, address posCollToken, uint256 collId, , ) = bank
            .getCurrentPositionInfo();
        if (IWIchiFarm(posCollToken).getUnderlyingToken(collId) != vault)
            revert INCORRECT_UNDERLYING(vault);
        if (posCollToken != address(wIchiFarm))
            revert INCORRECT_COLTOKEN(posCollToken);

        // 1. Take out collateral
        bank.takeCollateral(lpTakeAmt);
        wIchiFarm.burn(collId, lpTakeAmt);

        // 2-8. remove liquidity
        withdrawInternal(
            collToken,
            borrowToken,
            amountRepay,
            amountLpWithdraw,
            amountUWithdraw
        );

        // 9. Refund ichi token
        doCutRewardsFee(ICHI);
        doRefund(ICHI);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        if (msg.sender != address(swapPool)) revert NOT_FROM_UNIV3(msg.sender);
        address payer = abi.decode(data, (address));

        if (amount0Delta > 0) {
            if (payer == address(this)) {
                IERC20Upgradeable(swapPool.token0()).safeTransfer(
                    msg.sender,
                    uint256(amount0Delta)
                );
            } else {
                IERC20Upgradeable(swapPool.token0()).safeTransferFrom(
                    payer,
                    msg.sender,
                    uint256(amount0Delta)
                );
            }
        } else if (amount1Delta > 0) {
            if (payer == address(this)) {
                IERC20Upgradeable(swapPool.token1()).safeTransfer(
                    msg.sender,
                    uint256(amount1Delta)
                );
            } else {
                IERC20Upgradeable(swapPool.token1()).safeTransferFrom(
                    payer,
                    msg.sender,
                    uint256(amount1Delta)
                );
            }
        }
    }
}
