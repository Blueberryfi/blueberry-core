// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IProtocolConfig.sol";
import "./utils/BlueBerryConst.sol" as Constants;
import "./utils/BlueBerryErrors.sol" as Errors;

/// @title FeeManager
/// @author BlueberryProtocol
/// @notice The FeeManager contract is responsible for processing and distributing fees
///         within the BlueberryProtocol ecosystem.
contract FeeManager is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IProtocolConfig public config;

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

    /// @dev Initializes the FeeManager contract
    /// @param config_ Address of the protocol config.
    function initialize(IProtocolConfig config_) external initializer {
        __Ownable_init();

        if (address(config_) == address(0)) revert Errors.ZERO_ADDRESS();
        config = config_;
    }

    /// @notice Calculates and transfers deposit fee when lending
    ///         isolated underlying assets to Blueberry Money Market.
    /// @param token Address of the underlying token.
    /// @param amount Amount of tokens being deposited.
    /// @return The net amount after deducting the fee.
    function doCutDepositFee(
        address token,
        uint256 amount
    ) external returns (uint256) {
        return _doCutFee(token, amount, config.depositFee());
    }

    /// @notice Calculates and transfers withdrawal fee when redeeming 
    ///         isolated underlying tokens from Blueberry Money Market.
    /// @param token Address of the underlying token.
    /// @param amount Amount of tokens being withdrawn.
    /// @return The net amount after deducting the fee.
    function doCutWithdrawFee(
        address token,
        uint256 amount
    ) external returns (uint256) {
        return _doCutFee(token, amount, config.withdrawFee());
    }

    /// @notice Calculates and transfers the performance fee from the rewards generated from the leveraged position.
    /// @param token Address of the reward token.
    /// @param amount Amount of rewards.
    /// @return The net rewards after deducting the fee.
    function doCutRewardsFee(
        address token,
        uint256 amount
    ) external returns (uint256) {
        return _doCutFee(token, amount, config.rewardFee());
    }

    /// @notice Cut vault withdraw fee when perform withdraw from Blueberry Money Market within the given window
    /// @param token Address of the underlying token.
    /// @param amount Amount of tokens being withdrawn.
    /// @return The net amount after deducting the fee if within the fee window, else returns the original amount.
    function doCutVaultWithdrawFee(
        address token,
        uint256 amount
    ) external returns (uint256) {
        /// Calculate the fee if it's within the fee window, otherwise return the original amount.
        if (
            block.timestamp <
            config.withdrawVaultFeeWindowStartTime() +
                config.withdrawVaultFeeWindow()
        ) {
            return _doCutFee(token, amount, config.withdrawVaultFee());
        } else {
            return amount;
        }
    }

    /// @dev Cut fee from given amount with given rate and send fee to the treasury
    /// @param token Address of the token from which the fee will be cut.
    /// @param amount Total amount from which the fee will be cut.
    /// @param feeRate Fee rate as a percentage (base 10000, so 100 means 1%).
    /// @return The net amount after deducting the fee.
    function _doCutFee(
        address token,
        uint256 amount,
        uint256 feeRate
    ) internal returns (uint256) {
        address treasury = config.treasury();
        if (treasury == address(0)) revert Errors.NO_TREASURY_SET();

        /// Calculate the fee based on the provided rate.
        uint256 fee = (amount * feeRate) / Constants.DENOMINATOR;
        /// Transfer the fee to the treasury if it's non-zero.
        if (fee > 0) {
            IERC20Upgradeable(token).safeTransferFrom(
                msg.sender,
                treasury,
                fee
            );
        }
        return amount - fee; /// Return the net amount after deducting the fee.
    }
}
