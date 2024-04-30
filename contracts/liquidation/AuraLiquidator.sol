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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { BaseLiquidator } from "./BaseLiquidator.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { StablePoolUserData } from "../libraries/balancer-v2/StablePoolUserData.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IBalancerV2Pool } from "../interfaces/balancer-v2/IBalancerV2Pool.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { ICvxBooster } from "../interfaces/convex/ICvxBooster.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IWAuraBooster } from "../interfaces/IWAuraBooster.sol";

/**
 * @title AuraLiquidator
 * @author Blueberry Protocol
 * @notice This contract is the liquidator for all Aura Spells
 */
contract AuraLiquidator is BaseLiquidator {
    using SafeERC20 for IERC20;

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
     * @notice Initializes the Liquidator for Aura Spells
     * @param bank Address of the Blueberry Bank
     * @param treasury Address of the treasury that receives liquidator bot profits
     * @param poolAddressesProvider AAVE poolAdddressesProvider address
     * @param auraSpell Address of the AuraSpell
     * @param balancerVault Address of the Balancer Vault
     * @param swapRouter Address of the Uniswap V3 SwapRouter
     * @param weth Address of the WETH token
     * @param owner The owner of the contract
     */
    function initialize(
        IBank bank,
        address treasury,
        address emergencyFund,
        address poolAddressesProvider,
        address auraSpell,
        address balancerVault,
        address swapRouter,
        address weth,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = auraSpell;
        _treasury = treasury;

        _balancerVault = balancerVault;
        _swapRouter = swapRouter;
        _weth = weth;

        _emergencyFund = emergencyFund;
        _transferOwnership(owner);
    }

    /// @inheritdoc BaseLiquidator
    function _unwindPosition(
        IBank.Position memory posInfo,
        address softVault,
        address debtToken,
        uint256 debtAmount
    ) internal override {
        // Withdraw ERC1155 liquidiation
        (address[] memory rewardTokens, uint256[] memory rewards) = IWAuraBooster(posInfo.collToken).burn(
            posInfo.collId,
            posInfo.collateralSize
        );

        // Withdraw lp from auraBooster
        (uint256 pid, ) = IWAuraBooster(posInfo.collToken).decodeId(posInfo.collId);
        ICvxBooster auraBooster = IWAuraBooster(posInfo.collToken).getAuraBooster();

        (address lpToken, address token, , , , ) = auraBooster.poolInfo(pid);
        IERC20(token).forceApprove(address(auraBooster), IERC20(token).balanceOf(address(this)));
        auraBooster.withdraw(pid, IERC20(token).balanceOf(address(this)));

        // Withdraw token from BalancerPool
        _exit(IERC20(lpToken), debtToken);

        /// Holding Reward Tokens, Underlying Tokens and Debt Tokens
        address underlyingToken = address(ISoftVault(softVault).getUnderlyingToken());
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));
        uint256 uTokenAmt = IERC20Upgradeable(underlyingToken).balanceOf(address(this));

        // Liquidate all reward tokens to debtTokens until we have enough to repay the debt
        uint256 rewardLength = rewardTokens.length;
        for (uint256 i = 0; i < rewardLength; ++i) {
            if (debtAmount > debtTokenBalance) {
                if (rewardTokens[i] != address(debtToken) && rewards[i] != 0) {
                    debtTokenBalance += _swap(rewardTokens[i], address(debtToken), rewards[i]);
                }
            } else {
                break;
            }
        }

        // liquidate all remaining tokens if we still don't have enough to repay the debt
        if (debtAmount > debtTokenBalance) {
            if (underlyingToken != address(debtToken) && uTokenAmt != 0) {
                debtTokenBalance += _swap(underlyingToken, address(debtToken), uTokenAmt);
            }
        }
    }

    /// @inheritdoc BaseLiquidator
    function _exit(IERC20 lpToken, address debtToken) internal override {
        bytes32 poolId = IBalancerV2Pool(address(lpToken)).getPoolId();
        (address[] memory assets, , ) = IBalancerVault(_balancerVault).getPoolTokens(poolId);

        uint256 tokenIndex;
        uint256 length = assets.length;
        uint256 offset;
        for (uint256 i = 0; i < length; i++) {
            if (assets[i] == address(lpToken)) {
                offset = 1;
            } else if (assets[i] == debtToken) {
                tokenIndex = i - offset;
                break;
            }
        }

        uint256[] memory minAmountsOut = new uint256[](length);

        uint256 lpTokenAmt = lpToken.balanceOf(address(this));

        IBalancerVault.ExitPoolRequest memory exitPoolRequest;
        exitPoolRequest.assets = assets;
        exitPoolRequest.minAmountsOut = minAmountsOut;
        exitPoolRequest.userData = abi.encode(
            StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
            lpTokenAmt,
            tokenIndex
        );

        lpToken.forceApprove(address(_balancerVault), lpTokenAmt);

        IBalancerVault(_balancerVault).exitPool(poolId, address(this), payable(address(this)), exitPoolRequest);
    }
}
