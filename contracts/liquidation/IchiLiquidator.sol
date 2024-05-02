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
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IIchiSpell } from "../interfaces/spell/IIchiSpell.sol";
import { IIchiFarm } from "../interfaces/ichi/IIchiFarm.sol";
import { IWIchiFarm } from "../interfaces/IWIchiFarm.sol";
import { IICHIVault } from "../interfaces/ichi/IICHIVault.sol";
import { IWERC20 } from "../interfaces/IWERC20.sol";

/**
 * @title IchiLiquidator
 * @author Blueberry Protocol
 * @notice This contract is the liquidator for all Ichi Spells
 */
contract IchiLiquidator is BaseLiquidator {
    /// @dev address of ICHI token
    address private _ichiV2Token;

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
     * @param ichiSpell Address of the Ichi Spell Contract
     * @param swapRouter Address of the Uniswap V3 SwapRouter
     * @param ichiV2Token Address of the Ichi V2 token
     * @param owner The owner of the contract
     */
    function initialize(
        IBank bank,
        address treasury,
        address emergencyFund,
        address poolAddressesProvider,
        address ichiSpell,
        address swapRouter,
        address ichiV2Token,
        address weth,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = ichiSpell;
        _treasury = treasury;

        _ichiV2Token = ichiV2Token;
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
        address lpToken = _unwrapLpToken(posInfo);

        IICHIVault(lpToken).withdraw(IERC20(lpToken).balanceOf(address(this)), address(this));

        address underlyingToken = address(ISoftVault(softVault).getUnderlyingToken());
        uint256 ichiAmt = IERC20(_ichiV2Token).balanceOf(address(this));
        uint256 uTokenAmt = IERC20Upgradeable(underlyingToken).balanceOf(address(this));
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(address(this));

        if (debtAmount > debtTokenBalance) {
            if (_ichiV2Token != address(debtToken) && ichiAmt != 0) {
                debtTokenBalance += _swap(_ichiV2Token, address(debtToken), ichiAmt);
            }
        }

        if (debtAmount > debtTokenBalance) {
            if (underlyingToken != address(debtToken) && uTokenAmt != 0) {
                debtTokenBalance += _swap(underlyingToken, address(debtToken), uTokenAmt);
            }
        }
    }

    /**
     * @notice Unwraps the LP token and sends it to the caller
     * @dev This function can handle both Farming and regular positions
     * @param posInfo The position info for the liquidation
     * @return The address of the Ichi LP token
     */
    function _unwrapLpToken(IBank.Position memory posInfo) internal returns (address) {
        // Withdraw ERC1155 liquidiation
        if (posInfo.collToken == address(IIchiSpell(_spell).getWIchiFarm())) {
            uint256 balance = IERC1155(posInfo.collToken).balanceOf(address(this), posInfo.collId);
            IWIchiFarm(posInfo.collToken).burn(posInfo.collId, balance);
            (uint256 pid, ) = IWIchiFarm(posInfo.collToken).decodeId(posInfo.collId);

            return IIchiFarm(IWIchiFarm(posInfo.collToken).getIchiFarm()).lpToken(pid);
        } else {
            uint256 balance = IERC1155(posInfo.collToken).balanceOf(address(this), posInfo.collId);
            IWERC20(posInfo.collToken).burn(address(uint160(posInfo.collId)), balance);

            return IWERC20(posInfo.collToken).getUnderlyingToken(posInfo.collId);
        }
    }
}
