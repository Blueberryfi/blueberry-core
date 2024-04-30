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
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BasicSpell } from "./BasicSpell.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IICHIVault } from "../interfaces/ichi/IICHIVault.sol";
import { IUniswapV3Router } from "../interfaces/uniswap/IUniswapV3Router.sol";
import { IWIchiFarm } from "../interfaces/IWIchiFarm.sol";
import { IIchiSpell } from "../interfaces/spell/IIchiSpell.sol";

/**
 * @title IchiSpell
 * @author BlueberryProtocol
 * @notice Factory contract that defines the interaction between the
 *         Blueberry Protocol and Ichi Vaults.
 */
contract IchiSpell is IIchiSpell, BasicSpell {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the Uniswap V3 router.
    IUniswapV3Router private _uniV3Router;
    /// @dev Address of the ICHI farm wrapper.
    IWIchiFarm private _wIchiFarm;
    /// @dev Address of the ICHI token.
    address private _ichiV2;

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
     * @param wichiFarm Address of the wrapped Ichi Farm contract.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     * @param owner Address of the owner of the contract.
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address wichiFarm,
        address uniV3Router,
        address augustusSwapper,
        address tokenTransferProxy,
        address owner
    ) external initializer {
        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy, owner);
        if (wichiFarm == address(0)) revert Errors.ZERO_ADDRESS();

        _wIchiFarm = IWIchiFarm(wichiFarm);
        _ichiV2 = address(IWIchiFarm(wichiFarm).getIchiV2());
        _wIchiFarm.setApprovalForAll(address(bank), true);

        _uniV3Router = IUniswapV3Router(uniV3Router);
    }

    /// @inheritdoc IIchiSpell
    function addStrategy(address vault, uint256 minCollSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(vault, minCollSize, maxPosSize);
    }

    /// @inheritdoc IIchiSpell
    function openPosition(
        OpenPosParam calldata param
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        /// 1-5 Deposit on ichi vault
        _deposit(param);

        /// 6. Put collateral - ICHI Vault Lp Token
        address vault = _strategies[param.strategyId].vault;
        _doPutCollateral(vault, IERC20Upgradeable(vault).balanceOf(address(this)));
    }

    /// @inheritdoc IIchiSpell
    function openPositionFarm(
        OpenPosParam calldata param
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        Strategy memory strategy = _strategies[param.strategyId];

        IWIchiFarm wIchiFarm = getWIchiFarm();

        address lpToken = wIchiFarm.getIchiFarm().lpToken(param.farmingPoolId);
        if (strategy.vault != lpToken) revert Errors.INCORRECT_LP(lpToken);

        /// 1-5 Deposit on ichi vault
        _deposit(param);

        IBank bank = getBank();
        /// 6. Take out collateral and burn
        {
            IBank.Position memory pos = bank.getCurrentPositionInfo();
            address posCollToken = pos.collToken;
            uint256 collId = pos.collId;
            uint256 collSize = pos.collateralSize;

            if (collSize > 0) {
                (uint256 decodedPid, ) = wIchiFarm.decodeId(collId);
                if (param.farmingPoolId != decodedPid) revert Errors.INCORRECT_PID(param.farmingPoolId);
                if (posCollToken != address(wIchiFarm)) revert Errors.INCORRECT_COLTOKEN(posCollToken);

                bank.takeCollateral(collSize);
                wIchiFarm.burn(collId, collSize);

                _doRefundRewards(getIchiV2());
            }
        }

        /// 5. Deposit on farming pool, put collateral
        uint256 lpAmount = IERC20Upgradeable(lpToken).balanceOf(address(this));
        IERC20(lpToken).universalApprove(address(wIchiFarm), lpAmount);
        uint256 id = wIchiFarm.mint(param.farmingPoolId, lpAmount);
        bank.putCollateral(address(wIchiFarm), id, lpAmount);
    }

    /// @inheritdoc IIchiSpell
    function closePosition(
        ClosePosParam calldata param
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        /// 1. Take out collateral
        _doTakeCollateral(_strategies[param.strategyId].vault, param.amountPosRemove);

        /// 2-8. Remove liquidity
        _withdraw(getBank(), param);
    }

    /// @inheritdoc IIchiSpell
    function closePositionFarm(
        ClosePosParam calldata param
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        IBank bank = getBank();
        address vault = _strategies[param.strategyId].vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;

        IWIchiFarm wIchiFarm = getWIchiFarm();
        address ichiV2 = getIchiV2();

        if (IWIchiFarm(posCollToken).getUnderlyingToken(collId) != vault) revert Errors.INCORRECT_UNDERLYING(vault);
        if (posCollToken != address(wIchiFarm)) revert Errors.INCORRECT_COLTOKEN(posCollToken);

        /// 1. Take out collateral
        uint256 amountPosRemove = bank.takeCollateral(param.amountPosRemove);
        wIchiFarm.burn(collId, amountPosRemove);
        _doRefundRewards(ichiV2);

        /// 2-8. Remove liquidity
        _withdraw(bank, param);

        /// 9. Refund ichi token
        _doRefund(ichiV2);
    }

    /// @inheritdoc IIchiSpell
    function getUniswapV3Router() public view override returns (IUniswapV3Router) {
        return _uniV3Router;
    }

    /// @inheritdoc IIchiSpell
    function getWIchiFarm() public view override returns (IWIchiFarm) {
        return _wIchiFarm;
    }

    /// @inheritdoc IIchiSpell
    function getIchiV2() public view returns (address) {
        return _ichiV2;
    }

    /**
     * @notice Handles the deposit logic, including lending and borrowing
     *         operations, and depositing borrowed tokens in the ICHI vault.
     * @param param Parameters required for the deposit operation.
     */
    function _deposit(OpenPosParam calldata param) internal {
        Strategy memory strategy = _strategies[param.strategyId];

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        IICHIVault vault = IICHIVault(strategy.vault);
        if (vault.token0() != param.borrowToken && vault.token1() != param.borrowToken) {
            revert Errors.INCORRECT_DEBT(param.borrowToken);
        }

        uint256 borrowBalance = _doBorrow(param.borrowToken, param.borrowAmount);

        /// 3. Add liquidity - Deposit on ICHI Vault
        bool isTokenA = vault.token0() == param.borrowToken;
        IERC20(param.borrowToken).universalApprove(address(vault), borrowBalance);

        uint ichiVaultShare;
        if (isTokenA) {
            ichiVaultShare = vault.deposit(borrowBalance, 0, address(this));
        } else {
            ichiVaultShare = vault.deposit(0, borrowBalance, address(this));
        }

        /// 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);
    }

    /**
     * @notice Handles the withdrawal logic, including withdrawing
     *         from the ICHI vault, swapping tokens, and repaying the debt.
     * @param bank Reference to the Bank contract.
     * @param param Parameters required for the close position operation.
     */
    function _withdraw(IBank bank, ClosePosParam calldata param) internal {
        Strategy memory strategy = _strategies[param.strategyId];
        IICHIVault vault = IICHIVault(strategy.vault);

        /// 1. Compute repay amount if MAX_INT is supplied (max debt)
        uint256 amountRepay = param.amountRepay;
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
        }

        /// 2. Calculate actual amount to remove
        uint256 amountPosRemove = param.amountPosRemove;
        if (amountPosRemove == type(uint256).max) {
            amountPosRemove = vault.balanceOf(address(this));
        }

        /// 3. Withdraw liquidity from ICHI vault
        vault.withdraw(amountPosRemove, address(this));

        /// 4. Swap withdrawn tokens to debt token
        bool isTokenA = vault.token0() == param.borrowToken;
        uint256 amountIn = IERC20Upgradeable(isTokenA ? vault.token1() : vault.token0()).balanceOf(address(this));

        if (amountIn > 0) {
            address[] memory swapPath = new address[](2);
            swapPath[0] = isTokenA ? vault.token1() : vault.token0();
            swapPath[1] = isTokenA ? vault.token0() : vault.token1();

            IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: swapPath[0],
                tokenOut: swapPath[1],
                fee: IUniswapV3Pool(vault.pool()).fee(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: param.amountOutMin,
                sqrtPriceLimitX96: 0
            });

            IUniswapV3Router uniV3Router = getUniswapV3Router();

            IERC20(params.tokenIn).universalApprove(address(uniV3Router), amountIn);
            uniV3Router.exactInputSingle(params);
        }

        /// 5. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 6. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(param.collToken, param.amountToSwap, param.swapData);

        /// 7. Repay
        _doRepay(param.borrowToken, amountRepay);

        _validateMaxLTV(param.strategyId);

        /// 8. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }
}
