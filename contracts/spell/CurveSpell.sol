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
import "../interfaces/IWCurveGauge.sol";
import "../interfaces/curve/ICurvePool.sol";

contract CurveSpell is BasicSpell {
    using SafeCast for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev address of ICHI farm wrapper
    IWCurveGauge public wCurveGauge;
    /// @dev address of curve registry
    ICurveRegistry public registry;
    /// @dev address of ICHI token
    address public CRV;
    /// @dev Mapping from LP token address -> underlying token addresses
    mapping(address => address[]) public ulTokens;
    /// @dev Mapping from LP token address to -> pool address
    mapping(address => address) public poolOf;

    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address wCurveGauge_
    ) external initializer {
        __BasicSpell_init(bank_, werc20_, weth_);

        wCurveGauge = IWCurveGauge(wCurveGauge_);
        CRV = address(wCurveGauge.CRV());
        registry = wCurveGauge.registry();
        IWCurveGauge(wCurveGauge_).setApprovalForAll(address(bank_), true);
    }

    /**
     * @notice Add strategy to the spell, and set pool info
     * @param vault Address of curve lp token for given strategy
     * @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
     */
    function addStrategy(
        address vault,
        uint256 maxPosSize
    ) public override onlyOwner {
        // Update pool info
        address pool = poolOf[vault];
        if (pool != address(0)) revert Errors.CRV_LP_ALREADY_REGISTERED(vault);

        pool = registry.get_pool_from_lp_token(vault);
        if (pool == address(0)) revert Errors.NO_LP_REGISTERED(vault);

        poolOf[vault] = pool;
        (uint256 n, ) = registry.get_n_coins(pool);
        address[8] memory tokens = registry.get_coins(pool);
        for (uint256 i = 0; i < n; i++) {
            ulTokens[vault].push(tokens[i]);
        }

        super.addStrategy(vault, maxPosSize);
    }

    /**
     * @notice Add liquidity to Curve pool with 2 underlying tokens, with staking to Curve gauge
     * @param minLPMint Desired LP token amount (slippage control)
     * @param gid Curve gauge id for the pool
     */
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minLPMint,
        uint256 gid
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        address lp = strategies[param.strategyId].vault;
        address pool = poolOf[lp];
        address[] memory tokens = ulTokens[lp];
        if (
            wCurveGauge.getUnderlyingTokenFromIds(param.farmingPoolId, gid) !=
            lp
        ) revert Errors.INCORRECT_UNDERLYING(lp);

        // 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        // 2. Borrow specific amounts
        uint256 borrowBalance = _doBorrow(
            param.borrowToken,
            param.borrowAmount
        );

        // 3. Add liquidity on curve
        _ensureApprove(param.borrowToken, pool, borrowBalance);
        if (tokens.length == 2) {
            uint256[2] memory suppliedAmts;
            for (uint256 i = 0; i < 2; i++) {
                suppliedAmts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );
            }
            ICurvePool(pool).add_liquidity(suppliedAmts, minLPMint);
        } else if (tokens.length == 3) {
            uint256[3] memory suppliedAmts;
            for (uint256 i = 0; i < 3; i++) {
                suppliedAmts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );
            }
            ICurvePool(pool).add_liquidity(suppliedAmts, minLPMint);
        } else if (tokens.length == 4) {
            uint256[4] memory suppliedAmts;
            for (uint256 i = 0; i < 4; i++) {
                suppliedAmts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );
            }
            ICurvePool(pool).add_liquidity(suppliedAmts, minLPMint);
        }

        // 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        // 5. Validate Max Pos Size
        _validateMaxPosSize(param.strategyId);

        // 6. Take out collateral and burn
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collateralSize > 0) {
            (uint256 decodedPid, uint256 decodedGid, ) = wCurveGauge.decodeId(
                pos.collId
            );
            if (param.farmingPoolId != decodedPid || gid != decodedGid)
                revert Errors.INCORRECT_PID(param.farmingPoolId);
            if (pos.collToken != address(wCurveGauge))
                revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            bank.takeCollateral(pos.collateralSize);
            wCurveGauge.burn(pos.collId, pos.collateralSize);
            _doRefundRewards(CRV);
        }

        // 7. Deposit on Curve Gauge, Put wrapped collateral on Blueberry Bank
        uint256 lpAmount = IERC20Upgradeable(lp).balanceOf(address(this));
        _ensureApprove(lp, address(wCurveGauge), lpAmount);
        uint256 id = wCurveGauge.mint(param.farmingPoolId, gid, lpAmount);
        bank.putCollateral(address(wCurveGauge), id, lpAmount);
    }

    function closePositionFarm(
        ClosePosParam calldata param
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        address crvLp = strategies[param.strategyId].vault;
        ICurvePool crvPool = ICurvePool(poolOf[crvLp]);

        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;
        if (IWCurveGauge(posCollToken).getUnderlyingToken(collId) != crvLp)
            revert Errors.INCORRECT_UNDERLYING(crvLp);
        if (posCollToken != address(wCurveGauge))
            revert Errors.INCORRECT_COLTOKEN(posCollToken);

        // 1. Take out collateral - Burn wrapped tokens, receive crv lp tokens and harvest CRV
        bank.takeCollateral(param.amountPosRemove);
        wCurveGauge.burn(collId, param.amountPosRemove);
        _doRefundRewards(CRV);

        // 2. Compute repay amount if MAX_INT is supplied (max debt)
        uint256 amountRepay = param.amountRepay;
        if (amountRepay == type(uint256).max) {
            amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
        }

        // 3. Calculate actual amount to remove
        uint256 amountPosRemove = param.amountPosRemove;
        if (amountPosRemove == type(uint256).max) {
            amountPosRemove = IERC20Upgradeable(crvLp).balanceOf(address(this));
        }

        // 4. Remove liquidity
        address[] memory tokens = ulTokens[crvLp];
        int128 tokenIndex;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == pos.debtToken) {
                tokenIndex = int128(uint128(i));
                break;
            }
        }
        crvPool.remove_liquidity_one_coin(
            amountPosRemove,
            int128(tokenIndex),
            amountRepay
        );

        // 5. Withdraw isolated collateral from Bank
        _doWithdraw(posCollToken, param.amountShareWithdraw);

        // 6. Repay
        _doRepay(param.borrowToken, amountRepay);

        _validateMaxLTV(param.strategyId);

        // 7. Refund
        _doRefund(param.borrowToken);
        _doRefund(posCollToken);
        _doRefund(CRV);
    }
}
