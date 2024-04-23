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
import "hardhat/console.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { IHardVault } from "../interfaces/IHardVault.sol";
import { VaultAddress } from "../libraries/Address.sol";
//import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IBank, IShortLongSpell, ShortLongSpell, PSwapLib, UniversalERC20, IERC20, IWERC20 } from "./ShortLongSpell.sol";


import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";




/**
 * @title Short/Long Spell
 * @author BlueberryProtocol
 * @notice Short/Long Spell is the factory contract that
 *          defines how Blueberry Protocol interacts for leveraging
 *          an asset either long or short
 */
contract ShortLongSpell_ERC4626 is ShortLongSpell {
//    using SafeCast for uint256;
//    using SafeCast for int256;
//    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;
    using VaultAddress for address;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IShortLongSpell
    function openPosition(
        OpenPosParam calldata param,
        bytes calldata swapData
    ) external override existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        Strategy memory strategy = _strategies[param.strategyId];
        uint256 tokenId = 888464623530194257602517549495353035908660900838;
        if (IHardVault(strategy.vault).getUnderlyingToken(tokenId) == param.borrowToken) {
            revert Errors.INCORRECT_LP(param.borrowToken);
        }

        /// 1-3 Swap to strategy underlying token, deposit to hard vault
        _deposit(param, swapData);

        /// 4. Put collateral - strategy token
//        _doPutCollateral(strategy.vault, IERC20Upgradeable(strategy.vault).balanceOf(address(this)));//todo
        _doPutCollateral(strategy.vault, strategy.vault.balanceOf(address(this)));//todo
    }

    /// @inheritdoc IShortLongSpell
    function closePosition(
        ClosePosParam calldata param,
        bytes calldata swapData
    ) external override existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        IBank bank = getBank();
        IWERC20 werc20 = getWrappedERC20();
        Strategy memory strategy = _strategies[param.strategyId];
//
        address vault = strategy.vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;

        if (IWERC20(posCollToken).getUnderlyingToken(collId) != vault) revert Errors.INCORRECT_UNDERLYING(vault);
        if (posCollToken != address(werc20)) revert Errors.INCORRECT_COLTOKEN(posCollToken);

        /// 1. Take out collateral
        uint256 burnAmount = bank.takeCollateral(param.amountPosRemove);

        werc20.burn(vault, burnAmount);

        /// 2-7. Remove liquidity
        _withdraw(param, swapData);
    }


    /**
     * @notice Internal function to swap token using paraswap assets
     * @dev Deposit isolated underlying to Blueberry Money Market,
     *      Borrow tokens from Blueberry Money Market,
     *      Swap borrowed token to another token
     *      Then deposit swapped token to softvault,
     * @param param Parameters for opening position
     * @dev params found in OpenPosParam struct in {BasicSpell}
     * @param swapData Data for paraswap swap
     * @dev swapData found in bytes struct in {PSwapLib}
     */
    function _deposit(OpenPosParam calldata param, bytes calldata swapData) internal override {
        Strategy memory strategy = _strategies[param.strategyId];
        uint256 tokenId = 888464623530194257602517549495353035908660900838;

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);
        console.log("step 1 done");

        /// 2. Borrow specific amounts
        _doBorrow(param.borrowToken, param.borrowAmount);
        console.log("step 2 done", "borrow amount: ", IERC20(param.borrowToken).balanceOf(address(this)), param.borrowAmount);

        /// 3. Swap borrowed token to strategy token
        IERC4626Upgradeable underlyingToken = IERC4626Upgradeable(IHardVault(strategy.vault).getUnderlyingToken(tokenId));
        console.log("underlying token", address(underlyingToken));
        IERC20Upgradeable swapToken = IERC20Upgradeable(underlyingToken.asset());
        uint256 dstTokenAmt = swapToken.balanceOf(address(this));
        console.log("step 3 done", "swap token is: ", address(swapToken));

        address borrowToken = param.borrowToken;
        if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, borrowToken, param.borrowAmount, swapData)) {
            revert Errors.SWAP_FAILED(borrowToken);
        }

        dstTokenAmt = swapToken.balanceOf(address(this)) - dstTokenAmt;
        if (dstTokenAmt == 0) revert Errors.ZERO_AMOUNT();
        console.log("pxETH bal: ", dstTokenAmt); //40766072905497535

        swapToken.approve(address(underlyingToken), dstTokenAmt);
//        swapToken.transferFrom(address(this), address(underlyingToken), dstTokenAmt);
        underlyingToken.deposit(dstTokenAmt, address(this));
        uint256 underlyingTokenAmount = underlyingToken.balanceOf(address(this));
        console.log("apxETH bal: ", underlyingTokenAmount);

        /// 4. Deposit to HardVault directly
        console.log("spell addr: ", address(this));
        underlyingToken.approve(address(strategy.vault), underlyingTokenAmount);
