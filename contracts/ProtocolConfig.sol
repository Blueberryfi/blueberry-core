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

import "./utils/BlueBerryConst.sol" as Constants;
import "./utils/BlueBerryErrors.sol" as Errors;
import "./interfaces/IProtocolConfig.sol";


/// @title ProtocolConfig
/// @author BlueberryProtocol
/// @notice This contract acts as the central point of all configurable states in the Blueberry Protocol.
///         It holds references to fee management, various fee types and values, 
///         treasury settings, and other system configurations.

contract ProtocolConfig is OwnableUpgradeable, IProtocolConfig {

    /// Fee manager of the protocol to handle different types of fees.
    IFeeManager public feeManager;

    /// Fee structures related to leveraging activities.
    uint256 public depositFee;             // Fee applied on deposits.
    uint256 public withdrawFee;            // Fee applied on withdrawals.
    uint256 public rewardFee;              // Fee applied on reward claims.

    /// Fee structures related to vault operations.
    uint256 public withdrawVaultFee;                 /// Fee applied on vault withdrawals.
    uint256 public withdrawVaultFeeWindow;           /// Time window for which the vault withdrawal fee applies.
    uint256 public withdrawVaultFeeWindowStartTime;  /// Start timestamp of the withdrawal fee window.

    /// Fee distribution rates.
    uint256 public treasuryFeeRate;        /// Portion of the fee sent to the protocol's treasury.
    uint256 public blbStablePoolFeeRate;   /// Portion of the fee for $BLB stablecoin pool.
    uint256 public blbIchiVaultFeeRate;    /// Portion of the fee for $BLB-ICHI vault.

    /// Addresses associated with the protocol.
    address public treasury;               /// Address of the protocol's treasury.
    address public blbUsdcIchiVault;       /// Address of the $BLB-USDC ICHI vault.
    address public blbStabilityPool;       /// Address of the $BLB stability pool against stablecoins.

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

    /// @dev Initializes the contract with the given treasury address.
    /// @param treasury_ Address of the treasury.
    function initialize(address treasury_) external initializer {
        __Ownable_init();
        if (treasury_ == address(0)) revert Errors.ZERO_ADDRESS();
        treasury = treasury_;

        /// Set default values for fees and fee rates.
        depositFee = 50; // Represents 0.5% (base 10000)
        withdrawFee = 50; // Represents 0.5% (base 10000)
        rewardFee = 1000; // Represents 10% (base 10000)

        treasuryFeeRate = 3000; // 30% of deposit/withdraw fee => 0.15%
        blbStablePoolFeeRate = 3500; //  35% of deposit/withdraw fee => 0.175%
        blbIchiVaultFeeRate = 3500; //  35% of deposit/withdraw fee => 0.175%

        withdrawVaultFee = 100; // Represents 1% (base 10000)
        withdrawVaultFeeWindow = 60 days; // Liquidity boot strapping event per vault
    }

    /// @dev Owner priviledged function to start the withdraw vault fee window
    /// @notice This function can only be called once per vault
    function startVaultWithdrawFee() external onlyOwner {
        if (withdrawVaultFeeWindowStartTime > 0)
            revert Errors.FEE_WINDOW_ALREADY_STARTED();
        withdrawVaultFeeWindowStartTime = block.timestamp;
    }

    /// @dev Owner priviledged function to set deposit fee
    /// @param depositFee_ Fee rate applied to the deposit
    function setDepositFee(uint256 depositFee_) external onlyOwner {
        /// Capped at 20%
        if (depositFee_ > Constants.MAX_FEE_RATE)
            revert Errors.RATIO_TOO_HIGH(depositFee_);
        depositFee = depositFee_;
    }

    /// @dev Owner priviledged function to set withdraw fee
    /// @param withdrawFee_ Fee rate applied to the withdraw
    function setWithdrawFee(uint256 withdrawFee_) external onlyOwner {
        /// Capped at 20%
        if (withdrawFee_ > Constants.MAX_FEE_RATE)
            revert Errors.RATIO_TOO_HIGH(withdrawFee_);
        withdrawFee = withdrawFee_;
    }

    /// @dev Owner priviledged function to set withdraw vault fee window duration
    /// @param withdrawVaultFeeWindow_ Duration of the withdraw vault fee window
    function setWithdrawVaultFeeWindow(
        uint256 withdrawVaultFeeWindow_
    ) external onlyOwner {
        /// Capped at 60 days
        if (withdrawVaultFeeWindow_ > Constants.MAX_WITHDRAW_VAULT_FEE_WINDOW)
            revert Errors.FEE_WINDOW_TOO_LONG(withdrawVaultFeeWindow_);
        withdrawVaultFeeWindow = withdrawVaultFeeWindow_;
    }

    /// @dev Owner priviledged function to set reward fee
    /// @param rewardFee_ Fee rate applied to the rewards
    function setRewardFee(uint256 rewardFee_) external onlyOwner {
        /// Capped at 20%
        if (rewardFee_ > Constants.MAX_FEE_RATE)
            revert Errors.RATIO_TOO_HIGH(rewardFee_);
        rewardFee = rewardFee_;
    }

    /// @dev Owner priviledged function to set the distribution rates for the various fees
    /// @param treasuryFeeRate_ Fee rate sent to treasury
    /// @param blbStablePoolFeeRate_ Fee rate applied to the $BLB liquidity pool
    /// @param blbIchiVaultFeeRate_ Fee rate applied to the $BLB-ICHI vault
    function setFeeDistribution(
        uint256 treasuryFeeRate_,
        uint256 blbStablePoolFeeRate_,
        uint256 blbIchiVaultFeeRate_
    ) external onlyOwner {
        if (
            (treasuryFeeRate_ + blbStablePoolFeeRate_ + blbIchiVaultFeeRate_) !=
            Constants.DENOMINATOR
        ) revert Errors.INVALID_FEE_DISTRIBUTION();
        treasuryFeeRate = treasuryFeeRate_;
        blbStablePoolFeeRate = blbStablePoolFeeRate_;
        blbIchiVaultFeeRate = blbIchiVaultFeeRate_;
    }

    /// @dev Owner priviledged function to set treasury address
    /// @param treasury_ Address of the new treasury
    function setTreasuryWallet(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert Errors.ZERO_ADDRESS();
        treasury = treasury_;
    }

    /// @dev Owner priviledged function to set fee manager address
    /// @param feeManager_ Address of the new fee manager
    function setFeeManager(address feeManager_) external onlyOwner {
        if (feeManager_ == address(0)) revert Errors.ZERO_ADDRESS();
        feeManager = IFeeManager(feeManager_);
    }

    /// @dev Owner priviledged function to set $BLB-ICHI vault address
    /// @param vault_ Address of the new vault
    function setBlbUsdcIchiVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert Errors.ZERO_ADDRESS();
        blbUsdcIchiVault = vault_;
    }

    /// @dev Owner priviledged function to set $BLB stability pool address
    /// @param pool_ Address of the new stability pool
    function setBlbStabilityPool(address pool_) external onlyOwner {
        if (pool_ == address(0)) revert Errors.ZERO_ADDRESS();
        blbStabilityPool = pool_;
    }
}
