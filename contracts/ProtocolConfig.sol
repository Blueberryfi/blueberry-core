// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./utils/BlueBerryConst.sol";
import "./utils/BlueBerryErrors.sol";
import "./interfaces/IProtocolConfig.sol";

contract ProtocolConfig is OwnableUpgradeable, IProtocolConfig {
    uint256 public depositFee;
    uint256 public withdrawFee;

    uint256 public withdrawVaultFee;
    uint256 public withdrawVaultFeeWindow;
    uint256 public withdrawVaultFeeWindowStartTime;

    uint256 public treasuryFeeRate;
    uint256 public blbStablePoolFeeRate;
    uint256 public blbIchiVaultFeeRate;

    address public treasury;
    address public blbUsdcIchiVault;
    /// @dev $BLB liquidity pool against stablecoins
    address public blbStabilityPool;

    function initialize(address treasury_) external initializer {
        __Ownable_init();
        if (treasury_ == address(0)) revert ZERO_ADDRESS();
        treasury = treasury_;

        depositFee = 50; // 0.5% as default, base 10000
        withdrawFee = 50; // 0.5% as default, base 10000
        treasuryFeeRate = 3000; // 30% of deposit/withdraw fee => 0.15%
        blbStablePoolFeeRate = 3500; //  35% of deposit/withdraw fee => 0.175%
        blbIchiVaultFeeRate = 3500; //  35% of deposit/withdraw fee => 0.175%

        withdrawVaultFee = 100; // 1% as default, base 10000
        withdrawVaultFeeWindow = 60 days;
    }

    function startVaultWithdrawFee() external onlyOwner {
        withdrawVaultFeeWindowStartTime = block.timestamp;
    }

    /**
     * @dev Owner priviledged function to set deposit fee
     */
    function setDepositFee(uint256 depositFee_) external onlyOwner {
        // Cap to 20%
        if (depositFee_ > 2000) revert FEE_TOO_HIGH(depositFee_);
        depositFee = depositFee_;
    }

    function setWithdrawFee(uint256 withdrawFee_) external onlyOwner {
        // Cap to 20%
        if (withdrawFee_ > 2000) revert FEE_TOO_HIGH(withdrawFee_);
        withdrawFee = withdrawFee_;
    }

    function setFeeDistribution(
        uint256 treasuryFeeRate_,
        uint256 blbStablePoolFeeRate_,
        uint256 blbIchiVaultFeeRate_
    ) external onlyOwner {
        if (
            (treasuryFeeRate_ + blbStablePoolFeeRate_ + blbIchiVaultFeeRate_) !=
            DENOMINATOR
        ) revert INVALID_FEE_DISTRIBUTION();
        treasuryFeeRate = treasuryFeeRate_;
        blbStablePoolFeeRate = blbStablePoolFeeRate_;
        blbIchiVaultFeeRate = blbIchiVaultFeeRate_;
    }

    function setTreasuryWallet(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZERO_ADDRESS();
        treasury = treasury_;
    }

    function setBlbUsdcIchiVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZERO_ADDRESS();
        blbUsdcIchiVault = vault_;
    }

    function setBlbStabilityPool(address pool_) external onlyOwner {
        if (pool_ == address(0)) revert ZERO_ADDRESS();
        blbStabilityPool = pool_;
    }
}
