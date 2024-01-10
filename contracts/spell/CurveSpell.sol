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

import "./BasicSpell.sol";
import "../interfaces/ICurveOracle.sol";
import "../interfaces/IWCurveGauge.sol";
import "../interfaces/curve/ICurvePool.sol";
import "../libraries/Paraswap/PSwapLib.sol";
import "../libraries/UniversalERC20.sol";

/**
 * @title CurveSpell
 * @author BlueberryProtocol
 * @notice CurveSpell is the factory contract that
 * defines how Blueberry Protocol interacts with Curve pools
 */
contract CurveSpell is BasicSpell {
    using UniversalERC20 for IERC20;

    /// @dev address of Wrapped Curve Gauge
    IWCurveGauge public wCurveGauge;
    /// @dev address of CurveOracle
    ICurveOracle public crvOracle;
    /// @dev address of CRV token
    address public crvToken;

    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address wCurveGauge_,
        address crvOracle_,
        address augustusSwapper_,
        address tokenTransferProxy_
    ) external initializer {
        __BasicSpell_init(bank_, werc20_, weth_, augustusSwapper_, tokenTransferProxy_);
        if (wCurveGauge_ == address(0) || crvOracle_ == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        wCurveGauge = IWCurveGauge(wCurveGauge_);
        crvToken = address(wCurveGauge.crvToken());
        crvOracle = ICurveOracle(crvOracle_);
        IWCurveGauge(wCurveGauge_).setApprovalForAll(address(bank_), true);

        augustusSwapper = augustusSwapper_;
        tokenTransferProxy = tokenTransferProxy_;
    }

    /**
     * @notice Add strategy to the spell
     * @param crvLp Address of crv lp token for given strategy
     * @param minPosSize, USD price of minimum position size for given strategy, based 1e18
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(address crvLp, uint256 minPosSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(crvLp, minPosSize, maxPosSize);
    }

    /**
     * @notice Add liquidity to Curve pool with 2 underlying tokens, with staking to Curve gauge
     * @param minLPMint Desired LP token amount (slippage control)
     */
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minLPMint
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        address lp = strategies[param.strategyId].vault;
        if (wCurveGauge.getLpFromGaugeId(param.farmingPoolId) != lp) {
            revert Errors.INCORRECT_LP(lp);
        }
        (address pool, address[] memory tokens, ) = crvOracle.getPoolInfo(lp);

        // 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        // 2. Borrow specific amounts
        uint256 borrowBalance = _doBorrow(param.borrowToken, param.borrowAmount);

        // 3. Add liquidity on curve
        {
            address borrowToken = param.borrowToken;
            IERC20(borrowToken).universalApprove(pool, borrowBalance);
            uint256 ethValue;
            uint256 tokenBalance = IERC20(borrowToken).universalBalanceOf(address(this));
            require(borrowBalance <= tokenBalance, "impossible");
            if (borrowToken == WETH) {
                bool hasEth;
                uint256 tokenLength = tokens.length;
                for (uint256 i; i != tokenLength; ++i) {
                    if (tokens[i] == ETH) {
                        hasEth = true;
                        break;
                    }
                }
                if (hasEth) {
                    IWETH(borrowToken).withdraw(tokenBalance);
                    ethValue = tokenBalance;
                }
            }

            if (tokens.length == 2) {
                uint256[2] memory suppliedAmts;

                for (uint256 i; i < 2; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == ETH && borrowToken == WETH)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }
                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, minLPMint);
            } else if (tokens.length == 3) {
                uint256[3] memory suppliedAmts;

                for (uint256 i; i < 3; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == ETH && borrowToken == WETH)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }
                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, minLPMint);
            } else if (tokens.length == 4) {
                uint256[4] memory suppliedAmts;

                for (uint256 i; i < 4; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == ETH && borrowToken == WETH)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }
                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, minLPMint);
            }
        }

        // 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        // 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);

        // 6. Take out collateral and burn
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collateralSize > 0) {
            (uint256 decodedGid, ) = wCurveGauge.decodeId(pos.collId);
            if (param.farmingPoolId != decodedGid) {
                revert Errors.INCORRECT_PID(param.farmingPoolId);
            }
            if (pos.collToken != address(wCurveGauge)) {
                revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            }
            bank.takeCollateral(pos.collateralSize);
            wCurveGauge.burn(pos.collId, pos.collateralSize);
            _doRefundRewards(crvToken);
        }

        // 7. Deposit on Curve Gauge, Put wrapped collateral tokens on Blueberry Bank
        uint256 lpAmount = IERC20(lp).balanceOf(address(this));
        IERC20(lp).universalApprove(address(wCurveGauge), lpAmount);
        uint256 id = wCurveGauge.mint(param.farmingPoolId, lpAmount);
        bank.putCollateral(address(wCurveGauge), id, lpAmount);
    }

    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata amounts,
        bytes[] calldata swapDatas,
        uint256 deadline
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        if (block.timestamp > deadline) revert Errors.EXPIRED(deadline);

        address crvLp = strategies[param.strategyId].vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collToken != address(wCurveGauge)) {
            revert Errors.INCORRECT_COLTOKEN(pos.collToken);
        }
        if (wCurveGauge.getUnderlyingToken(pos.collId) != crvLp) {
            revert Errors.INCORRECT_UNDERLYING(crvLp);
        }

        // 1. Take out collateral - Burn wrapped tokens, receive crv lp tokens and harvest CRV
        bank.takeCollateral(param.amountPosRemove);
        wCurveGauge.burn(pos.collId, param.amountPosRemove);

        {
            // 2. Swap rewards tokens to debt token
            _swapOnParaswap(crvToken, amounts[0], swapDatas[0]);
        }

        {
            address[] memory tokens;
            {
                address pool;
                (pool, tokens, ) = crvOracle.getPoolInfo(crvLp);

                // 3. Calculate actual amount to remove
                uint256 amountPosRemove = param.amountPosRemove;
                if (amountPosRemove == type(uint256).max) {
                    amountPosRemove = IERC20(crvLp).balanceOf(address(this));
                }

                // 4. Remove liquidity
                _removeLiquidity(param, pool, tokens, pos, amountPosRemove);
            }
        }

        // 5. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        // 6. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(param.collToken, param.amountToSwap, param.swapData);

        // 7. Repay
        {
            // Compute repay amount if MAX_INT is supplied (max debt)
            uint256 amountRepay = param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        _validateMaxLTV(param.strategyId);

        // 8. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
        _doRefund(crvToken);
    }

    function _removeLiquidity(
        ClosePosParam memory param,
        address pool,
        address[] memory tokens,
        IBank.Position memory pos,
        uint256 amountPosRemove
    ) internal {
        uint256 tokenIndex;
        uint256 len = tokens.length;
        {
            for (uint256 i; i < len; ++i) {
                if (tokens[i] == pos.debtToken) {
                    tokenIndex = i;
                    break;
                }
            }
        }

        ICurvePool(pool).remove_liquidity_one_coin(amountPosRemove, int128(uint128(tokenIndex)), param.amountOutMin);

        if (tokens[uint128(tokenIndex)] == ETH) {
            IWETH(WETH).deposit{ value: address(this).balance }();
        }
    }

    function _swapOnParaswap(address token, uint256 amount, bytes calldata swapData) internal {
        if (amount == 0) return;
        if (!PSwapLib.swap(augustusSwapper, tokenTransferProxy, token, amount, swapData)) {
            revert Errors.SWAP_FAILED(token);
        }

        // Refund rest amount to owner
        _doRefund(token);
    }
}
