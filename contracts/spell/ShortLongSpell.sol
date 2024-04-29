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

import { PSwapLib } from "../libraries/Paraswap/PSwapLib.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BasicSpell } from "./BasicSpell.sol";

import { IBank } from "../interfaces/IBank.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IWERC20 } from "../interfaces/IWERC20.sol";
import { IShortLongSpell } from "../interfaces/spell/IShortLongSpell.sol";

/**
 * @title Short/Long Spell
 * @author BlueberryProtocol
 * @notice Short/Long Spell is the factory contract that
 *          defines how Blueberry Protocol interacts for leveraging
 *          an asset either long or short
 */
contract ShortLongSpell is IShortLongSpell, BasicSpell {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

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
     * @notice Initializes the contract
     * @param bank The bank interface
     * @param werc20 Wrapped ERC20 interface
     * @param weth Wrapped Ether address
     * @param augustusSwapper Augustus Swapper address
     * @param tokenTransferProxy Token Transfer Proxy address
     * @param owner Address of the owner
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address augustusSwapper,
        address tokenTransferProxy,
        address owner
    ) external initializer {
        if (augustusSwapper == address(0)) revert Errors.ZERO_ADDRESS();
        if (tokenTransferProxy == address(0)) revert Errors.ZERO_ADDRESS();

        _augustusSwapper = augustusSwapper;
        _tokenTransferProxy = tokenTransferProxy;

        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy, owner);
    }

    /// @inheritdoc IShortLongSpell
    function openPosition(
        OpenPosParam calldata param,
        bytes calldata swapData
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        Strategy memory strategy = _strategies[param.strategyId];
        if (address(ISoftVault(strategy.vault).getUnderlyingToken()) == param.borrowToken) {
            revert Errors.INCORRECT_LP(param.borrowToken);
        }

        /// 1-3 Swap to strategy underlying token, deposit to softvault
        _deposit(param, swapData);

        /// 4. Put collateral - strategy token
        address vault = _strategies[param.strategyId].vault;

        _doPutCollateral(vault, IERC20Upgradeable(ISoftVault(vault)).balanceOf(address(this)));
    }

    /// @inheritdoc IShortLongSpell
    function closePosition(
        ClosePosParam calldata param,
        bytes calldata swapData
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        IBank bank = getBank();
        IWERC20 werc20 = getWrappedERC20();
        Strategy memory strategy = _strategies[param.strategyId];

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

    /// @inheritdoc IShortLongSpell
    function addStrategy(address swapToken, uint256 minCollSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(swapToken, minCollSize, maxPosSize);
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
    function _deposit(OpenPosParam calldata param, bytes calldata swapData) internal {
        Strategy memory strategy = _strategies[param.strategyId];

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        _doBorrow(param.borrowToken, param.borrowAmount);

        /// 3. Swap borrowed token to strategy token
        IERC20Upgradeable swapToken = ISoftVault(strategy.vault).getUnderlyingToken();
        uint256 dstTokenAmt = swapToken.balanceOf(address(this));

        address borrowToken = param.borrowToken;
        if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, borrowToken, param.borrowAmount, swapData)) {
            revert Errors.SWAP_FAILED(borrowToken);
        }

        dstTokenAmt = swapToken.balanceOf(address(this)) - dstTokenAmt;
        if (dstTokenAmt == 0) revert Errors.SWAP_FAILED(borrowToken);

        /// 4. Deposit to SoftVault directly
        IERC20(address(swapToken)).universalApprove(address(strategy.vault), dstTokenAmt);
        ISoftVault(strategy.vault).deposit(dstTokenAmt);

        /// 5. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 6. Validate Max Pos Size
        _validatePosSize(param.strategyId);
    }

    /**
     * @notice Internal utility function to handle the withdrawal of assets from SoftVault.
     * @param param Parameters required for the withdrawal, described in the `ClosePosParam` struct.
     * @param swapData Specific data needed for the ParaSwap swap.
     */
    function _withdraw(ClosePosParam calldata param, bytes calldata swapData) internal {
        Strategy memory strategy = _strategies[param.strategyId];
        ISoftVault vault = ISoftVault(strategy.vault);
        IBank bank = getBank();

        uint256 positionId = bank.POSITION_ID();

        /// 1. Calculate actual amount to remove
        uint256 amountPosRemove = param.amountPosRemove;
        if (amountPosRemove == type(uint256).max) {
            amountPosRemove = vault.balanceOf(address(this));
        }

        /// 2. Withdraw from softvault
        uint256 swapAmount = vault.withdraw(amountPosRemove);

        /// 3. Swap strategy token to isolated collateral token
        {
            IERC20Upgradeable uToken = ISoftVault(strategy.vault).getUnderlyingToken();
            uint256 balanceBefore = uToken.balanceOf(address(this));

            if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, address(uToken), swapAmount, swapData))
                revert Errors.SWAP_FAILED(address(uToken));

            if (uToken.balanceOf(address(this)) > balanceBefore - swapAmount) {
                revert Errors.INCORRECT_LP(address(uToken));
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
}
