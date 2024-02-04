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

import { IBank } from "../interfaces/IBank.sol";

import { ICvxBooster } from "../interfaces/convex/ICvxBooster.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IWConvexBooster } from "../interfaces/IWConvexBooster.sol";

contract ConvexLiquidator is BaseLiquidator {
    /// @dev The address of the CVX token
    address public _cvxToken;

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
     * @notice Initializes the Liquidator for Convex Spells
     * @param bank Address of the Blueberry Bank
     * @param treasury Address of the treasury that receives liquidator bot profits
     * @param poolAddressesProvider AAVE poolAdddressesProvider address
     * @param augustusSwapper Address for Paraswaps AugustusSwapper
     * @param stableAsset Address of the stable asset
     * @param convexSpell Address of the ConvexSpell
     * @param cvxToken Address of the CVX token
     * @param curvePool Curve/WETH Weighted Pool // TODO: FIX pool
     * @param owner The owner of the contract
     */
    function initialize(
        IBank bank,
        address treasury,
        address poolAddressesProvider,
        address augustusSwapper, // TODO: Replace with a different swap
        address stableAsset,
        address convexSpell,
        address cvxToken,
        address curvePool,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = convexSpell;
        _treasury = treasury;
        _stableAsset = stableAsset;

        _cvxToken = cvxToken;

        _transferOwnership(owner);
    }

    /// @inheritdoc BaseLiquidator
    function _unwindPosition(IBank.Position memory posInfo, address softVault, address debtToken) internal override {
        // Withdraw ERC1155 liquidiation
        (address[] memory rewardTokens, uint256[] memory rewards) = IWConvexBooster(posInfo.collToken).burn(
            posInfo.collId,
            posInfo.collateralSize
        );

        // Withdraw lp from convexBooster
        (uint256 pid, ) = IWConvexBooster(posInfo.collToken).decodeId(posInfo.collId);
        ICvxBooster convexBooster = IWConvexBooster(posInfo.collToken).getCvxBooster();

        (address lpToken, address token, , , , ) = convexBooster.poolInfo(pid);
        IERC20(token).approve(address(convexBooster), IERC20(token).balanceOf(address(this)));
        convexBooster.withdraw(pid, IERC20(token).balanceOf(address(this)));

        // Withdraw token from BalancerPool
        _exit(IERC20(lpToken));

        uint256 _stableAssetAmt = IERC20(_stableAsset).balanceOf(address(this));
        uint256 cvxAmt = IERC20(_cvxToken).balanceOf(address(this));
        uint256 uTokenAmt = IERC20Upgradeable(ISoftVault(softVault).getUnderlyingToken()).balanceOf(address(this));

        // Swap all tokens to the debtToken
        // Future optimization would be to swap only the needed tokens to debtToken and the rest Stables.
        if (_stableAsset != address(debtToken) && _stableAssetAmt != 0) {
            _swap(_stableAsset, address(debtToken), _stableAssetAmt);
        }
        if (_cvxToken != address(debtToken) && cvxAmt != 0) {
            _swap(_cvxToken, address(debtToken), cvxAmt);
        }
        if (address(ISoftVault(softVault).getUnderlyingToken()) != address(debtToken) && uTokenAmt != 0) {
            _swap(address(ISoftVault(softVault).getUnderlyingToken()), address(debtToken), uTokenAmt);
        }
    }

    // TODO: Implement Swap
    function _swap(address srcToken, address dstToken, uint256 amount) internal {
    
    }

    // TODO: Exit the curve pool
    function _exit(IERC20 lpToken) internal {

    }
}
