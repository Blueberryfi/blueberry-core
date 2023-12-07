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

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./BasicSpell.sol";
import "../interfaces/IWAuraPools.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../libraries/Paraswap/PSwapLib.sol";
import "../libraries/UniversalERC20.sol";

/// @title AuraSpell
/// @author BlueberryProtocol
/// @notice AuraSpell is the factory contract that
///         defines how Blueberry Protocol interacts with Aura pools
contract AuraSpell is BasicSpell {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to Wrapped Aura Pools
    IWAuraPools public wAuraPools;
    /// @dev Address of AURA token
    address public AURA;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with required parameters.
    /// @param bank_ Reference to the Bank contract.
    /// @param werc20_ Reference to the WERC20 contract.
    /// @param weth_ Address of the wrapped Ether token.
    /// @param wAuraPools_ Address of the wrapped Aura Pools contract.
    /// @param augustusSwapper_ Address of the paraswap AugustusSwapper.
    /// @param tokenTransferProxy_ Address of the paraswap TokenTransferProxy.
    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address wAuraPools_,
        address augustusSwapper_,
        address tokenTransferProxy_
    ) external initializer {
        __BasicSpell_init(
            bank_,
            werc20_,
            weth_,
            augustusSwapper_,
            tokenTransferProxy_
        );
        if (wAuraPools_ == address(0)) revert Errors.ZERO_ADDRESS();

        wAuraPools = IWAuraPools(wAuraPools_);
        AURA = address(wAuraPools.AURA());
        IWAuraPools(wAuraPools_).setApprovalForAll(address(bank_), true);
    }

    /// @notice Allows the owner to add a new strategy.
    /// @param bpt Address of the Balancer Pool Token.
    /// @param minPosSize, USD price of minimum position size for given strategy, based 1e18
    /// @param maxPosSize, USD price of maximum position size for given strategy, based 1e18
    function addStrategy(
        address bpt,
        uint256 minPosSize,
        uint256 maxPosSize
    ) external onlyOwner {
        _addStrategy(bpt, minPosSize, maxPosSize);
    }

    /// @notice Adds liquidity to a Balancer pool and stakes the resultant tokens in Aura.
    /// @param param Configuration for opening a position.
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minimumBPT
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        /// Extract strategy details for the given strategy ID.
        Strategy memory strategy = strategies[param.strategyId];
        /// Fetch pool information based on provided farming pool ID.
        (address lpToken, , , , , ) = wAuraPools.getPoolInfoFromPoolId(
            param.farmingPoolId
        );
        if (strategy.vault != lpToken) revert Errors.INCORRECT_LP(lpToken);

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);
        console.log("lended");
        /// 2. Borrow funds based on specified amount
        _doBorrow(param.borrowToken, param.borrowAmount);
        console.log("borrowed");
        /// 3. Add liquidity to the Balancer pool and receive BPT in return.
        {
            uint256 _minimumBPT = minimumBPT;
            IBalancerVault vault = wAuraPools.getVault(lpToken);

            (address[] memory tokens, , ) = wAuraPools.getPoolTokens(lpToken);
            (
                uint256[] memory maxAmountsIn,
                uint256[] memory amountsIn
            ) = _getJoinPoolParamsAndApprove(address(vault), tokens, lpToken);

            vault.joinPool(
                wAuraPools.getBPTPoolId(lpToken),
                address(this),
                address(this),
                IBalancerVault.JoinPoolRequest({
                    assets: tokens,
                    maxAmountsIn: maxAmountsIn,
                    userData: abi.encode(1, amountsIn, _minimumBPT),
                    fromInternalBalance: false
                })
            );
        }
        console.log("BPT: %s", IERC20Upgradeable(lpToken).balanceOf(address(this)));
        /// 4. Ensure that the resulting LTV does not exceed maximum allowed value.
        _validateMaxLTV(param.strategyId);
        console.log("validateMaxLTV");
        /// 5. Ensure position size is within permissible limits.
        _validatePosSize(param.strategyId);
        console.log("validatePosSize");
        /// 6. Withdraw existing collaterals and burn the associated tokens.
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collateralSize > 0) {
            (uint256 pid, ) = wAuraPools.decodeId(pos.collId);

            if (param.farmingPoolId != pid)
                revert Errors.INCORRECT_PID(param.farmingPoolId);
            if (pos.collToken != address(wAuraPools))
                revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            
            bank.takeCollateral(pos.collateralSize);
            
            (address[] memory rewardTokens, , address stashAura) = wAuraPools.burn(
                pos.collId,
                pos.collateralSize
            );
            
            // Distribute the multiple rewards to users.
            uint256 rewardTokensLength = rewardTokens.length;
            for (uint256 i; i != rewardTokensLength; ++i) {
                _doRefundRewards(
                    rewardTokens[i] == stashAura ? AURA : rewardTokens[i]
                );
            }
        }

        /// 7. Deposit the tokens in the Aura pool and place the wrapped collateral tokens in the Blueberry Bank.
        uint256 lpAmount = IERC20Upgradeable(lpToken).balanceOf(address(this));
        IERC20(lpToken).universalApprove(address(wAuraPools), lpAmount);
        console.log("approved");
        uint256 id = wAuraPools.mint(param.farmingPoolId, lpAmount);
        console.log("minted");
        bank.putCollateral(address(wAuraPools), id, lpAmount);
        console.log("putCollateral");
    }

    /// @notice Closes a position from Balancer pool and exits the Aura farming.
    /// @param param Parameters for closing the position
    /// @param expectedRewards Expected reward amounts for each reward token
    /// @param swapDatas Data required for swapping reward tokens to the debt token
    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata expectedRewards,
        bytes[] calldata swapDatas
    )
        external
        existingStrategy(param.strategyId)
        existingCollateral(param.strategyId, param.collToken)
    {
        /// Information about the position from Blueberry Bank
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address[] memory rewardTokens;
        //address stashAura;
        /// Ensure the position's collateral token matches the expected one
        {
            address lpToken = strategies[param.strategyId].vault;
            if (pos.collToken != address(wAuraPools))
                revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            if (wAuraPools.getUnderlyingToken(pos.collId) != lpToken)
                revert Errors.INCORRECT_UNDERLYING(lpToken);

            bank.takeCollateral(param.amountPosRemove);
            
            /// 1. Burn the wrapped tokens, retrieve the BPT tokens, and claim the AURA rewards            
            {
                address stashToken;
                (rewardTokens, , stashToken) = wAuraPools.burn(
                    pos.collId,
                    param.amountPosRemove
                );

                /// 2. Swap each reward token for the debt token
                _sellRewards(rewardTokens, expectedRewards, swapDatas, stashToken);
                console.log("sold rewards");
            }

            {
                /// 3. Determine the exact amount of position to remove
                uint256 amountPosRemove = param.amountPosRemove;
                if (amountPosRemove == type(uint256).max) {
                    amountPosRemove = IERC20Upgradeable(lpToken).balanceOf(
                        address(this)
                    );
                }
                /// 4. Parameters for removing liquidity
                (
                    uint256[] memory minAmountsOut,
                    address[] memory tokens,
                    uint256 borrowTokenIndex
                ) = _getExitPoolParams(param, lpToken);

                wAuraPools.getVault(lpToken).exitPool(
                    IBalancerPool(lpToken).getPoolId(),
                    address(this),
                    address(this),
                    IBalancerVault.ExitPoolRequest(
                        tokens,
                        minAmountsOut,
                        abi.encode(0, amountPosRemove, borrowTokenIndex),
                        false
                    )
                );
            }
        }

        /// 5. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 6. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(param.collToken, param.amountToSwap, param.swapData);

        /// 7. Withdraw collateral from the bank and repay the borrowed amount
        {
            /// Compute repay amount if MAX_INT is supplied (max debt)
            uint256 amountRepay = param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        /// Ensure that the Loan to Value (LTV) ratio remains within accepted boundaries
        _validateMaxLTV(param.strategyId);

        /// 8. Refund any remaining tokens to the owner
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }

    /// @dev Calculate the parameters required for joining a Balancer pool.
    /// @param vault Address of the Balancer vault
    /// @param tokens List of tokens in the Balancer pool
    /// @param lpToken The LP token for the Balancer pool
    /// @return maxAmountsIn Maximum amounts to deposit for each token
    /// @return amountsIn Amounts of each token to deposit
    function _getJoinPoolParamsAndApprove(
        address vault,
        address[] memory tokens,
        address lpToken
    ) internal returns (uint256[] memory, uint256[] memory) {
        uint256 i;
        uint256 j;
        uint256 length = tokens.length;
        uint256[] memory maxAmountsIn = new uint256[](length);
        uint256[] memory amountsIn = new uint256[](length);
        bool isLPIncluded;

        for (i; i != length; ++i) {
            if (tokens[i] != lpToken) {
                amountsIn[j] = IERC20(tokens[i]).balanceOf(address(this));
                if (amountsIn[j] > 0) {
                    IERC20(tokens[i]).universalApprove(vault, amountsIn[j]);
                    maxAmountsIn[i] = amountsIn[j];
                }
                ++j;
            } else isLPIncluded = true;
        }

        if (isLPIncluded) {
            assembly {
                mstore(amountsIn, sub(mload(amountsIn), 1))
            }
        }

        return (maxAmountsIn, amountsIn);
    }

    /// @dev Calculate the parameters required for exiting a Balancer pool.
    /// @param param Close position param
    /// @param lpToken The LP token for the Balancer pool
    /// @return minAmountsOut Minimum amounts to receive for each token upon exiting
    /// @return tokens List of tokens in the Balancer pool
    /// @return exitTokenIndex Index of the borrowToken in the tokens list
    function _getExitPoolParams(
        ClosePosParam calldata param,
        address lpToken
    ) internal view returns (uint256[] memory, address[] memory, uint256) {
        address borrowToken = param.borrowToken;
        uint256 amountOutMin = param.amountOutMin;
        (address[] memory tokens, , ) = wAuraPools.getPoolTokens(lpToken);

        uint256 length = tokens.length;
        uint256[] memory minAmountsOut = new uint256[](length);
        uint256 exitTokenIndex;

        for (uint256 i; i != length; ++i) {
            if (tokens[i] == borrowToken) {
                minAmountsOut[i] = amountOutMin;
                break;
            }

            if (tokens[i] != lpToken) ++exitTokenIndex;

        }

        return (minAmountsOut, tokens, exitTokenIndex);
    }

    function _sellRewards(
        address[] memory rewardTokens,
        uint256[] calldata expectedRewards,
        bytes[] calldata swapDatas,
        address stashAura
    ) internal {
        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i != rewardTokensLength; ++i) {
            address sellToken = rewardTokens[i];
            if (sellToken == stashAura) sellToken = AURA;

            _doCutRewardsFee(sellToken);
            if (
                expectedRewards[i] != 0 &&
                !PSwapLib.swap(
                    augustusSwapper,
                    tokenTransferProxy,
                    sellToken,
                    expectedRewards[i],
                    swapDatas[i]
                )
            ) revert Errors.SWAP_FAILED(sellToken);

            /// Refund rest (dust) amount to owner
            _doRefund(sellToken);
        }
    }
}
