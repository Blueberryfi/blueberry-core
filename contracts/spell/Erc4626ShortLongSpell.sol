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

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { PSwapLib } from "../libraries/Paraswap/PSwapLib.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BasicSpell } from "./BasicSpell.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IWERC20 } from "../interfaces/IWERC20.sol";
import { IWERC4626 } from "../interfaces/IWERC4626.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IErc4626ShortLongSpell, IShortLongSpell } from "../interfaces/spell/IErc4626ShortLongSpell.sol";
import "hardhat/console.sol";

/**
 * @title ERC4626 Short/Long Spell
 * @author BlueberryProtocol
 * @notice ERC4626 Short/Long Spell is the factory contract that
 *          defines how Blueberry Protocol interacts for leveraging
 *          an asset either long or short for ERC4626 vaults
 */
contract Erc4626ShortLongSpell is IErc4626ShortLongSpell, BasicSpell {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Mapping of an Erc4626 vault to its associated wrapper and asset
    mapping(address => VaultInfo) public vaultToVaultInfo;

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
        address werc20, // Irrelevent for this contract as multiple ERC4626 vaults can be used
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
        VaultInfo memory vaultInfo = vaultToVaultInfo[address(strategy.vault)];

        // swap token cannot be borrow token
        if (param.borrowToken == vaultInfo.asset) {
            revert Errors.INCORRECT_LP(param.borrowToken);
        }

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        _doBorrow(param.borrowToken, param.borrowAmount);

        /// 3. Swap to strategy underlying token
        uint256 amount = _swapToAsset(param.borrowToken, vaultInfo.asset, param.borrowAmount, swapData);

        /// 4. Mint wrapper token
        _depositAndMint(vaultInfo, amount);

        /// 5. Validate MAX LTV and POS Size
        _validateMaxLTV(param.strategyId);
        _validatePosSize(param.strategyId);
    }

    /// @inheritdoc IShortLongSpell
    function closePosition(
        ClosePosParam calldata param,
        bytes calldata swapData
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        /// 1. Get all necessary information for the position
        IBank bank = getBank();
        Strategy memory strategy = _strategies[param.strategyId];
        VaultInfo memory vaultInfo = vaultToVaultInfo[address(strategy.vault)];

        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;

        address lpToken = strategy.vault;
        if (posCollToken != vaultInfo.wrapper) revert Errors.INCORRECT_COLTOKEN(posCollToken);
        if (address(IWERC4626(posCollToken).getUnderlyingToken(0)) != lpToken) {
            revert Errors.INCORRECT_UNDERLYING(vaultInfo.wrapper);
        }
        console.log("pos.collId: %s", pos.collId);
        /// 2. Exit position in ERC4626 vault
        uint256 swapAmount = _exitPosition(vaultInfo.wrapper, pos.collId, param.amountPosRemove);
        console.log("swapAmount: %s", swapAmount);
        /// 3. Swap strategy token to debt token
        _swapToDebt(vaultInfo.asset, swapAmount, swapData);
        console.log("Swap to Debt Done");
        /// 4. Withdraw Isolated Collateral from the bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);
        console.log("Withdraw Collateral Done");
        /// 5. Swap isolated collateral to debt token
        _swapCollToDebt(param.collToken, param.amountToSwap, swapData);
        console.log("Swap collateral to debt");
        console.log("pxETH balance: %s", IERC20Upgradeable(vaultInfo.asset).balanceOf(address(this)));
        console.log("borrowToken balance: %s", IERC20Upgradeable(param.borrowToken).balanceOf(address(this)));
        /// 6. Repay all debt
        _repayDebt(bank, param.borrowToken, param.amountRepay);
        console.log("Repay Debt Done");
        /// 7. Validate MAX LTV
        _validateMaxLTV(param.strategyId);
        console.log("Validate Max LTV Done");
        /// 8. Send tokens to the user
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
        console.log("Refund Done");
    }

    /**
     * @notice Adds a strategy to the spell
     * @param wrapper Address of the wrapper contract associated with the vault
     * @param minCollSize The minimum size of isolated collateral in USD scaled by 1e18
     * @param maxPosSize The maximum size of the position in USD scaled by 1e18
     */
    function addStrategy(address wrapper, uint256 minCollSize, uint256 maxPosSize) external onlyOwner {
        IERC4626 erc4626Vault = IERC4626(IWERC4626(wrapper).getUnderlyingToken(0));
        address asset = erc4626Vault.asset();

        vaultToVaultInfo[address(erc4626Vault)] = VaultInfo({ wrapper: wrapper, asset: asset });
        _addStrategy(address(erc4626Vault), minCollSize, maxPosSize);
        IWERC20(wrapper).setApprovalForAll(address(_bank), true);
    }

    /**
     * @notice Remove the wrapper from the bank and unwind the position to receive the base asset of the vault
     * @param wrapper Address of the wrapper
     * @param collId The ID of the collateral
     * @param amount Amount of the collateral to remove
     * @return Amount of base asset received
     */
    function _exitPosition(address wrapper, uint256 collId, uint256 amount) internal returns (uint256) {
        uint256 burnAmount = _bank.takeCollateral(amount);
        return IWERC4626(wrapper).burn(collId, burnAmount);
    }

    /**
     * @notice Swaps strategy token to debt token
     * @param asset Asset being swapped from
     * @param swapAmount Amount of asset being swapped
     * @param swapData Bytes data for the swap function to execute
     */
    function _swapToDebt(address asset, uint256 swapAmount, bytes calldata swapData) internal {
        IERC20Upgradeable uToken = IERC20Upgradeable(asset);
        uint256 balanceBefore = uToken.balanceOf(address(this));

        if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, address(uToken), swapAmount, swapData))
            revert Errors.SWAP_FAILED(address(uToken));

        if (uToken.balanceOf(address(this)) > balanceBefore - swapAmount) {
            revert Errors.INCORRECT_LP(address(uToken));
        }
    }

    /**
     * @notice Repays the debt of the position
     * @param bank The Blueberry Bank
     * @param borrowToken Address of the token being borrowed
     * @param amountRepay Amount of the debt needing to be repaid
     */
    function _repayDebt(IBank bank, address borrowToken, uint256 amountRepay) internal {
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
        }
        console.log("amountRepay: %s", amountRepay);
        _doRepay(borrowToken, amountRepay);
    }

    /**
     * @notice Swap borrowed token from the money market into the asset we are depositing into the ERC4626 vault
     * @param borrowToken Address of the token being borrowed from the money market
     * @param asset Address of the asset being deposited into the money market (Swapping for this token)
     * @param borrowAmount The amount of the borrow token to swap
     * @param swapData Bytes data for the swap function to execute
     */
    function _swapToAsset(
        address borrowToken,
        address asset,
        uint256 borrowAmount,
        bytes calldata swapData
    ) internal returns (uint256) {
        /// Swap borrowed token to strategy token
        IERC20Upgradeable swapToken = IERC20Upgradeable(asset);
        uint256 swapTokenAmt = swapToken.balanceOf(address(this));

        if (!PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, borrowToken, borrowAmount, swapData)) {
            revert Errors.SWAP_FAILED(borrowToken);
        }

        swapTokenAmt = swapToken.balanceOf(address(this)) - swapTokenAmt;
        if (swapTokenAmt == 0) revert Errors.SWAP_FAILED(borrowToken);

        return swapTokenAmt;
    }

    /**
     * @notice Deposit the asset into the ERC4626 and wrap the position
     * @param vaultInfo Information about the ERC4626 Vault
     * @param amount The amount of asset to deposit
     */
    function _depositAndMint(VaultInfo memory vaultInfo, uint256 amount) internal {
        IWERC4626 wrapper = IWERC4626(vaultInfo.wrapper);
        IERC20(vaultInfo.asset).universalApprove(address(wrapper), amount);
        uint256 id = wrapper.mint(amount);
        _bank.putCollateral(address(wrapper), id, amount);
    }
}
