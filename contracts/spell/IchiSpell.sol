// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import "./BasicSpell.sol";
import "../interfaces/IWIchiFarm.sol";
import "../interfaces/ichi/IICHIVault.sol";
import "../interfaces/uniswap/IUniswapV3Router.sol";

/**
 * @title IchiSpell
 * @author BlueberryProtocol
 * @notice IchiSpell is the factory contract that
 * defines how Blueberry Protocol interacts with Ichi Vaults
 */
contract IchiSpell is BasicSpell, IUniswapV3SwapCallback {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev temperory state used to store uni v3 pool when swapping on uni v3
    IUniswapV3Pool private SWAP_POOL;

    /// @dev address of uniswap v3 router
    IUniswapV3Router private uniV3Router;

    /// @dev address of ICHI farm wrapper
    IWIchiFarm public wIchiFarm;
    /// @dev address of ICHI token
    address public ICHI;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address wichiFarm_,
        address uniV3Router_
    ) external initializer {
        __BasicSpell_init(bank_, werc20_, weth_);
        if (wichiFarm_ == address(0)) revert Errors.ZERO_ADDRESS();

        wIchiFarm = IWIchiFarm(wichiFarm_);
        ICHI = address(wIchiFarm.ICHI());
        wIchiFarm.setApprovalForAll(address(bank_), true);

        uniV3Router = IUniswapV3Router(uniV3Router_);
    }

    /**
     * @notice Add strategy to the spell
     * @param vault Address of vault for given strategy
     * @param minPosSize, USD price of minimum position size for given strategy, based 1e18
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address vault, uint256 minPosSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(vault, minPosSize, maxPosSize);
    }

    /**
     * @notice Internal function to deposit assets on ICHI Vault
     * @dev Deposit isolated underlying to Blueberry Money Market,
     *      Borrow tokens from Blueberry Money Market,
     *      Then deposit borrowed tokens on ICHI vault
     */
    function _deposit(OpenPosParam calldata param) internal {
        Strategy memory strategy = strategies[param.strategyId];

        // 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        // 2. Borrow specific amounts
        IICHIVault vault = IICHIVault(strategy.vault);
        if (
            vault.token0() != param.borrowToken &&
            vault.token1() != param.borrowToken
        ) revert Errors.INCORRECT_DEBT(param.borrowToken);
        uint256 borrowBalance = _doBorrow(
            param.borrowToken,
            param.borrowAmount
        );

        // 3. Add liquidity - Deposit on ICHI Vault
        bool isTokenA = vault.token0() == param.borrowToken;
        _ensureApprove(param.borrowToken, address(vault), borrowBalance);

        uint ichiVaultShare;
        if (isTokenA) {
            ichiVaultShare = vault.deposit(borrowBalance, 0, address(this));
        } else {
            ichiVaultShare = vault.deposit(0, borrowBalance, address(this));
        }

        // 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        // 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);
    }

    /**
     * @notice External function to deposit assets on IchiVault
     */
    function openPosition(
        OpenPosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        // 1-5 Deposit on ichi vault
        _deposit(param);

        // 6. Put collateral - ICHI Vault Lp Token
        address vault = strategies[param.strategyId].vault;
        _doPutCollateral(
            vault,
            IERC20Upgradeable(vault).balanceOf(address(this))
        );
    }

    /**
     * @notice External function to deposit assets on IchiVault and farm in Ichi Farm
     */
    function openPositionFarm(
        OpenPosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        Strategy memory strategy = strategies[param.strategyId];
        address lpToken = wIchiFarm.ichiFarm().lpToken(param.farmingPoolId);
        if (strategy.vault != lpToken) revert Errors.INCORRECT_LP(lpToken);

        // 1-5 Deposit on ichi vault
        _deposit(param);

        // 6. Take out collateral and burn
        {
            IBank.Position memory pos = bank.getCurrentPositionInfo();
            address posCollToken = pos.collToken;
            uint256 collId = pos.collId;
            uint256 collSize = pos.collateralSize;
            if (collSize > 0) {
                (uint256 decodedPid, ) = wIchiFarm.decodeId(collId);
                if (param.farmingPoolId != decodedPid)
                    revert Errors.INCORRECT_PID(param.farmingPoolId);
                if (posCollToken != address(wIchiFarm))
                    revert Errors.INCORRECT_COLTOKEN(posCollToken);
                bank.takeCollateral(collSize);
                wIchiFarm.burn(collId, collSize);
                _doRefundRewards(ICHI);
            }
        }

        // 5. Deposit on farming pool, put collateral
        uint256 lpAmount = IERC20Upgradeable(lpToken).balanceOf(address(this));
        _ensureApprove(lpToken, address(wIchiFarm), lpAmount);
        uint256 id = wIchiFarm.mint(param.farmingPoolId, lpAmount);
        bank.putCollateral(address(wIchiFarm), id, lpAmount);
    }

    /**
     * @notice Internal function to withdraw assets from ICHI Vault
     * @dev Withdraw assets from ICHI Vault,
     *      Swap withdrawn assets to debt token,
     *      Withdraw isolated collaterals from Blueberry Money Market,
     *      Repay Debt and refund rest to user
     */
    function _withdraw(ClosePosParam calldata param) internal {
        if (param.sellSlippage > bank.config().maxSlippageOfClose())
            revert Errors.RATIO_TOO_HIGH(param.sellSlippage);

        Strategy memory strategy = strategies[param.strategyId];
        IICHIVault vault = IICHIVault(strategy.vault);

        // 1. Compute repay amount if MAX_INT is supplied (max debt)
        uint256 amountRepay = param.amountRepay;
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
        }

        // 2. Calculate actual amount to remove
        uint256 amountPosRemove = param.amountPosRemove;
        if (amountPosRemove == type(uint256).max) {
            amountPosRemove = vault.balanceOf(address(this));
        }

        // 3. Withdraw liquidity from ICHI vault
        vault.withdraw(amountPosRemove, address(this));

        // 4. Swap withdrawn tokens to debt token
        bool isTokenA = vault.token0() == param.borrowToken;
        uint256 amountIn = IERC20Upgradeable(
            isTokenA ? vault.token1() : vault.token0()
        ).balanceOf(address(this));

        if (amountIn > 0) {
            uint160 deltaSqrt = (param.sqrtRatioLimit *
                uint160(param.sellSlippage)) / uint160(Constants.DENOMINATOR);
            address[] memory swapPath = new address[](2);
            swapPath[0] = isTokenA ? vault.token1() : vault.token0();
            swapPath[1] = isTokenA ? vault.token0() : vault.token1();

            uint256 amountOutMin = _getMinOutAmount(
                swapPath[0],
                swapPath[1],
                amountIn,
                param.sellSlippage
            );

            IUniswapV3Router.ExactInputSingleParams
                memory params = IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: swapPath[0],
                    tokenOut: swapPath[1],
                    fee: IUniswapV3Pool(vault.pool()).fee(),
                    recipient: address(this),
                    deadline: block.timestamp + Constants.MAX_DELAY_ON_SWAP,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin,
                    sqrtPriceLimitX96: isTokenA
                        ? param.sqrtRatioLimit + deltaSqrt
                        : param.sqrtRatioLimit - deltaSqrt
                });

            _ensureApprove(params.tokenIn, address(uniV3Router), amountIn);
            uniV3Router.exactInputSingle(params);
        }

        // 5. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        // 6. Repay
        _doRepay(param.borrowToken, amountRepay);

        _validateMaxLTV(param.strategyId);

        // 7. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }

    /**
     * @notice Internal function to get outToken amount based on inToken amount
     * @param inToken Address of inToken
     * @param outToken Address of outToken
     * @param amountIn Amount of inToken
     * @param slippage Swap slippage
     */
    function _getMinOutAmount(
        address inToken,
        address outToken,
        uint256 amountIn,
        uint256 slippage
    ) internal returns (uint256) {
        uint256 inTokenPrice = bank.oracle().getPrice(inToken);
        uint256 outTokenPrice = bank.oracle().getPrice(outToken);
        uint256 inTokenDecimal = IERC20MetadataUpgradeable(inToken).decimals();
        uint256 outTokenDecimal = IERC20MetadataUpgradeable(outToken)
            .decimals();

        // calculate amountOut based on this formular. token0 blance * token0 price = token1 balance * token1 price
        // decimal should be considered
        uint256 amountOut = ((amountIn * inTokenPrice) *
            (10 ** outTokenDecimal)) / (outTokenPrice * (10 ** inTokenDecimal));

        return
            (amountOut * (Constants.DENOMINATOR - slippage)) /
            Constants.DENOMINATOR;
    }

    /**
     * @notice External function to withdraw assets from ICHI Vault
     */
    function closePosition(
        ClosePosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        // 1. Take out collateral
        _doTakeCollateral(
            strategies[param.strategyId].vault,
            param.amountPosRemove
        );

        // 2-8. Remove liquidity
        _withdraw(param);
    }

    function closePositionFarm(
        ClosePosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        address vault = strategies[param.strategyId].vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;
        if (IWIchiFarm(posCollToken).getUnderlyingToken(collId) != vault)
            revert Errors.INCORRECT_UNDERLYING(vault);
        if (posCollToken != address(wIchiFarm))
            revert Errors.INCORRECT_COLTOKEN(posCollToken);

        // 1. Take out collateral
        bank.takeCollateral(param.amountPosRemove);
        wIchiFarm.burn(collId, param.amountPosRemove);
        _doRefundRewards(ICHI);

        // 2-8. Remove liquidity
        _withdraw(param);

        // 9. Refund ichi token
        _doRefund(ICHI);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        if (msg.sender != address(SWAP_POOL))
            revert Errors.NOT_FROM_UNIV3(msg.sender);
        address payer = abi.decode(data, (address));

        if (amount0Delta > 0) {
            if (payer == address(this)) {
                IERC20Upgradeable(SWAP_POOL.token0()).safeTransfer(
                    msg.sender,
                    amount0Delta.toUint256()
                );
            } else {
                IERC20Upgradeable(SWAP_POOL.token0()).safeTransferFrom(
                    payer,
                    msg.sender,
                    amount0Delta.toUint256()
                );
            }
        } else if (amount1Delta > 0) {
            if (payer == address(this)) {
                IERC20Upgradeable(SWAP_POOL.token1()).safeTransfer(
                    msg.sender,
                    amount1Delta.toUint256()
                );
            } else {
                IERC20Upgradeable(SWAP_POOL.token1()).safeTransferFrom(
                    payer,
                    msg.sender,
                    amount1Delta.toUint256()
                );
            }
        }
    }
}
