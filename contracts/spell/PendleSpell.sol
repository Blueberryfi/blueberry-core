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
import { IWERC20 } from "../interfaces/IWERC20.sol";
import { IPMarket, IPPrincipalToken, IPYieldToken } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import { IPendleRouter } from "../interfaces/pendle-v2/IPendleRouter.sol";
import { ApproxParams, TokenInput, TokenOutput, LimitOrderData } from "../interfaces/pendle-v2/IPendleRouter.sol";

import { IWMasterPenPie } from "../interfaces/IWMasterPenPie.sol";
import { IPendleSpell } from "../interfaces/spell/IPendleSpell.sol";

/**
 * @title PendleSpell
 * @author BlueberryProtocol
 * @notice PendleSpell is the factory contract that
 *         defines how Blueberry Protocol interacts with Pendle PTs and LPs
 */
contract PendleSpell is IPendleSpell, BasicSpell {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the Pendle Router contract
    IPendleRouter private _pendleRouter;
    /// @dev Address of the Wrapped Master PenPie contract
    IWMasterPenPie private _wMasterPenPie;
    /// @dev Address of the Pendle token
    address private _pendle;
    /// @dev Address of PNP token
    address private _penPie;
    /// @dev Mapping of Principal Tokens to their respective markets
    mapping(address => address) private _ptToMarket;

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
     * @notice Initializes the contract with required parameters.
     * @param bank Reference to the Bank contract.
     * @param werc20 Reference to the WERC20 contract.
     * @param weth Address of the wrapped Ether token.
     * @param pendleRouter Address of the Pendle Router contract.
     * @param wMasterPenPie Address of the wrapped Master PenPie.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     * @param owner Address of the owner of the contract.
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address pendleRouter,
        address wMasterPenPie,
        address augustusSwapper,
        address tokenTransferProxy,
        address owner
    ) external initializer {
        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy, owner);
        if (pendleRouter == address(0) || wMasterPenPie == address(0)) revert Errors.ZERO_ADDRESS();

        _penPie = address(IWMasterPenPie(wMasterPenPie).getPenPie());
        _wMasterPenPie = IWMasterPenPie(wMasterPenPie);
        _pendleRouter = IPendleRouter(pendleRouter);
        IWMasterPenPie(wMasterPenPie).setApprovalForAll(address(bank), true);
    }

    /// @inheritdoc IPendleSpell
    function addStrategy(address token, uint256 minCollSize, uint256 maxPosSize) external override onlyOwner {
        /// TODO: Handle expirations
        _addStrategy(token, minCollSize, maxPosSize);
    }

    /// @inheritdoc IPendleSpell
    function openPosition(
        OpenPosParam calldata param,
        uint256 minimumPt,
        bytes memory data
    ) external override existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        address pt = _strategies[param.strategyId].vault;

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow funds based on specified amount
        _doBorrow(param.borrowToken, param.borrowAmount);

        /// 3. Swap borrowToken to PT
        (ApproxParams memory params, TokenInput memory input, LimitOrderData memory limitOrder) = abi.decode(
            data,
            (ApproxParams, TokenInput, LimitOrderData)
        );

        (uint256 ptAmount, , ) = IPendleRouter(_pendleRouter).swapExactTokenForPt(
            address(this),
            _ptToMarket[pt],
            minimumPt,
            params,
            input,
            limitOrder
        );

        /// 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);

        /// 6. Wrap PT and deposit to Bank
        _doPutCollateral(pt, ptAmount);
    }

    /// @inheritdoc IPendleSpell
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minimumLP,
        bytes memory data
    ) external override existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        IBank bank = getBank();
        address market = _strategies[param.strategyId].vault;
        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        address borrowToken = param.borrowToken;
        uint256 borrowAmount = param.borrowAmount;

        /// 2. Borrow funds based on specified amount
        _doBorrow(borrowToken, borrowAmount);

        /// 3. Add liquidity to Pendle Market
        {
            (ApproxParams memory params, TokenInput memory input, LimitOrderData memory limitOrder) = abi.decode(
                data,
                (ApproxParams, TokenInput, LimitOrderData)
            );

            // Deposit into the Pendle Market
            IPendleRouter(_pendleRouter).addLiquiditySingleToken(
                address(this),
                market,
                minimumLP,
                params,
                input,
                limitOrder
            );
            /// 4. Ensure that the resulting LTV does not exceed maximum allowed value.
            _validateMaxLTV(param.strategyId);

            /// 5. Ensure position size is within permissible limits.
            _validatePosSize(param.strategyId);

            /// 6. Withdraw existing collaterals and burn the associated tokens.
            IBank.Position memory pos = bank.getCurrentPositionInfo();
            if (pos.collateralSize > 0) {
                if (pos.collToken != address(_wMasterPenPie)) revert Errors.INCORRECT_COLTOKEN(pos.collToken);

                bank.takeCollateral(pos.collateralSize);

                (address[] memory rewardTokens, ) = _wMasterPenPie.burn(pos.collId, pos.collateralSize);

                // Distribute the multiple rewards to users.
                uint256 rewardTokensLength = rewardTokens.length;
                for (uint256 i; i < rewardTokensLength; ++i) {
                    _doRefundRewards(rewardTokens[i]);
                }
            }
        }

        /// 7. Deposit the tokens in the Master PenPie staking contract and place the wrapped collateral tokens in the Blueberry Bank.
        uint256 lpAmount = IERC20Upgradeable(market).balanceOf(address(this));
        IERC20(market).universalApprove(address(_wMasterPenPie), lpAmount);

        uint256 id = _wMasterPenPie.mint(market, lpAmount);
        bank.putCollateral(address(_wMasterPenPie), id, lpAmount);
    }

    /// @inheritdoc IPendleSpell
    function closePosition(
        ClosePosParam calldata param,
        bytes memory data
    ) external override existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        IBank bank = getBank();
        IWERC20 werc20 = getWrappedERC20();
        address pt = _strategies[param.strategyId].vault;

        /// 1. Validate input data
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;

        if (IWERC20(posCollToken).getUnderlyingToken(collId) != pt) revert Errors.INCORRECT_UNDERLYING(pt);
        if (posCollToken != address(werc20)) revert Errors.INCORRECT_COLTOKEN(posCollToken);

        /// 2. Take out collateral
        uint256 burnAmount = bank.takeCollateral(param.amountPosRemove);
        werc20.burn(pt, burnAmount);

        /// 3. Exit PT position
        {
            (TokenOutput memory output, LimitOrderData memory limitOrder) = abi.decode(
                data,
                (TokenOutput, LimitOrderData)
            );
            address market = _ptToMarket[pt];
            (, , IPYieldToken yt) = IPMarket(market).readTokens();

            // If the PT has expired, we need to redeem, if not we can swap
            if (IPMarket(market).isExpired()) {
                IPendleRouter(_pendleRouter).redeemPyToToken(msg.sender, address(yt), burnAmount, output);
            } else {
                IPendleRouter(_pendleRouter).swapExactPtForToken(msg.sender, market, burnAmount, output, limitOrder);
            }
        }

        /// 4. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 5. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(param.collToken, param.amountToSwap, param.swapData);

        /// 6. Repay
        {
            uint256 amountRepay = param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        /// 7. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 8. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }

    /// @inheritdoc IPendleSpell
    function closePositionFarm(
        ClosePositionFarmParam calldata closePosParam,
        bytes memory data
    )
        external
        override
        existingStrategy(closePosParam.param.strategyId)
        existingCollateral(closePosParam.param.strategyId, closePosParam.param.collToken)
    {
        /// Information about the position from Blueberry Bank
        IBank bank = getBank();
        IBank.Position memory pos = bank.getCurrentPositionInfo();

        {
            /// Ensure the position's collateral token matches the expected one
            address lpToken = _strategies[closePosParam.param.strategyId].vault;
            if (pos.collToken != address(_wMasterPenPie)) revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            if (_wMasterPenPie.getUnderlyingToken(pos.collId) != lpToken) {
                revert Errors.INCORRECT_UNDERLYING(lpToken);
            }

            /// 1. Burn the wrapped tokens, retrieve the Pendle Market and sell to the debt token
            {
                uint256 amountPosRemove = bank.takeCollateral(closePosParam.param.amountPosRemove);
                address[] memory rewardTokens;
                (rewardTokens, ) = _wMasterPenPie.burn(pos.collId, amountPosRemove);
                /// 2. Swap each reward token for the debt token
                _sellRewards(rewardTokens, closePosParam);
            }

            {
                uint256 amountPosRemove = closePosParam.param.amountPosRemove;
                if (amountPosRemove == type(uint256).max) {
                    amountPosRemove = IERC20Upgradeable(lpToken).balanceOf(address(this));
                }
                (TokenOutput memory output, LimitOrderData memory limitOrder) = abi.decode(
                    data,
                    (TokenOutput, LimitOrderData)
                );
                // Withdraw from the Pendle Market
                IPendleRouter(_pendleRouter).removeLiquiditySingleToken(
                    msg.sender,
                    lpToken,
                    amountPosRemove,
                    output,
                    limitOrder
                );
            }
        }

        /// 2. Withdraw isolated collateral from Bank
        _doWithdraw(closePosParam.param.collToken, closePosParam.param.amountShareWithdraw);

        /// 3. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(closePosParam.param.collToken, closePosParam.param.amountToSwap, closePosParam.param.swapData);

        /// 4. Withdraw collateral from the bank and repay the borrowed amount
        {
            /// Compute repay amount if MAX_INT is supplied (max debt)
            uint256 amountRepay = closePosParam.param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(closePosParam.param.borrowToken, amountRepay);
        }

        /// 5. Validate MAX LTV
        _validateMaxLTV(closePosParam.param.strategyId);

        /// 6. Refund any remaining tokens to the owner
        _doRefund(closePosParam.param.borrowToken);
        _doRefund(closePosParam.param.collToken);
    }

    /// @inheritdoc IPendleSpell
    function getPendleRouter() external view override returns (address) {
        return address(_pendleRouter);
    }

    /// @inheritdoc IPendleSpell
    function getPenPie() external view override returns (address) {
        return _penPie;
    }

    /// @inheritdoc IPendleSpell
    function getPendle() external view override returns (address) {
        return _pendle;
    }

    /// @inheritdoc IPendleSpell
    function getWMasterPenPie() external view override returns (IWMasterPenPie) {
        return _wMasterPenPie;
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
