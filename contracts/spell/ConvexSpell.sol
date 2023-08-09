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
import "./BasicSpell.sol";
import "../interfaces/ICurveOracle.sol";
import "../interfaces/IWConvexPools.sol";
import "../interfaces/curve/ICurvePool.sol";
import "../libraries/Paraswap/PSwapLib.sol";

/// @title ConvexSpell
/// @author BlueberryProtocol
/// @notice This contract serves as the factory for defining how the Blueberry Protocol 
///         interacts with Convex pools. It handles strategies, interactions with external contracts, 
///         and facilitates operations related to liquidity provision.
contract ConvexSpell is BasicSpell {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the Wrapped Convex Pools
    IWConvexPools public wConvexPools;
    /// @dev address of CurveOracle to retrieve pool information
    ICurveOracle public crvOracle;
    /// @dev address of CVX token
    address public CVX;

    /// @dev paraswap AugustusSwapper address for token swaps
    address public augustusSwapper;
    /// @dev paraswap TokenTransferProxy address for efficient token transfers
    address public tokenTransferProxy;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
        
    /// @notice Initializes the ConvexSpell contract with required parameters.
    /// @param bank_ Address of the bank contract.
    /// @param werc20_ Address of the wrapped ERC20 contract.
    /// @param weth_ Address of the wrapped Ethereum contract.
    /// @param wConvexPools_ Address of the wrapped Convex pools contract.
    /// @param crvOracle_ Address of the Curve Oracle contract.
    /// @param augustusSwapper_ Address of the paraswap AugustusSwapper.
    /// @param tokenTransferProxy_ Address of the paraswap TokenTransferProxy.
    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address wConvexPools_,
        address crvOracle_,
        address augustusSwapper_,
        address tokenTransferProxy_
    ) external initializer {
        __BasicSpell_init(bank_, werc20_, weth_);
        if (wConvexPools_ == address(0) || crvOracle_ == address(0))
            revert Errors.ZERO_ADDRESS();

        wConvexPools = IWConvexPools(wConvexPools_);
        CVX = address(wConvexPools.CVX());
        crvOracle = ICurveOracle(crvOracle_);
        IWConvexPools(wConvexPools_).setApprovalForAll(address(bank_), true);

        augustusSwapper = augustusSwapper_;
        tokenTransferProxy = tokenTransferProxy_;
    }

    /// @notice Adds a new strategy to the spell.
    /// @param crvLp Address of the Curve LP token for the strategy.
    /// @param minPosSize Minimum position size in USD for the strategy (with 1e18 precision).
    /// @param maxPosSize Maximum position size in USD for the strategy (with 1e18 precision).
    function addStrategy(
        address crvLp,
        uint256 minPosSize,
        uint256 maxPosSize
    ) external onlyOwner {
        _addStrategy(crvLp, minPosSize, maxPosSize);
    }

    /// @notice Adds liquidity to a Curve pool with two underlying tokens and stakes in Curve gauge.
    /// @param param Struct containing all required parameters for opening a position.
    /// @param minLPMint Minimum LP tokens expected to mint for slippage control.
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minLPMint
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        Strategy memory strategy = strategies[param.strategyId];
        (address lpToken, , , , , ) = wConvexPools.getPoolInfoFromPoolId(
            param.farmingPoolId
        );
        if (strategy.vault != lpToken) revert Errors.INCORRECT_LP(lpToken);

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow specific amounts
        uint256 borrowBalance = _doBorrow(
            param.borrowToken,
            param.borrowAmount
        );

        /// 3. Add liquidity on curve, get crvLp
        (address pool, address[] memory tokens, ) = crvOracle.getPoolInfo(
            lpToken
        );
        _ensureApprove(param.borrowToken, pool, borrowBalance);
        if (tokens.length == 2) {
            uint256[2] memory suppliedAmts;
            for (uint256 i; i != 2; ++i) {
                suppliedAmts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );
            }
            ICurvePool(pool).add_liquidity(suppliedAmts, minLPMint);
        } else if (tokens.length == 3) {
            uint256[3] memory suppliedAmts;
            for (uint256 i; i != 3; ++i) {
                suppliedAmts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );
            }
            ICurvePool(pool).add_liquidity(suppliedAmts, minLPMint);
        } else {
            uint256[4] memory suppliedAmts;
            for (uint256 i; i != 4; ++i) {
                suppliedAmts[i] = IERC20Upgradeable(tokens[i]).balanceOf(
                    address(this)
                );
            }
            ICurvePool(pool).add_liquidity(suppliedAmts, minLPMint);
        }

        /// 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);
        /// 6. Take out existing collateral and burn
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collateralSize > 0) {
            (uint256 pid, ) = wConvexPools.decodeId(pos.collId);
            if (param.farmingPoolId != pid)
                revert Errors.INCORRECT_PID(param.farmingPoolId);
            if (pos.collToken != address(wConvexPools))
                revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            bank.takeCollateral(pos.collateralSize);
            (address[] memory rewardTokens, ) = wConvexPools.burn(pos.collId, pos.collateralSize);
            // distribute multiple rewards to users
            uint256 tokensLength = rewardTokens.length;
            for (uint256 i; i != tokensLength; ++i) {
                _doRefundRewards(rewardTokens[i]);
            }
        }

        /// 7. Deposit on Convex Pool, Put wrapped collateral tokens on Blueberry Bank
        uint256 lpAmount = IERC20Upgradeable(lpToken).balanceOf(address(this));
        _ensureApprove(lpToken, address(wConvexPools), lpAmount);
        uint256 id = wConvexPools.mint(param.farmingPoolId, lpAmount);
        bank.putCollateral(address(wConvexPools), id, lpAmount);
    }

    /// @notice Closes an existing liquidity position, unstakes from Curve gauge, and swaps rewards.
    /// @param param Struct containing all required parameters for closing a position.
    /// @param expectedRewards List of expected reward amounts for each token.
    /// @param swapDatas Swap data for each reward token.
    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata expectedRewards,
        bytes[] calldata swapDatas
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        address crvLp = strategies[param.strategyId].vault;
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collToken != address(wConvexPools))
            revert Errors.INCORRECT_COLTOKEN(pos.collToken);
        if (wConvexPools.getUnderlyingToken(pos.collId) != crvLp)
            revert Errors.INCORRECT_UNDERLYING(crvLp);

        uint256 amountPosRemove = param.amountPosRemove;

        /// 1. Take out collateral - Burn wrapped tokens, receive crv lp tokens and harvest CRV
        bank.takeCollateral(amountPosRemove);
        (address[] memory rewardTokens, ) = wConvexPools.burn(
            pos.collId,
            amountPosRemove
        );

        /// 2. Swap rewards tokens to debt token
        _sellRewards(rewardTokens, expectedRewards, swapDatas);

        /// 3. Remove liquidity
        _removeLiquidity(param, pos, crvLp, amountPosRemove);

        /// 4. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 5. Repay
        {
            /// Compute repay amount if MAX_INT is supplied (max debt)
            uint256 amountRepay = param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        _validateMaxLTV(param.strategyId);

        /// 6. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
        _doRefund(CVX);
    }

    /// @dev Removes liquidity from a Curve pool for a given position.
    /// @param param Contains data required to close the position.
    /// @param pos Data structure representing the current bank position.
    /// @param crvLp Address of the Curve LP token.
    /// @param amountPosRemove Amount of LP tokens to be removed from the pool. 
    ///        If set to max, will remove all available LP tokens.
    function _removeLiquidity(
        ClosePosParam memory param,
        IBank.Position memory pos,
        address crvLp,
        uint256 amountPosRemove
    ) internal {
        (address pool, address[] memory tokens, ) = crvOracle.getPoolInfo(
            crvLp
        );

        if (amountPosRemove == type(uint256).max) {
            amountPosRemove = IERC20Upgradeable(crvLp).balanceOf(address(this));
        }

        int128 tokenIndex;
        uint256 tokensLength = tokens.length;
        for (uint256 i; i != tokensLength; ++i) {
            if (tokens[i] == pos.debtToken) {
                tokenIndex = int128(uint128(i));
                break;
            }
        }

        /// Removes liquidity from the Curve pool for the specified token.
        ICurvePool(pool).remove_liquidity_one_coin(
            amountPosRemove,
            int128(tokenIndex),
            param.amountOutMin
        );
    }

    /// @dev Internal function Sells the accumulated reward tokens.
    /// @param rewardTokens An array of addresses of the reward tokens to be sold.
    /// @param expectedRewards Array containing the expected amounts of each reward token.
    /// @param swapDatas Data required for performing the swaps.
    function _sellRewards(
        address[] memory rewardTokens,
        uint[] calldata expectedRewards,
        bytes[] calldata swapDatas
    ) internal {
        uint256 tokensLength = rewardTokens.length;
        for (uint256 i; i != tokensLength; ++i) {
            address sellToken = rewardTokens[i];

            /// Apply any potential fees on the reward.
            _doCutRewardsFee(sellToken);

            uint expectedReward = expectedRewards[i];
            /// If the expected reward is zero, skip to the next token.
            if (expectedReward == 0) continue;
            /// Swap the reward token for another desired token. If the swap fails, revert with an error.
            if (
                !PSwapLib.swap(
                    augustusSwapper,
                    tokenTransferProxy,
                    sellToken,
                    expectedReward,
                    swapDatas[i]
                )
            ) revert Errors.SWAP_FAILED(sellToken);
            /// Refund any leftover (dust) amounts after the swap to the contract owner
            _doRefund(sellToken);
        }
    }
}
