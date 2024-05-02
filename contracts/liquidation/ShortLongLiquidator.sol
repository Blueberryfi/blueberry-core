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

import { BaseLiquidator } from "./BaseLiquidator.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IWERC20 } from "../interfaces/IWERC20.sol";

/**
 * @title ShortLongLiquidator
 * @author Blueberry Protocol
 * @notice This contract is the liquidator for all ShortLong Spells
 */
contract ShortLongLiquidator is BaseLiquidator {
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
     * @param shortLongSpell Address of the ShortLong Spell Contract
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
        address shortLongSpell,
        address balancerVault,
        address swapRouter,
        address weth,
        address owner
    ) external initializer {
        __Ownable2Step_init();

        _initializeAavePoolInfo(poolAddressesProvider);

        _bank = bank;
        _spell = shortLongSpell;
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
        address /*softVault*/,
        address debtToken,
        uint256 /*debtAmount*/
    ) internal override {
        // Withdraw ERC1155 liquidiation
        uint256 balance = IERC1155(posInfo.collToken).balanceOf(address(this), posInfo.collId);
        IWERC20(posInfo.collToken).burn(address(uint160(posInfo.collId)), balance);
        _swap(posInfo.underlyingToken, debtToken, IERC20(posInfo.underlyingToken).balanceOf(address(this)));
    }
}
