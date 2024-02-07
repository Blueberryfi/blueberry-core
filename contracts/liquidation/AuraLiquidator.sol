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
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { BaseLiquidator } from "./BaseLiquidator.sol";

import { StablePoolUserData } from "../libraries/balancer-v2/StablePoolUserData.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IBalancerV2Pool } from "../interfaces/balancer-v2/IBalancerV2Pool.sol";
import { IBalancerVault, IAsset } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { ICvxBooster } from "../interfaces/convex/ICvxBooster.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IWAuraBooster } from "../interfaces/IWAuraBooster.sol";

contract AuraLiquidator is BaseLiquidator {
    /// @dev The address of the AURA token
    address public _auraToken;

    /// @dev balancer pool
    IBalancerV2Pool public _balancerPool;

    /// @dev balancer vault
    IBalancerVault public _balancerVault;

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
     * @param augustusSwapper Address for Paraswaps AugustusSwapper
     * @param stableAsset Address of the stable asset
     * @param auraSpell Address of the AuraSpell
     * @param auraToken Address of the AURA token
     * @param balancerPool Balancer AURA/WETH Weighted Pool
     * @param owner The owner of the contract
     */
    function initialize(
        IBank bank,
        address treasury,
        address poolAddressesProvider,
        address augustusSwapper, // TODO: Replace with a different swap
        address stableAsset,
        address auraSpell,
        address auraToken,
        address balancerPool,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = auraSpell;
        _treasury = treasury;
        _stableAsset = stableAsset;

        _auraToken = auraToken;
        _balancerPool = IBalancerV2Pool(balancerPool);
        _balancerVault = IBalancerVault(IBalancerV2Pool(balancerPool).getVault());

        _transferOwnership(owner);
    }

    /// @inheritdoc BaseLiquidator
    function _unwindPosition(IBank.Position memory posInfo, address softVault, address debtToken, uint256 debtAmount) internal override {
        // Withdraw ERC1155 liquidiation
        (address[] memory rewardTokens, uint256[] memory rewards) = IWAuraBooster(posInfo.collToken).burn(
            posInfo.collId,
            posInfo.collateralSize
        );

        // Withdraw lp from auraBooster
        (uint256 pid, ) = IWAuraBooster(posInfo.collToken).decodeId(posInfo.collId);
        ICvxBooster auraBooster = IWAuraBooster(posInfo.collToken).getAuraBooster();

        (address lpToken, address token, , , , ) = auraBooster.poolInfo(pid);
        IERC20(token).approve(address(auraBooster), IERC20(token).balanceOf(address(this)));
        auraBooster.withdraw(pid, IERC20(token).balanceOf(address(this)));

        // Withdraw token from BalancerPool
        _exit(IERC20(lpToken));

        /// Holding Reward Tokens, Underlying Tokens and Debt Tokens
        uint256 debtAmtReceived = IERC20(debtToken).balanceOf(address(this));
        uint256 auraAmt = IERC20(_auraToken).balanceOf(address(this));
        uint256 uTokenAmt = IERC20Upgradeable(ISoftVault(softVault).getUnderlyingToken()).balanceOf(address(this));

        // Liquidate all reward tokens to debtTokens
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (debtAmount >= debtAmtReceived) {
                if (rewardTokens[i] != address(debtToken) && rewards[i] != 0) {
                    debtAmount -= _swap(rewardTokens[i], address(debtToken), rewards[i]);
                }
            } else {
                break;
            }
        }

        if (debtAmount >= debtAmtReceived) {
            if (address(ISoftVault(softVault).getUnderlyingToken()) != address(debtToken) && uTokenAmt != 0) {
                _swap(address(ISoftVault(softVault).getUnderlyingToken()), address(debtToken), uTokenAmt);
            }
        }
        // Swap all tokens to the debtToken until we have enough to repay the debt
        if (_stableAsset != address(debtToken) && _stableAssetAmt != 0) {
            _swap(_stableAsset, address(debtToken), _stableAssetAmt);
        }
        if (_auraToken != address(debtToken) && auraAmt != 0) {
            _swap(_auraToken, address(debtToken), auraAmt);
        }
        if (address(ISoftVault(softVault).getUnderlyingToken()) != address(debtToken) && uTokenAmt != 0) {
            _swap(address(ISoftVault(softVault).getUnderlyingToken()), address(debtToken), uTokenAmt);
        }
    }

    function _exit(IERC20 lpToken) internal {
        bytes32 poolId = IBalancerV2Pool(address(lpToken)).getPoolId();
        (address[] memory assets, , ) = _balancerVault.getPoolTokens(poolId);

        uint256 tokenIndex;
        uint256 length = assets.length;
        uint256 offset;
        for (uint256 i = 0; i < length; i++) {
            if (assets[i] == address(lpToken)) {
                offset = 1;
            } else if (assets[i] == _stableAsset) {
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

        lpToken.approve(address(_balancerVault), lpTokenAmt);

        _balancerVault.exitPool(poolId, address(this), payable(address(this)), exitPoolRequest);
    }
}
