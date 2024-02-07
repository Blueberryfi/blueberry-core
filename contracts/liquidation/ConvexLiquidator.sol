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
import { ICurvePool } from "../interfaces/curve/ICurvePool.sol";

contract ConvexLiquidator is BaseLiquidator {
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
     * @param convexSpell Address of the ConvexSpell
     * @param owner The owner of the contract
     */
    function initialize(
        IBank bank,
        address treasury,
        address poolAddressesProvider,
        address convexSpell,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = convexSpell;
        _treasury = treasury;

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

        // Withdraw token from Curve Pool
        _exit(IERC20(lpToken), debtToken);

        address underlyingToken = address(ISoftVault(softVault).getUnderlyingToken());
        /// Holding Reward Tokens, Underlying Tokens and Debt Tokens
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
    function _exit(IERC20 lpToken, address dstToken) internal override {
        ICurvePool curvePool = ICurvePool(address(lpToken));

        uint256 tokenIndex;
        for (uint256 i = 0; i < 4; i++) {
            try curvePool.coins(i) returns (address coin) {
                if (coin == dstToken) {
                    tokenIndex = i;
                }
            } catch {}
        }

        curvePool.remove_liquidity_one_coin(lpToken.balanceOf(address(this)), tokenIndex, 0, false, address(this));
    }
}
