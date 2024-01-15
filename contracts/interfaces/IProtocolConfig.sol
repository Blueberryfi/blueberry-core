// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IFeeManager } from "./IFeeManager.sol";

/**
 * @title IProtocolConfig
 * @author BlueberryProtocol
 * @notice Interface for the Protocol Configuration,
 *         encapsulating various fees and related configuration parameters.
 * @dev This interface defines methods to retrieve fees
 *      and related parameters that govern the behavior of the protocol.
 */
interface IProtocolConfig {
    /**
     * @notice Retrieve the deposit fee rate applied when users deposit into the protocol.
     * @return The deposit fee rate.
     */
    function getDepositFee() external view returns (uint256);

    /**
     * @notice Retrieve the withdrawal fee rate applied when users withdraw from the protocol.
     * @return The withdrawal fee rate.
     */
    function getWithdrawFee() external view returns (uint256);

    /**
     * @notice Retrieve the reward fee rate applied when users claim rewards from the protocol.
     * @return The reward fee rate.
     */
    function getRewardFee() external view returns (uint256);

    /**
     * @notice Get the address where protocol's collected fees are stored and managed.
     * @return The treasury address of the protocol.
     */
    function getTreasury() external view returns (address);

    /**
     * @notice Retrieve the fee rate applied for withdrawals from vaults.
     * @return The fee rate for vault withdrawals.
     */
    function getTreasuryFeeRate() external view returns (uint256);

    /**
     * @notice Retrieve the fee rate applied for withdrawals from vaults.
     * @return The fee rate for vault withdrawals.
     */
    function getWithdrawVaultFee() external view returns (uint256);

    /**
     * @notice Retrieve the window of time where the vault withdrawal fee is applied.
     * @return The window of time where the vault withdrawal fee is applied.
     */
    function getWithdrawVaultFeeWindow() external view returns (uint256);

    /**
     * @notice Retrieve the start time of the window of time where the vault withdrawal fee is applied.
     * @return The start time of the window of time where the vault withdrawal fee is applied.
     */
    function getWithdrawVaultFeeWindowStartTime() external view returns (uint256);

    /**
     * @notice Get the fee manager that handles fee calculations and distributions.
     * @return An instance of the IFeeManager interface that manages fees within the protocol.
     */
    function getFeeManager() external view returns (IFeeManager);

    /**
     * @notice Get the address of the $BLB-ICHI vault.
     * @return The address of the $BLB-ICHI vault.
     */
    function getBlbUsdcIchiVault() external view returns (address);

    /**
     * @notice Get the address of the $BLB stability pool.
     * @return The address of the $BLB stability pool.
     */
    function getBlbStabilityPool() external view returns (address);

    /**
     * @notice Get the fee rate applied for withdrawals from the $BLB-ICHI vault.
     * @return The fee rate for $BLB-ICHI vault withdrawals.
     */
    function getBlbIchiVaultFeeRate() external view returns (uint256);

    /**
     * @notice Get the fee rate applied for withdrawals from the $BLB-ICHI vault.
     * @return The fee rate for $BLB-ICHI vault withdrawals.
     */
    function getBlbStablePoolFeeRate() external view returns (uint256);
}
