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

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./utils/BlueberryConst.sol" as Constants;
import "./utils/BlueberryErrors.sol" as Errors;

import { IProtocolConfig } from "./interfaces/IProtocolConfig.sol";
import { IFeeManager } from "./interfaces/IFeeManager.sol";

/**
 * @title FeeManager
 * @notice The FeeManager contract is responsible for processing and distributing fees
 *         within the BlueberryProtocol ecosystem.
 */
contract FeeManager is IFeeManager, Ownable2StepUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IProtocolConfig private _config;

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
     * @notice Initializes the FeeManager contract
     * @param config Address of the protocol config.
     * @param owner Address of the owner.
     */
    function initialize(IProtocolConfig config, address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);

        if (address(config) == address(0)) revert Errors.ZERO_ADDRESS();
        _config = config;
    }

    /// @inheritdoc IFeeManager
    function doCutDepositFee(address token, uint256 amount) external returns (uint256) {
        return _doCutFee(token, amount, _config.getDepositFee());
    }

    /// @inheritdoc IFeeManager
    function doCutWithdrawFee(address token, uint256 amount) external returns (uint256) {
        return _doCutFee(token, amount, _config.getWithdrawFee());
    }

    /// @inheritdoc IFeeManager
    function doCutRewardsFee(address token, uint256 amount) external returns (uint256) {
        return _doCutFee(token, amount, _config.getRewardFee());
    }

    /// @inheritdoc IFeeManager
    function doCutVaultWithdrawFee(address token, uint256 amount) external returns (uint256) {
        IProtocolConfig config = getConfig();
        /// Calculate the fee if it's within the fee window, otherwise return the original amount.
        if (block.timestamp < config.getWithdrawVaultFeeWindowStartTime() + config.getWithdrawVaultFeeWindow()) {
            return _doCutFee(token, amount, config.getWithdrawVaultFee());
        } else {
            return amount;
        }
    }

    /// @inheritdoc IFeeManager
    function getConfig() public view override returns (IProtocolConfig) {
        return _config;
    }

    /**
     * @dev Cut fee from given amount with given rate and send fee to the treasury
     * @param token Address of the token from which the fee will be cut.
     * @param amount Total amount from which the fee will be cut.
     * @param feeRate Fee rate as a percentage (base 10000, so 100 means 1%).
     * @return The net amount after deducting the fee.
     */
    function _doCutFee(address token, uint256 amount, uint256 feeRate) internal returns (uint256) {
        address treasury = _config.getTreasury();
        if (treasury == address(0)) revert Errors.NO_TREASURY_SET();

        /// Calculate the fee based on the provided rate.
        uint256 fee = (amount * feeRate) / Constants.DENOMINATOR;
        /// Transfer the fee to the treasury if it's non-zero.
        if (fee > 0) {
            IERC20Upgradeable(token).safeTransferFrom(msg.sender, treasury, fee);
        }
        return amount - fee; /// Return the net amount after deducting the fee.
    }
}
