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

import "./BasicSpell.sol";

import "../interfaces/ISoftVault.sol";
import "../interfaces/IWERC20.sol";
import "../libraries/Paraswap/PSwapLib.sol";

/// @title Short/Long Spell
/// @author BlueberryProtocol
/// @notice Short/Long Spell is the factory contract that
///         defines how Blueberry Protocol interacts for leveraging
///         an asset either long or short
contract ShortLongSpell is BasicSpell {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev paraswap AugustusSwapper address
    address public augustusSwapper;

    /// @dev paraswap TokenTransferProxy address
    address public tokenTransferProxy;

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

    /// @notice Initializes the contract
    /// @param bank_ The bank interface
    /// @param werc20_ Wrapped ERC20 interface
    /// @param weth_ Wrapped Ether address
    /// @param augustusSwapper_ Augustus Swapper address
    /// @param tokenTransferProxy_ Token Transfer Proxy address
    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address augustusSwapper_,
        address tokenTransferProxy_
    ) external initializer {
        if (augustusSwapper_ == address(0)) revert Errors.ZERO_ADDRESS();
        if (tokenTransferProxy_ == address(0)) revert Errors.ZERO_ADDRESS();

        augustusSwapper = augustusSwapper_;
        tokenTransferProxy = tokenTransferProxy_;

        __BasicSpell_init(bank_, werc20_, weth_);
    }

    /// @notice Internal function to swap token using paraswap assets
    /// @dev Deposit isolated underlying to Blueberry Money Market,
    ///      Borrow tokens from Blueberry Money Market,
    ///      Swap borrowed token to another token
    ///      Then deposit swapped token to softvault,
    /// @param param Parameters for opening position
    /// @dev params found in OpenPosParam struct in {BasicSpell}
    /// @param swapData Data for paraswap swap
    /// @dev swapData found in bytes struct in {PSwapLib}
    function _deposit(
        OpenPosParam calldata param,
        bytes calldata swapData
    ) internal {
        Strategy memory strategy = strategies[param.strategyId];

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        _doBorrow(param.borrowToken, param.borrowAmount);

        /// 3. Swap borrowed token to strategy token
        IERC20Upgradeable swapToken = ISoftVault(strategy.vault).uToken();
        uint256 dstTokenAmt = swapToken.balanceOf(address(this));

        address borrowToken = param.borrowToken;
        if (
            !PSwapLib.swap(
                augustusSwapper,
                tokenTransferProxy,
                borrowToken,
                param.borrowAmount,
                swapData
            )
        ) revert Errors.SWAP_FAILED(borrowToken);
        dstTokenAmt = swapToken.balanceOf(address(this)) - dstTokenAmt;
        if (dstTokenAmt == 0) revert Errors.SWAP_FAILED(borrowToken);

        /// 4. Deposit to SoftVault directly
        _ensureApprove(
            address(swapToken),
            address(strategy.vault),
            dstTokenAmt
        );
        ISoftVault(strategy.vault).deposit(dstTokenAmt);

        /// 5. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 6. Validate Max Pos Size
        _validatePosSize(param.strategyId);
    }

    /// @notice Opens a position using provided parameters and swap data.
    /// @dev This function first deposits an isolated underlying asset to Blueberry Money Market,
    /// then borrows tokens from it. The borrowed tokens are swapped for another token using
    /// ParaSwap and the resulting tokens are deposited into the softvault.
    /// 
    /// Pre-conditions:
    /// - Strategy for `param.strategyId` must exist.
    /// - Collateral for `param.strategyId` and `param.collToken` must exist.
    /// 
    /// @param param Parameters required to open the position, described in the `OpenPosParam` struct from {BasicSpell}.
    /// @param swapData Specific data needed for the ParaSwap swap, structured in the `bytes` format from {PSwapLib}.
    function openPosition(
        OpenPosParam calldata param,
        bytes calldata swapData
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        Strategy memory strategy = strategies[param.strategyId];
        if (address(ISoftVault(strategy.vault).uToken()) == param.borrowToken)
            revert Errors.INCORRECT_LP(param.borrowToken);

        /// 1-3 Swap to strategy underlying token, deposit to softvault
        _deposit(param, swapData);

        /// 4. Put collateral - strategy token
        address vault = strategies[param.strategyId].vault;

        _doPutCollateral(
            vault,
            IERC20Upgradeable(ISoftVault(vault)).balanceOf(address(this))
        );
    }

    /// @notice Internal utility function to handle the withdrawal of assets from SoftVault.
    /// @param param Parameters required for the withdrawal, described in the `ClosePosParam` struct.
    /// @param swapData Specific data needed for the ParaSwap swap.
    function _withdraw(
        ClosePosParam calldata param,
        bytes calldata swapData
    ) internal {
        Strategy memory strategy = strategies[param.strategyId];
        ISoftVault vault = ISoftVault(strategy.vault);
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
            IERC20Upgradeable uToken = ISoftVault(strategy.vault).uToken();
            uint256 balanceBefore = uToken.balanceOf(address(this));

            if (
                !PSwapLib.swap(
                    augustusSwapper,
                    tokenTransferProxy,
                    address(uToken),
                    swapAmount,
                    swapData
                )
            ) revert Errors.SWAP_FAILED(address(uToken));

            if (uToken.balanceOf(address(this)) > balanceBefore - swapAmount) {
                revert Errors.INCORRECT_LP(address(uToken));
            }
        }

        /// 4. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 5. Repay
        {
            uint256 amountRepay = param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(positionId);
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        _validateMaxLTV(param.strategyId);

        /// 6. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }

    /// @notice Externally callable function to close a position using provided parameters and swap data.
    /// @dev This function is a higher-level action that internally calls `_withdraw` to manage the closing 
    /// of a position. It ensures the given strategy and collateral exist, and then carries out the required 
    /// operations to close the position.
    /// 
    /// Pre-conditions:
    /// - Strategy for `param.strategyId` must exist.
    /// - Collateral for `param.strategyId` and `param.collToken` must exist.
    /// 
    /// @param param Parameters required to close the position, described in the `ClosePosParam` struct.
    /// @param swapData Specific data needed for the ParaSwap swap.
    function closePosition(
        ClosePosParam calldata param,
        bytes calldata swapData
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        Strategy memory strategy = strategies[param.strategyId];

        address vault = strategies[param.strategyId].vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;
        if (IWERC20(posCollToken).getUnderlyingToken(collId) != vault)
            revert Errors.INCORRECT_UNDERLYING(vault);
        if (posCollToken != address(werc20))
            revert Errors.INCORRECT_COLTOKEN(posCollToken);

        /// 1. Take out collateral
        uint burnAmount = bank.takeCollateral(param.amountPosRemove);

        werc20.burn(address(ISoftVault(strategy.vault)), burnAmount);

        /// 2-7. Remove liquidity
        _withdraw(param, swapData);
    }

    /// @notice Add strategy to the spell
    /// @param swapToken Address of token for given strategy
    /// @param minPosSize USD price of minimum position size for given strategy, based 1e18
    /// @param maxPosSize USD price of maximum position size for given strategy, based 1e18
    function addStrategy(
        address swapToken,
        uint256 minPosSize,
        uint256 maxPosSize
    ) external onlyOwner {
        _addStrategy(swapToken, minPosSize, maxPosSize);
    }
}
