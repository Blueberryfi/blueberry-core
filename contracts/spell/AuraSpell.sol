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
import { IBalancerV2Pool } from "../interfaces/balancer-v2/IBalancerV2Pool.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { IWAuraBooster } from "../interfaces/IWAuraBooster.sol";
import { IAuraSpell } from "../interfaces/spell/IAuraSpell.sol";

/**
 * @title AuraSpell
 * @author BlueberryProtocol
 * @notice AuraSpell is the factory contract that
 *         defines how Blueberry Protocol interacts with Aura pools
 */
contract AuraSpell is IAuraSpell, BasicSpell {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to Wrapped Aura Pools
    IWAuraBooster private _wAuraBooster;
    /// @dev Address of AURA token
    address private _auraToken;

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
     * @param wAuraBooster Address of the wrapped Aura Pools contract.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     * @param owner Address of the owner of the contract.
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address wAuraBooster,
        address augustusSwapper,
        address tokenTransferProxy,
        address owner
    ) external initializer {
        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy, owner);
        if (wAuraBooster == address(0)) revert Errors.ZERO_ADDRESS();

        _wAuraBooster = IWAuraBooster(wAuraBooster);
        _auraToken = address(IWAuraBooster(wAuraBooster).getAuraToken());
        IWAuraBooster(wAuraBooster).setApprovalForAll(address(bank), true);
    }

    /// @inheritdoc IAuraSpell
    function addStrategy(address bpt, uint256 minCollSize, uint256 maxPosSize) external onlyOwner {
        _addStrategy(bpt, minCollSize, maxPosSize);
    }

    /// @inheritdoc IAuraSpell
    function openPositionFarm(
        OpenPosParam calldata param,
        uint256 minimumBPT
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        IBank bank = getBank();
        /// Extract strategy details for the given strategy ID.
        Strategy memory strategy = _strategies[param.strategyId];
        /// Fetch pool information based on provided farming pool ID.
        (address lpToken, , , , , ) = _wAuraBooster.getPoolInfoFromPoolId(param.farmingPoolId);
        if (strategy.vault != lpToken) revert Errors.INCORRECT_LP(lpToken);

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        address borrowToken = param.borrowToken;
        uint256 borrowAmount = param.borrowAmount;

        /// 2. Borrow funds based on specified amount
        _doBorrow(borrowToken, borrowAmount);

        /// 3. Add liquidity to the Balancer pool and receive BPT in return.
        {
            uint256 _minimumBPT = minimumBPT;
            IBalancerVault vault = _wAuraBooster.getVault();

            (address[] memory tokens, , ) = _wAuraBooster.getPoolTokens(lpToken);
            (uint256[] memory maxAmountsIn, uint256[] memory amountsIn) = _getJoinPoolParamsAndApprove(
                address(vault),
                tokens,
                lpToken,
                borrowToken,
                borrowAmount
            );

            vault.joinPool(
                _wAuraBooster.getBPTPoolId(lpToken),
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

        /// 4. Ensure that the resulting LTV does not exceed maximum allowed value.
        _validateMaxLTV(param.strategyId);

        /// 5. Ensure position size is within permissible limits.
        _validatePosSize(param.strategyId);

        /// 6. Withdraw existing collaterals and burn the associated tokens.
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        if (pos.collateralSize > 0) {
            (uint256 pid, ) = _wAuraBooster.decodeId(pos.collId);

            if (param.farmingPoolId != pid) revert Errors.INCORRECT_PID(param.farmingPoolId);
            if (pos.collToken != address(_wAuraBooster)) revert Errors.INCORRECT_COLTOKEN(pos.collToken);

            bank.takeCollateral(pos.collateralSize);

            (address[] memory rewardTokens, ) = _wAuraBooster.burn(pos.collId, pos.collateralSize);

            // Distribute the multiple rewards to users.
            uint256 rewardTokensLength = rewardTokens.length;
            for (uint256 i; i < rewardTokensLength; ++i) {
                _doRefundRewards(rewardTokens[i]);
            }
        }

        /// 7. Deposit the tokens in the Aura pool and place the wrapped collateral tokens in the Blueberry Bank.
        uint256 lpAmount = IERC20Upgradeable(lpToken).balanceOf(address(this));
        IERC20(lpToken).universalApprove(address(_wAuraBooster), lpAmount);

        uint256 id = _wAuraBooster.mint(param.farmingPoolId, lpAmount);

        bank.putCollateral(address(_wAuraBooster), id, lpAmount);
    }

    /// @inheritdoc IAuraSpell
    function closePositionFarm(
        ClosePosParam calldata param,
        uint256[] calldata expectedRewards,
        bytes[] calldata swapDatas
    ) external existingStrategy(param.strategyId) existingCollateral(param.strategyId, param.collToken) {
        /// Information about the position from Blueberry Bank
        IBank bank = getBank();
        IBank.Position memory pos = bank.getCurrentPositionInfo();

        /// Ensure the position's collateral token matches the expected one
        {
            address lpToken = _strategies[param.strategyId].vault;
            if (pos.collToken != address(_wAuraBooster)) revert Errors.INCORRECT_COLTOKEN(pos.collToken);
            if (_wAuraBooster.getUnderlyingToken(pos.collId) != lpToken) {
                revert Errors.INCORRECT_UNDERLYING(lpToken);
            }

            /// 1. Burn the wrapped tokens, retrieve the BPT tokens, and claim the AURA rewards
            {
                uint256 amountPosRemove = bank.takeCollateral(param.amountPosRemove);
                address[] memory rewardTokens;
                (rewardTokens, ) = _wAuraBooster.burn(pos.collId, amountPosRemove);
                /// 2. Swap each reward token for the debt token
                _sellRewards(rewardTokens, expectedRewards, swapDatas);
            }

            {
                /// 3. Determine the exact amount of position to remove
                uint256 amountPosRemove = param.amountPosRemove;
                if (amountPosRemove == type(uint256).max) {
                    amountPosRemove = IERC20Upgradeable(lpToken).balanceOf(address(this));
                }
                /// 4. Parameters for removing liquidity
                (
                    uint256[] memory minAmountsOut,
                    address[] memory tokens,
                    uint256 borrowTokenIndex
                ) = _getExitPoolParams(param, lpToken);

                _wAuraBooster.getVault().exitPool(
                    IBalancerV2Pool(lpToken).getPoolId(),
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

    /// @inheritdoc IAuraSpell
    function getWAuraBooster() external view returns (IWAuraBooster) {
        return _wAuraBooster;
    }

    /// @inheritdoc IAuraSpell
    function getAuraToken() external view returns (address) {
        return _auraToken;
    }

    /**
     * @notice Calculate the parameters required for joining a Balancer pool.
     * @param vault Address of the Balancer vault
     * @param tokens List of tokens in the Balancer pool
     * @param lpToken The LP token for the Balancer pool
     * @return maxAmountsIn Maximum amounts to deposit for each token
     * @return amountsIn Amounts of each token to deposit
     */
    function _getJoinPoolParamsAndApprove(
        address vault,
        address[] memory tokens,
        address lpToken,
        address borrowToken,
        uint256 borrowAmount
    ) internal returns (uint256[] memory, uint256[] memory) {
        uint256 i;
        uint256 j;
        uint256 length = tokens.length;
        uint256[] memory maxAmountsIn = new uint256[](length);
        uint256[] memory amountsIn = new uint256[](length);
        bool isLPIncluded;

        for (i; i < length; ++i) {
            if (tokens[i] != lpToken) {
                if (tokens[i] == borrowToken) {
                    amountsIn[j] = borrowAmount;
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

    /**
     * @notice Calculate the parameters required for exiting a Balancer pool.
     * @param param Close position param
     * @param lpToken The LP token for the Balancer pool
     * @return minAmountsOut Minimum amounts to receive for each token upon exiting
     * @return tokens List of tokens in the Balancer pool
     * @return exitTokenIndex Index of the borrowToken in the tokens list
     */
    function _getExitPoolParams(
        ClosePosParam calldata param,
        address lpToken
    ) internal view returns (uint256[] memory, address[] memory, uint256) {
        address borrowToken = param.borrowToken;
        uint256 amountOutMin = param.amountOutMin;
        (address[] memory tokens, , ) = _wAuraBooster.getPoolTokens(lpToken);

        uint256 length = tokens.length;
        uint256[] memory minAmountsOut = new uint256[](length);
        uint256 exitTokenIndex;

        for (uint256 i; i < length; ++i) {
            if (tokens[i] == borrowToken) {
                minAmountsOut[i] = amountOutMin;
                break;
            }

            if (tokens[i] != lpToken) ++exitTokenIndex;
        }

        return (minAmountsOut, tokens, exitTokenIndex);
    }

    /**
     * @notice Internal function to sell reward tokens.
     * @param rewardTokens List of reward tokens to sell.
     * @param expectedRewards Expected reward amounts for each reward token.
     * @param swapDatas Data required for swapping reward tokens to the debt token.
     */
    function _sellRewards(
        address[] memory rewardTokens,
        uint256[] calldata expectedRewards,
        bytes[] calldata swapDatas
    ) internal {
        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ++i) {
            address sellToken = rewardTokens[i];

            _doCutRewardsFee(sellToken);
            if (
                expectedRewards[i] != 0 &&
                !PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, sellToken, expectedRewards[i], swapDatas[i])
            ) revert Errors.SWAP_FAILED(sellToken);

            /// Refund rest (dust) amount to owner
            _doRefund(sellToken);
        }
    }
}
