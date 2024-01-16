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

import { PSwapLib } from "../libraries/Paraswap/PSwapLib.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BasicSpell } from "./BasicSpell.sol";

import { IBank } from "../interfaces/IBank.sol";
import { ICurveOracle } from "../interfaces/ICurveOracle.sol";
import { ICurvePool } from "../interfaces/curve/ICurvePool.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { IWCurveGauge } from "../interfaces/IWCurveGauge.sol";

import { ICurveSpell } from "../interfaces/spell/ICurveSpell.sol";

/**
 * @title CurveSpell
 * @author BlueberryProtocol
 * @notice CurveSpell is the factory contract that
 *     defines how Blueberry Protocol interacts with Curve pools
 */
contract CurveSpell is ICurveSpell, BasicSpell {
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev address of Wrapped Curve Gauge
    IWCurveGauge private _wCurveGauge;
    /// @dev address of CurveOracle
    ICurveOracle private _crvOracle;
    /// @dev address of CRV token
    address private _crvToken;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with required parameters.
     * @param bank Reference to the Bank contract.
     * @param werc20 Reference to the WERC20 contract.
     * @param weth Address of the wrapped Ether token.
     * @param wCurveGauge Address of the wrapped Curve Gauge contract.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address wCurveGauge,
        address crvOracle,
        address augustusSwapper,
        address tokenTransferProxy
    ) external initializer {
        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy);
        if (wCurveGauge == address(0) || crvOracle == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _wCurveGauge = IWCurveGauge(wCurveGauge);
        _crvToken = address(IWCurveGauge(wCurveGauge).getCrvToken());
        _crvOracle = ICurveOracle(crvOracle);
        IWCurveGauge(wCurveGauge).setApprovalForAll(address(bank), true);

        augustusSwapper = augustusSwapper;
        tokenTransferProxy = tokenTransferProxy;
    }

    /// @inheritdoc ICurveSpell
    function addStrategy(address crvLp, uint256 minPosSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(crvLp, minPosSize, maxPosSize);
    }

    /// @inheritdoc ICurveSpell
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minLPMint
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        uint256 _minLPMint = minLPMint;
        address lp = _strategies[param.strategyId].vault;
        if (_wCurveGauge.getLpFromGaugeId(param.farmingPoolId) != lp) {
            revert Errors.INCORRECT_LP(lp);
        }

        (address pool, address[] memory tokens, ) = _crvOracle.getPoolInfo(lp);

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
            address weth = _weth;

            if (borrowBalance > tokenBalance) {
                revert Errors.INSUFFICIENT_COLLATERAL();
            }

            if (borrowToken == weth) {
                bool hasEth;
                uint256 tokenLength = tokens.length;
                for (uint256 i; i != tokenLength; ++i) {
                    if (tokens[i] == _ETH) {
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
                    if ((tokens[i] == borrowToken) || (tokens[i] == _ETH && borrowToken == weth)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }
                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, _minLPMint);
            } else if (tokens.length == 3) {
                uint256[3] memory suppliedAmts;

                for (uint256 i; i < 3; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == _ETH && borrowToken == weth)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }
                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, _minLPMint);
            } else if (tokens.length == 4) {
                uint256[4] memory suppliedAmts;

                for (uint256 i; i < 4; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == _ETH && borrowToken == weth)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }
                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, _minLPMint);
            }
        }

        // 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        // 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);

        IBank bank = getBank();
        IWCurveGauge wCurveGauge = getWCurveGauge();

        {
            // 6. Take out collateral and burn
            IBank.Position memory pos = bank.getCurrentPositionInfo();
            if (pos.collateralSize > 0) {
                if (param.farmingPoolId != _getGaugeId(pos.collId)) {
                    revert Errors.INCORRECT_PID(param.farmingPoolId);
                }

                if (pos.collToken != address(wCurveGauge)) {
                    revert Errors.INCORRECT_COLTOKEN(pos.collToken);
                }

                bank.takeCollateral(pos.collateralSize);
                wCurveGauge.burn(pos.collId, pos.collateralSize);

                _doRefundRewards(_crvToken);
            }
        }
        {
            // 7. Deposit on Curve Gauge, Put wrapped collateral tokens on Blueberry Bank
            uint256 lpAmount = IERC20(lp).balanceOf(address(this));
            IERC20(lp).universalApprove(address(wCurveGauge), lpAmount);

            uint256 id = wCurveGauge.mint(param.farmingPoolId, lpAmount);
            _bank.putCollateral(address(wCurveGauge), id, lpAmount);
        }
    }

    /// @inheritdoc ICurveSpell
    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata amounts,
        bytes[] calldata swapDatas,
        uint256 deadline
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        if (block.timestamp > deadline) revert Errors.EXPIRED(deadline);

        IBank bank = getBank();
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address crvLp = _strategies[param.strategyId].vault;

        {
            IWCurveGauge wCurveGauge = getWCurveGauge();

            if (pos.collToken != address(wCurveGauge)) {
                revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            }

            if (wCurveGauge.getUnderlyingToken(pos.collId) != crvLp) {
                revert Errors.INCORRECT_UNDERLYING(crvLp);
            }

            // 1. Take out collateral - Burn wrapped tokens, receive crv lp tokens and harvest CRV
            bank.takeCollateral(param.amountPosRemove);
            wCurveGauge.burn(pos.collId, param.amountPosRemove);
        }

        // 2. Swap rewards tokens to debt token
        _swapOnParaswap(getCrvToken(), amounts[0], swapDatas[0]);

        {
            address[] memory tokens;
            address pool;
            (pool, tokens, ) = _crvOracle.getPoolInfo(crvLp);

            // 3. Calculate actual amount to remove
            uint256 amountPosRemove = param.amountPosRemove;
            if (amountPosRemove == type(uint256).max) {
                amountPosRemove = IERC20(crvLp).balanceOf(address(this));
            }

            // 4. Remove liquidity
            _removeLiquidity(param, pool, tokens, pos, amountPosRemove);
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
        _doRefund(getCrvToken());
    }

    /// @inheritdoc ICurveSpell
    function getWCurveGauge() public view override returns (IWCurveGauge) {
        return _wCurveGauge;
    }

    /// @inheritdoc ICurveSpell
    function getCrvToken() public view override returns (address) {
        return _crvToken;
    }

    /// @inheritdoc ICurveSpell
    function getCurveOracle() external view returns (ICurveOracle) {
        return _crvOracle;
    }

    /**
     * @notice Removes liquidity from a Curve pool.
     * @param param Parameters required for closing a position.
     * @param pool The Curve pool address.
     * @param tokens Array of token addresses in the Curve pool.
     * @param pos Position struct containing information about the current position.
     * @param amountPosRemove Amount of LP tokens to burn to remove a position.
     */
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

        if (tokens[uint128(tokenIndex)] == _ETH) {
            IWETH(_weth).deposit{ value: address(this).balance }();
        }
    }

    /**
     * @notice Swaps token on Paraswap and refunds the rest amount to owner.
     * @param token Token to swap for
     * @param amount Amount of token to swap for
     * @param swapData Call data for the swap
     */
    function _swapOnParaswap(address token, uint256 amount, bytes calldata swapData) internal {
        if (amount == 0) return;
        if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, token, amount, swapData)) {
            revert Errors.SWAP_FAILED(token);
        }

        // Refund rest amount to owner
        _doRefund(token);
    }

    /**
     * @notice Returns the gauge ID from an ERC1155 token ID.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     */
    function _getGaugeId(uint256 tokenId) internal view returns (uint256 gid) {
        (gid, ) = _wCurveGauge.decodeId(tokenId);
    }
}
