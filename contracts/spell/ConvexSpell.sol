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

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { PSwapLib } from "../libraries/Paraswap/PSwapLib.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BasicSpell } from "./BasicSpell.sol";

import { IBank } from "../interfaces/IBank.sol";
import { ICurveOracle } from "../interfaces/ICurveOracle.sol";
import { ICurveZapDepositor } from "../interfaces/ICurveZapDepositor.sol";
import { ICurvePool } from "../interfaces/curve/ICurvePool.sol";
import { IWConvexBooster } from "../interfaces/IWConvexBooster.sol";
import { IWETH } from "../interfaces/IWETH.sol";

import { IConvexSpell } from "../interfaces/spell/IConvexSpell.sol";

/**
 * @title ConvexSpell
 * @author BlueberryProtocol
 * @notice This contract serves as the factory for defining how the Blueberry Protocol
        interacts with Convex pools. It handles strategies, interactions with 
        external contracts, and facilitates operations related to liquidity provision.
 */
contract ConvexSpell is IConvexSpell, BasicSpell {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the Wrapped Convex Pools
    IWConvexBooster private _wConvexBooster;
    /// @dev address of CurveOracle to retrieve pool information
    ICurveOracle private _crvOracle;
    /// @dev address of CVX token
    address private _cvxToken;

    /// @dev Curve Zap Depositor for USD metapools
    address private constant _CURVE_ZAP_DEPOSITOR = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;
    /// @dev _THREE_CRV token address
    address private constant _THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    /// @dev _DAI token address
    address private constant _DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    /// @dev _USDC token address
    address private constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    /// @dev _USDT token address
    address private constant _USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ConvexSpell contract with required parameters.
     * @param bank Address of the bank contract.
     * @param werc20 Address of the wrapped ERC20 contract.
     * @param weth Address of the wrapped Ethereum contract.
     * @param wConvexBooster Address of the wrapped Convex pools contract.
     * @param crvOracle Address of the Curve Oracle contract.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     * @param owner Address of the owner of the contract.
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address wConvexBooster,
        address crvOracle,
        address augustusSwapper,
        address tokenTransferProxy,
        address owner
    ) external initializer {
        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy, owner);
        if (wConvexBooster == address(0) || crvOracle == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _wConvexBooster = IWConvexBooster(wConvexBooster);
        _cvxToken = address(IWConvexBooster(wConvexBooster).getCvxToken());
        _crvOracle = ICurveOracle(crvOracle);
        IWConvexBooster(wConvexBooster).setApprovalForAll(address(bank), true);
    }

    /// @inheritdoc IConvexSpell
    function addStrategy(address crvLp, uint256 minCollSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(crvLp, minCollSize, maxPosSize);
    }

    /// @inheritdoc IConvexSpell
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minLPMint
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        uint256 _minLPMint = minLPMint;
        Strategy memory strategy = _strategies[param.strategyId];

        IWConvexBooster wConvexBooster = getWConvexBooster();

        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(param.farmingPoolId);
        if (strategy.vault != lpToken) revert Errors.INCORRECT_LP(lpToken);

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        uint256 borrowBalance = _doBorrow(param.borrowToken, param.borrowAmount);

        (address pool, address[] memory tokens, ) = _crvOracle.getPoolInfo(lpToken);

        /// 3. Add liquidity on curve, get crvLp
        {
            address borrowToken = param.borrowToken;
            IERC20(borrowToken).universalApprove(pool, borrowBalance);
            uint256 ethValue;
            uint256 tokenBalance = IERC20(borrowToken).balanceOf(address(this));

            if (borrowBalance > tokenBalance) {
                revert Errors.INSUFFICIENT_COLLATERAL();
            }

            bool isBorrowTokenWeth = borrowToken == _weth;
            if (isBorrowTokenWeth) {
                bool hasEth;
                uint256 tokenLength = tokens.length;
                for (uint256 i; i < tokenLength; ++i) {
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
                if (tokens[1] == _THREE_CRV) {
                    uint256[4] memory suppliedAmts;

                    if (tokens[0] == borrowToken) {
                        suppliedAmts[0] = tokenBalance;
                    } else if (_DAI == borrowToken) {
                        suppliedAmts[1] = tokenBalance;
                    } else if (_USDC == borrowToken) {
                        suppliedAmts[2] = tokenBalance;
                    } else {
                        suppliedAmts[3] = tokenBalance;
                    }

                    IERC20(borrowToken).universalApprove(pool, 0);
                    IERC20(borrowToken).universalApprove(_CURVE_ZAP_DEPOSITOR, borrowBalance);

                    ICurveZapDepositor(_CURVE_ZAP_DEPOSITOR).add_liquidity(pool, suppliedAmts, _minLPMint);
                } else {
                    uint256[2] memory suppliedAmts;

                    for (uint256 i; i < 2; ++i) {
                        if ((tokens[i] == borrowToken) || (tokens[i] == _ETH && isBorrowTokenWeth)) {
                            suppliedAmts[i] = tokenBalance;
                            break;
                        }
                    }
                    ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, _minLPMint);
                }
            } else if (tokens.length == 3) {
                uint256[3] memory suppliedAmts;

                for (uint256 i; i < 3; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == _ETH && isBorrowTokenWeth)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }

                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, _minLPMint);
            } else if (tokens.length == 4) {
                uint256[4] memory suppliedAmts;

                for (uint256 i; i < 4; ++i) {
                    if ((tokens[i] == borrowToken) || (tokens[i] == _ETH && isBorrowTokenWeth)) {
                        suppliedAmts[i] = tokenBalance;
                        break;
                    }
                }

                ICurvePool(pool).add_liquidity{ value: ethValue }(suppliedAmts, _minLPMint);
            }
        }

        /// 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);

        {
            IBank bank = getBank();
            /// 6. Take out existing collateral and burn
            IBank.Position memory pos = bank.getCurrentPositionInfo();
            if (pos.collateralSize > 0) {
                (uint256 pid, ) = wConvexBooster.decodeId(pos.collId);

                if (param.farmingPoolId != pid) {
                    revert Errors.INCORRECT_PID(param.farmingPoolId);
                }

                if (pos.collToken != address(wConvexBooster)) {
                    revert Errors.INCORRECT_COLTOKEN(pos.collToken);
                }

                bank.takeCollateral(pos.collateralSize);

                (address[] memory rewardTokens, ) = wConvexBooster.burn(pos.collId, pos.collateralSize);
                // distribute multiple rewards to users
                uint256 tokensLength = rewardTokens.length;

                for (uint256 i; i < tokensLength; ++i) {
                    _doRefundRewards(rewardTokens[i]);
                }
            }
        }
        {
            /// 7. Deposit on Convex Pool, Put wrapped collateral tokens on Blueberry Bank
            uint256 lpAmount = IERC20(lpToken).balanceOf(address(this));
            IERC20(lpToken).universalApprove(address(wConvexBooster), lpAmount);

            uint256 id = wConvexBooster.mint(param.farmingPoolId, lpAmount);
            _bank.putCollateral(address(wConvexBooster), id, lpAmount);
        }
    }

    /// @inheritdoc IConvexSpell
    function closePositionFarm(
        ClosePositionFarmParam calldata closePosParam
    )
        external
        existingStrategy(closePosParam.param.strategyId)
        existingCollateral(closePosParam.param.strategyId, closePosParam.param.collToken)
    {
        IBank bank = getBank();
        address crvLp = _strategies[closePosParam.param.strategyId].vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();

        IWConvexBooster wConvexBooster = getWConvexBooster();

        if (pos.collToken != address(wConvexBooster)) {
            revert Errors.INCORRECT_COLTOKEN(pos.collToken);
        }

        if (wConvexBooster.getUnderlyingToken(pos.collId) != crvLp) {
            revert Errors.INCORRECT_UNDERLYING(crvLp);
        }

        uint256 amountPosRemove = closePosParam.param.amountPosRemove;

        /// 1. Take out collateral - Burn wrapped tokens, receive crv lp tokens and harvest CRV
        amountPosRemove = bank.takeCollateral(amountPosRemove);
        (address[] memory rewardTokens, ) = wConvexBooster.burn(pos.collId, amountPosRemove);

        /// 2. Swap rewards tokens to debt token
        _sellRewards(rewardTokens, closePosParam);

        /// 3. Remove liquidity
        _removeLiquidity(closePosParam.param, pos, crvLp, amountPosRemove);

        /// 4. Withdraw isolated collateral from Bank
        _doWithdraw(closePosParam.param.collToken, closePosParam.param.amountShareWithdraw);

        /// 5. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(closePosParam.param.collToken, closePosParam.param.amountToSwap, closePosParam.param.swapData);

        /// 6. Repay
        {
            /// Compute repay amount if MAX_INT is supplied (max debt)
            uint256 amountRepay = closePosParam.param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(closePosParam.param.borrowToken, amountRepay);
        }

        _validateMaxLTV(closePosParam.param.strategyId);

        /// 7. Refund
        _doRefund(closePosParam.param.borrowToken);
        _doRefund(closePosParam.param.collToken);
        _doRefund(getCvxToken());
    }

    /// @inheritdoc IConvexSpell
    function getWConvexBooster() public view override returns (IWConvexBooster) {
        return _wConvexBooster;
    }

    /// @inheritdoc IConvexSpell
    function getCvxToken() public view override returns (address) {
        return _cvxToken;
    }

    /// @inheritdoc IConvexSpell
    function getCrvOracle() public view override returns (ICurveOracle) {
        return _crvOracle;
    }

    /**
     * @notice Removes liquidity from a Curve pool for a given position.
     * @param param Contains data required to close the position.
     * @param pos Data structure representing the current bank position.
     * @param crvLp Address of the Curve LP token.
     * @param amountPosRemove Amount of LP tokens to be removed from the pool.
     *        If set to max, will remove all available LP tokens.
     */
    function _removeLiquidity(
        ClosePosParam memory param,
        IBank.Position memory pos,
        address crvLp,
        uint256 amountPosRemove
    ) internal returns (address[] memory tokens) {
        address pool;
        (pool, tokens, ) = _crvOracle.getPoolInfo(crvLp);

        if (amountPosRemove == type(uint256).max) {
            amountPosRemove = IERC20(crvLp).balanceOf(address(this));
        }

        int128 tokenIndex;
        uint256 len = tokens.length;
        for (uint256 i; i < len; ++i) {
            if (tokens[i] == pos.debtToken) {
                tokenIndex = int128(uint128(i));
                break;
            }
        }

        if (len == 2 && tokens[1] == _THREE_CRV) {
            int128 index;
            if (tokens[0] == param.borrowToken) {
                index = 0;
            } else if (_DAI == param.borrowToken) {
                index = 1;
            } else if (_USDC == param.borrowToken) {
                index = 2;
            } else {
                index = 3;
            }
            IERC20(pool).universalApprove(_CURVE_ZAP_DEPOSITOR, amountPosRemove);
            ICurveZapDepositor(_CURVE_ZAP_DEPOSITOR).remove_liquidity_one_coin(
                pool,
                amountPosRemove,
                index,
                param.amountOutMin
            );
            return _getMetaPoolTokens(tokens[0]);
        } else {
            /// Removes liquidity from the Curve pool for the specified token.
            ICurvePool(pool).remove_liquidity_one_coin(amountPosRemove, tokenIndex, param.amountOutMin);
        }

        if (tokens[uint128(tokenIndex)] == _ETH) {
            IWETH(_weth).deposit{ value: address(this).balance }();
        }
    }

    /**
     * @notice Returns an array of addresses of the tokens in the Curve metapool.
     * @param token Address of the token to be swapped.
     * @return tokens An array of addresses of the tokens in the Curve metapool.
     */
    function _getMetaPoolTokens(address token) internal pure returns (address[] memory tokens) {
        tokens = new address[](4);
        tokens[0] = token;
        tokens[1] = _DAI;
        tokens[2] = _USDC;
        tokens[3] = _USDT;
    }

    /**
     * @notice Sells the accumulated reward tokens.
     * @param rewardTokens An array of addresses of the reward tokens to be sold.
     * @param closePosParam Struct containing all required parameters for closing a position.
     */
    function _sellRewards(address[] memory rewardTokens, ClosePositionFarmParam calldata closePosParam) internal {
        uint256 tokensLength = rewardTokens.length;
        for (uint256 i; i < tokensLength; ++i) {
            address sellToken = rewardTokens[i];

            /// Apply any potential fees on the reward.
            _doCutRewardsFee(sellToken);

            if (sellToken != closePosParam.param.borrowToken) {
                uint256 expectedReward = closePosParam.amounts[i];
                /// If the expected reward is zero, skip to the next token.
                _swapOnParaswap(sellToken, expectedReward, closePosParam.swapDatas[i]);
            }
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
        if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, token, amount, swapData))
            revert Errors.SWAP_FAILED(token);

        // Refund rest amount to owner
        _doRefund(token);
    }
}
