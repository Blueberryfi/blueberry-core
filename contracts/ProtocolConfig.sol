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

import "./utils/BlueberryConst.sol" as Constants;
import "./utils/BlueberryErrors.sol" as Errors;

import { IFeeManager } from "./interfaces/IFeeManager.sol";
import { IProtocolConfig } from "./interfaces/IProtocolConfig.sol";

/**
 *  @title ProtocolConfig
 *  @author BlueberryProtocol
 *  @notice This contract acts as the central point of all configurable states in the Blueberry Protocol.
 *          It holds references to fee management, various fee types and values,
 *          treasury settings, and other system configurations.
 */
contract ProtocolConfig is IProtocolConfig, Ownable2StepUpgradeable {
    /// Fee manager of the protocol to handle different types of fees.
    IFeeManager private _feeManager;

    /// @dev Fee structures related to leveraging activities.
    uint256 private _depositFee; /// @dev Fee applied on deposits.
    uint256 private _withdrawFee; /// @dev Fee applied on withdrawals.
    uint256 private _rewardFee; /// @dev Fee applied on reward claims.

    /// @dev Fee structures related to vault operations.
    uint256 private _withdrawVaultFee; /// @dev Fee applied on vault withdrawals.
    uint256 private _withdrawVaultFeeWindow; /// @dev Time window for which the vault withdrawal fee applies.
    uint256 private _withdrawVaultFeeWindowStartTime; /// @dev Start timestamp of the withdrawal fee window.

    /// @dev Fee distribution rates.
    uint256 private _treasuryFeeRate; /// @dev Portion of the fee sent to the protocol's treasury.
    uint256 private _blbStablePoolFeeRate; /// @dev Portion of the fee for $BLB stablecoin pool.
    uint256 private _blbIchiVaultFeeRate; /// @dev Portion of the fee for $BLB-ICHI vault.

    /// @dev Addresses associated with the protocol.
    address private _treasury; /// @dev Address of the protocol's treasury.
    address private _blbUsdcIchiVault; /// @dev Address of the $BLB-USDC ICHI vault.
    address private _blbStabilityPool; /// @dev Address of the $BLB stability pool against stablecoins.

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
     * @dev Initializes the contract with the given treasury address.
     * @param treasury Address of the treasury.
     * @param owner Address of the owner.
     */
    function initialize(address treasury, address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
        if (treasury == address(0)) revert Errors.ZERO_ADDRESS();
        _treasury = treasury;

        /// Set default values for fees and fee rates.
        _depositFee = 50; // Represents 0.5% (base 10000)
        _withdrawFee = 50; // Represents 0.5% (base 10000)
        _rewardFee = 1000; // Represents 10% (base 10000)

        _treasuryFeeRate = 3000; // 30% of deposit/withdraw fee => 0.15%
        _blbStablePoolFeeRate = 3500; //  35% of deposit/withdraw fee => 0.175%
        _blbIchiVaultFeeRate = 3500; //  35% of deposit/withdraw fee => 0.175%

        _withdrawVaultFee = 100; // Represents 1% (base 10000)
        _withdrawVaultFeeWindow = 60 days; // Liquidity boot strapping event per vault
    }

    /**
     * @dev Owner priviledged function to start the withdraw vault fee window
     * @notice This function can only be called once per vault
     */
    function startVaultWithdrawFee() external onlyOwner {
        if (_withdrawVaultFeeWindowStartTime > 0) revert Errors.FEE_WINDOW_ALREADY_STARTED();
        _withdrawVaultFeeWindowStartTime = block.timestamp;
    }

    /**
     * @dev Owner priviledged function to set deposit fee
     * @param depositFee Fee rate applied to the deposit
     */
    function setDepositFee(uint256 depositFee) external onlyOwner {
        /// Capped at 20%
        if (depositFee > Constants.MAX_FEE_RATE) revert Errors.RATIO_TOO_HIGH(depositFee);
        _depositFee = depositFee;
    }

    /**
     * @dev Owner priviledged function to set withdraw fee
     * @param withdrawFee Fee rate applied to the withdraw
     */
    function setWithdrawFee(uint256 withdrawFee) external onlyOwner {
        /// Capped at 20%
        if (withdrawFee > Constants.MAX_FEE_RATE) revert Errors.RATIO_TOO_HIGH(withdrawFee);
        _withdrawFee = withdrawFee;
    }

    /**
     * @dev Owner priviledged function to set withdraw vault fee window duration
     * @param withdrawVaultFeeWindow Duration of the withdraw vault fee window
     */
    function setWithdrawVaultFeeWindow(uint256 withdrawVaultFeeWindow) external onlyOwner {
        /// Capped at 60 days
        if (withdrawVaultFeeWindow > Constants.MAX_WITHDRAW_VAULT_FEE_WINDOW) {
            revert Errors.FEE_WINDOW_TOO_LONG(withdrawVaultFeeWindow);
        }
        _withdrawVaultFeeWindow = withdrawVaultFeeWindow;
    }

    /**
     * @dev Owner priviledged function to set reward fee
     * @param rewardFee Fee rate applied to the rewards
     */
    function setRewardFee(uint256 rewardFee) external onlyOwner {
        /// Capped at 20%
        if (rewardFee > Constants.MAX_FEE_RATE) revert Errors.RATIO_TOO_HIGH(rewardFee);
        _rewardFee = rewardFee;
    }

    /**
     * @dev Owner priviledged function to set the distribution rates for the various fees
     * @param treasuryFeeRate Fee rate sent to treasury
     * @param blbStablePoolFeeRate Fee rate applied to the $BLB liquidity pool
     * @param blbIchiVaultFeeRate Fee rate applied to the $BLB-ICHI vault
     */
    function setFeeDistribution(
        uint256 treasuryFeeRate,
        uint256 blbStablePoolFeeRate,
        uint256 blbIchiVaultFeeRate
    ) external onlyOwner {
        if ((treasuryFeeRate + blbStablePoolFeeRate + blbIchiVaultFeeRate) != Constants.DENOMINATOR) {
            revert Errors.INVALID_FEE_DISTRIBUTION();
        }
        _treasuryFeeRate = treasuryFeeRate;
        _blbStablePoolFeeRate = blbStablePoolFeeRate;
        _blbIchiVaultFeeRate = blbIchiVaultFeeRate;
    }

    /**
     * @dev Owner priviledged function to set treasury address
     * @param treasury Address of the new treasury
     */
    function setTreasuryWallet(address treasury) external onlyOwner {
        if (treasury == address(0)) revert Errors.ZERO_ADDRESS();
        _treasury = treasury;
    }

    /**
     * @dev Owner priviledged function to set fee manager address
     * @param feeManager Address of the new fee manager
     */
    function setFeeManager(address feeManager) external onlyOwner {
        if (feeManager == address(0)) revert Errors.ZERO_ADDRESS();
        _feeManager = IFeeManager(feeManager);
    }

    /**
     * @dev Owner priviledged function to set $BLB-ICHI vault address
     * @param vault Address of the new vault
     */
    function setBlbUsdcIchiVault(address vault) external onlyOwner {
        if (vault == address(0)) revert Errors.ZERO_ADDRESS();
        _blbUsdcIchiVault = vault;
    }

    /**
     * @dev Owner priviledged function to set $BLB stability pool address
     * @param pool Address of the new stability pool
     */
    function setBlbStabilityPool(address pool) external onlyOwner {
        if (pool == address(0)) revert Errors.ZERO_ADDRESS();
        _blbStabilityPool = pool;
    }

    /// @inheritdoc IProtocolConfig
    function getDepositFee() external view override returns (uint256) {
        return _depositFee;
    }

    /// @inheritdoc IProtocolConfig
    function getWithdrawFee() external view override returns (uint256) {
        return _withdrawFee;
    }

    /// @inheritdoc IProtocolConfig
    function getRewardFee() external view override returns (uint256) {
        return _rewardFee;
    }

    /// @inheritdoc IProtocolConfig
    function getTreasury() external view override returns (address) {
        return _treasury;
    }

    /// @inheritdoc IProtocolConfig
    function getTreasuryFeeRate() external view override returns (uint256) {
        return _treasuryFeeRate;
    }

    /// @inheritdoc IProtocolConfig
    function getWithdrawVaultFee() external view override returns (uint256) {
        return _withdrawVaultFee;
    }

    /// @inheritdoc IProtocolConfig
    function getWithdrawVaultFeeWindow() external view override returns (uint256) {
        return _withdrawVaultFeeWindow;
    }

    /// @inheritdoc IProtocolConfig
    function getWithdrawVaultFeeWindowStartTime() external view override returns (uint256) {
        return _withdrawVaultFeeWindowStartTime;
    }

    /// @inheritdoc IProtocolConfig
    function getFeeManager() external view override returns (IFeeManager) {
        return _feeManager;
    }

    /// @inheritdoc IProtocolConfig
    function getBlbUsdcIchiVault() external view override returns (address) {
        return _blbUsdcIchiVault;
    }

    /// @inheritdoc IProtocolConfig
    function getBlbStabilityPool() external view override returns (address) {
        return _blbStabilityPool;
    }

    /// @inheritdoc IProtocolConfig
    function getBlbIchiVaultFeeRate() external view override returns (uint256) {
        return _blbIchiVaultFeeRate;
    }

    /// @inheritdoc IProtocolConfig
    function getBlbStablePoolFeeRate() external view override returns (uint256) {
        return _blbStablePoolFeeRate;
    }
}
