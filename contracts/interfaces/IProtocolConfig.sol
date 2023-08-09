// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./IFeeManager.sol";

/// @title IProtocolConfig
/// @notice Interface for the Protocol Configuration, 
///         encapsulating various fees and related configuration parameters.
/// @dev This interface defines methods to retrieve fees 
///      and related parameters that govern the behavior of the protocol.
interface IProtocolConfig {

    /// @notice Retrieve the deposit fee rate applied when users deposit into the protocol.
    /// @return The deposit fee rate.
    function depositFee() external view returns (uint256);

    /// @notice Retrieve the withdrawal fee rate applied when users withdraw from the protocol.
    /// @return The withdrawal fee rate.
    function withdrawFee() external view returns (uint256);

    /// @notice Retrieve the reward fee rate applied when users claim rewards from the protocol.
    /// @return The reward fee rate.
    function rewardFee() external view returns (uint256);

    /// @notice Get the address where protocol's collected fees are stored and managed.
    /// @return The treasury address of the protocol.
    function treasury() external view returns (address);

    /// @notice Retrieve the fee rate applied for withdrawals from vaults.
    /// @return The fee rate for vault withdrawals.
    function withdrawVaultFee() external view returns (uint256);

    /// @notice Retrieve the window of time where the vault withdrawal fee is applied.
    /// @return The window of time where the vault withdrawal fee is applied.
    function withdrawVaultFeeWindow() external view returns (uint256);

    /// @notice Retrieve the start time of the window of time where the vault withdrawal fee is applied.
    /// @return The start time of the window of time where the vault withdrawal fee is applied.
    function withdrawVaultFeeWindowStartTime() external view returns (uint256);

    /// @notice Get the fee manager that handles fee calculations and distributions.
    /// @return An instance of the IFeeManager interface that manages fees within the protocol.
    function feeManager() external view returns (IFeeManager);
}
