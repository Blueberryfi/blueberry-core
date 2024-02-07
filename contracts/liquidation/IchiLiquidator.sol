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

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import { IBank } from "../interfaces/IBank.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IWIchiFarm } from "../interfaces/IWIchiFarm.sol";
import { IICHIVault } from "../interfaces/ichi/IICHIVault.sol";

contract IchiLiquidator is BaseLiquidator {
    /// @dev temperory state used to store uni v3 pool when swapping on uni v3
    //// @audit: Why temporary
    ISwapRouter private swapRouter;
    
    /// @dev address of ICHI token
    address public _ichiV2Token;

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
     * @param stableAsset Address of the stable asset
     * @param ichiSpell Address of the Ichi Spell Contract
     * @param swapRouter /// TODO: Align with other spells
     * @param ichiV2Token Address of the Ichi V2 token
     * @param owner The owner of the contract
     */
    function initialize(
        IBank bank,
        address treasury,
        address poolAddressesProvider,
        address stableAsset,
        address ichiSpell,
        address swapRouter,
        address ichiV2Token,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = ichiSpell;
        _treasury = treasury;
        _stableAsset = stableAsset;

        _ichiV2Token = ichiV2Token;
        swapRouter = ISwapRouter(_swapRouter);

        _transferOwnership(owner);
    }

    /// @inheritdoc BaseLiquidator
    function _unwindPosition(IBank.Position memory posInfo, address softVault, address debtToken) internal overide {
        // Withdraw ERC1155 liquidiation
        IWIchiFarm(posInfo.collToken).burn(posInfo.collId, posInfo.collateralSize);

        // Withdraw lp from ichiFarm
        (uint256 pid, ) = IWIchiFarm(posInfo.collToken).decodeId(posInfo.collId);
        address lpToken = IIchiFarm(IWIchiFarm(posInfo.collToken).ichiFarm()).lpToken(pid);
        IICHIVault(lpToken).withdraw(IERC20(lpToken).balanceOf(address(this)), address(this));

        uint256 usdcAmt = IERC20(_stableAsset).balanceOf(address(this));
        uint256 ichiAmt = IERC20(_ichiV2Token).balanceOf(address(this));
        uint256 uTokenAmt = IERC20Upgradeable(ISoftVault(bankInfo.softVault).uToken()).balanceOf(address(this));

        if (_stableAsset != address(debtToken) && usdcAmt != 0) {
            _swap(_stableAsset, address(debtToken), usdcAmt);
        }
        if (_ichiV2Token != address(debtToken) && ichiAmt != 0) {
            _swap(_ichiV2Token, address(debtToken), ichiAmt);
        }
        if (address(ISoftVault(bankInfo.softVault).uToken()) != address(debtToken) && uTokenAmt != 0) {
            _swap(address(ISoftVault(bankInfo.softVault).uToken()), address(debtToken), uTokenAmt);
        }
    }

    function _swap(address _srcToken, address _dstToken, uint256 _amount) internal {
        if (IERC20(_srcToken).balanceOf(address(this)) >= _amount) {
            IERC20(_srcToken).approve(address(swapRouter), _amount);

            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: _srcToken,
                    tokenOut: _dstToken,
                    fee: 1e4,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }
}
