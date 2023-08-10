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

import "./BasicSpell.sol";
import "../interfaces/IWIchiFarm.sol";
import "../interfaces/ichi/IICHIVault.sol";
import "../interfaces/uniswap/IUniswapV3Router.sol";

/// @title IchiSpell
/// @author BlueberryProtocol
/// @notice Factory contract that defines the interaction between the Blueberry Protocol and Ichi Vaults.
contract IchiSpell is BasicSpell {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Temporary state to store Uniswap V3 pool for swapping operations.
    IUniswapV3Pool private SWAP_POOL;

    /// @dev Address of the Uniswap V3 router.
    IUniswapV3Router private uniV3Router;

    /// @dev Address of the ICHI farm wrapper.
    IWIchiFarm public wIchiFarm;
    /// @dev Address of the ICHI token.
    address public ICHI;

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

    /// @notice Initializes contract with essential external dependencies.
    /// @param bank_ Address of the bank.
    /// @param werc20_ Address of the wrapped ERC20.
    /// @param weth_ Address of WETH.
    /// @param wichiFarm_ Address of ICHI farm wrapper.
    /// @param uniV3Router_ Address of the Uniswap V3 router.
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

    /// @notice Adds a strategy to the contract.
    /// @param vault Address of the vault linked to the strategy.
    /// @param minPosSize Minimum position size in USD, normalized to 1e18.
    /// @param maxPosSize Maximum position size in USD, normalized to 1e18.
    function addStrategy(
        address vault,
        uint256 minPosSize,
        uint256 maxPosSize
    ) external onlyOwner {
        _addStrategy(vault, minPosSize, maxPosSize);
    }

    /// @notice Handles the deposit logic, including lending and borrowing
    ///         operations, and depositing borrowed tokens in the ICHI vault.
    /// @param param Parameters required for the deposit operation.
    function _deposit(OpenPosParam calldata param) internal {
        Strategy memory strategy = strategies[param.strategyId];

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        IICHIVault vault = IICHIVault(strategy.vault);
        if (
            vault.token0() != param.borrowToken &&
            vault.token1() != param.borrowToken
        ) revert Errors.INCORRECT_DEBT(param.borrowToken);
        uint256 borrowBalance = _doBorrow(
            param.borrowToken,
            param.borrowAmount
        );

        /// 3. Add liquidity - Deposit on ICHI Vault
        bool isTokenA = vault.token0() == param.borrowToken;
        _ensureApprove(param.borrowToken, address(vault), borrowBalance);

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

    /// @notice Deposits assets into an IchiVault.
    /// @param param Parameters required for the open position operation.
    /// @dev param struct found in {BasicSpell}.
    function openPosition(
        OpenPosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        /// 1-5 Deposit on ichi vault
        _deposit(param);

        /// 6. Put collateral - ICHI Vault Lp Token
        address vault = strategies[param.strategyId].vault;
        _doPutCollateral(
            vault,
            IERC20Upgradeable(vault).balanceOf(address(this))
        );
    }

    /// @notice Deposits assets into an IchiVault and then farms them in Ichi Farm.
    /// @param param Parameters required for the open position operation.
    /// @dev param struct found in {BasicSpell}.
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

        /// 1-5 Deposit on ichi vault
        _deposit(param);

        /// 6. Take out collateral and burn
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

        /// 5. Deposit on farming pool, put collateral
        uint256 lpAmount = IERC20Upgradeable(lpToken).balanceOf(address(this));
        _ensureApprove(lpToken, address(wIchiFarm), lpAmount);
        uint256 id = wIchiFarm.mint(param.farmingPoolId, lpAmount);
        bank.putCollateral(address(wIchiFarm), id, lpAmount);
    }

    /// @notice Handles the withdrawal logic, including withdrawing 
    ///         from the ICHI vault, swapping tokens, and repaying the debt.
    /// @param param Parameters required for the withdrawal operation.
    /// @dev param struct found in {BasicSpell}.
    function _withdraw(ClosePosParam calldata param) internal {
        Strategy memory strategy = strategies[param.strategyId];
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
        uint256 amountIn = IERC20Upgradeable(
            isTokenA ? vault.token1() : vault.token0()
        ).balanceOf(address(this));

        if (amountIn > 0) {
            address[] memory swapPath = new address[](2);
            swapPath[0] = isTokenA ? vault.token1() : vault.token0();
            swapPath[1] = isTokenA ? vault.token0() : vault.token1();

            IUniswapV3Router.ExactInputSingleParams
                memory params = IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: swapPath[0],
                    tokenOut: swapPath[1],
                    fee: IUniswapV3Pool(vault.pool()).fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: param.amountOutMin,
                    sqrtPriceLimitX96: 0
                });

            _ensureApprove(params.tokenIn, address(uniV3Router), amountIn);
            uniV3Router.exactInputSingle(params);
        }

        /// 5. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 6. Repay
        _doRepay(param.borrowToken, amountRepay);

        _validateMaxLTV(param.strategyId);

        /// 7. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }

    /// @notice Withdraws assets from an ICHI Vault.
    /// @param param Parameters required for the close position operation.
    /// @dev param struct found in {BasicSpell}.
    function closePosition(
        ClosePosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        /// 1. Take out collateral
        _doTakeCollateral(
            strategies[param.strategyId].vault,
            param.amountPosRemove
        );

        /// 2-8. Remove liquidity
        _withdraw(param);
    }

    /// @notice Withdraws assets from an ICHI Vault and from Ichi Farm.
    /// @param param Parameters required for the close position operation.
    /// @dev param struct found in {BasicSpell}.
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

        /// 1. Take out collateral
        bank.takeCollateral(param.amountPosRemove);
        wIchiFarm.burn(collId, param.amountPosRemove);
        _doRefundRewards(ICHI);

        /// 2-8. Remove liquidity
        _withdraw(param);

        /// 9. Refund ichi token
        _doRefund(ICHI);
    }
}