//        IERC20(address(swapToken)).universalApprove(address(strategy.vault), underlyingTokenAmount);
        IHardVault(strategy.vault).deposit(address(underlyingToken), underlyingTokenAmount);
        console.log("hardvault deposit done");
        /// 5. Validate MAX LTV
        _validateMaxLTV(param.strategyId);
        console.log("_validateMaxLTV done");

        /// 6. Validate Max Pos Size
        _validatePosSize(param.strategyId);
        console.log("_validatePosSize done");
    }

    /**
     * @notice Internal utility function to handle the withdrawal of assets from SoftVault.
     * @param param Parameters required for the withdrawal, described in the `ClosePosParam` struct.
     * @param swapData Specific data needed for the ParaSwap swap.
     */
    function _withdraw(ClosePosParam calldata param, bytes calldata swapData) internal override {
        uint256 tokenId = 888464623530194257602517549495353035908660900838;

        IBank bank = getBank();
//        Strategy memory strategy = _strategies[param.strategyId];
        IHardVault vault = IHardVault(_strategies[param.strategyId].vault);//IHardVault(strategy.vault);
        IERC4626Upgradeable underlyingToken = IERC4626Upgradeable(vault.getUnderlyingToken(tokenId));


        uint256 positionId = bank.POSITION_ID();

        /// 1. Calculate actual amount to remove
        uint256 amountPosRemove = param.amountPosRemove;
        if (amountPosRemove == type(uint256).max) {
            amountPosRemove =  vault.balanceOf(address(this), tokenId);//vault.balanceOf(address(this));
        }

        /// 2. Withdraw from softvault
        uint256 underlyingAmount = vault.withdraw(address(underlyingToken), amountPosRemove);
        //so here, the spell holds apxETH, so we withdraw pxETH from apxETH, and the we swap pxETH for CRV and
        //then return the CRV we borrowed and then collect our initial DAI
        uint256 swapAmount = underlyingToken.withdraw(underlyingAmount, address(this), address(this));

        /// 3. Swap strategy token to isolated collateral token
        {
//            IERC20Upgradeable uToken = IHardVault(strategy.vault).getUnderlyingToken();
            uint256 balanceBefore = underlyingToken.balanceOf(address(this));

            if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, underlyingToken.asset(), swapAmount, swapData))
                revert Errors.SWAP_FAILED(address(underlyingToken.asset()));

            if (IERC20(underlyingToken.asset()).balanceOf(address(this)) > balanceBefore - swapAmount) {
                revert Errors.INCORRECT_LP(address(underlyingToken.asset()));
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
                amountRepay = bank.currentPositionDebt(positionId);
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        _validateMaxLTV(param.strategyId);

        /// 7. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }


    /**
     * @notice Internal function to validate if the current position size is within the strategy's bounds.
     * @param strategyId Strategy ID to validate against.
     */
    function _validatePosSize(uint256 strategyId) internal override view {
        IBank bank = getBank();
        Strategy memory strategy = _strategies[strategyId];
        IBank.Position memory pos = bank.getCurrentPositionInfo();

        uint256 tokenId = 888464623530194257602517549495353035908660900838;
        IERC4626Upgradeable underlyingToken = IERC4626Upgradeable(IHardVault(strategy.vault).getUnderlyingToken(tokenId));

        /// Get previous position size
        uint256 prevPosSize;
        if (pos.collToken != address(0)) {
            prevPosSize = bank.getOracle().getWrappedTokenValue(pos.collToken, pos.collId, pos.collateralSize);
        }

        /// Get newly added position size
        uint256 addedPosSize;
        IERC20 lpToken = IERC20(strategy.vault); //todo: Note that there is an assumption here that all vaults are SoftVaults, which is incorrect
        //todo: will the design be cleaner if a vault is bundled with it's oracle?
        uint256 lpBalance = strategy.vault.balanceOf(address(this));
        uint256 lpPrice = bank.getOracle().getPrice(address(underlyingToken));

        addedPosSize = (lpPrice * lpBalance) / 10 ** underlyingToken.decimals();

        // Check if position size is within bounds
        if (prevPosSize + addedPosSize > strategy.maxPositionSize) {
            revert Errors.EXCEED_MAX_POS_SIZE(strategyId);
        }
        if (prevPosSize + addedPosSize < strategy.minPositionSize) {
            revert Errors.EXCEED_MIN_POS_SIZE(strategyId);
        }
    }

    /**
     * @notice Internal function Deposit collateral tokens into the bank.
     * @dev Ensures approval of tokens to the werc20 contract, mints them,
     *      and then deposits them as collateral in the bank.
     *      Only deposits if the specified amount is greater than zero.
     * @param token Address of the collateral token to be deposited.
     * @param amount Amount of collateral tokens to deposit.
     */
    function _doPutCollateral(address token, uint256 amount) internal override {
        console.log("start doPutCollateral");
//        uint256 tokenId = 888464623530194257602517549495353035908660900838;
//        IERC4626Upgradeable underlyingToken = IERC4626Upgradeable(IHardVault(token).getUnderlyingToken(tokenId));

        if (amount > 0) {
            IWERC20 werc20 = getWrappedERC20();
            IERC1155Upgradeable(token).setApprovalForAll(address(werc20), true);
            werc20.mint(token, amount);
            _bank.putCollateral(address(werc20), uint256(uint160(token)), amount);
        }
        console.log("end _doPutCollateral");
    }

}
