// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IProtocolConfig } from "./IProtocolConfig.sol";

/**
 * @title IFeeManager
 * @notice Interface for FeeManager, the central fee management contract in the Blueberry Protocol.
 * @dev FeeManager is responsible for cutting various fees in the protocol and sending them to the treasury.
 */
interface IFeeManager {
    /**
     * @notice Calculates and deducts the deposit fee when lending
     *         isolated underlying assets to Blueberry Money Market.
     * @param token The address of the underlying token for which the deposit fee is to be calculated.
     * @param amount The gross deposit amount before fees.
     * @return The net deposit amount after the fee deduction.
     */
    function doCutDepositFee(address token, uint256 amount) external returns (uint256);

    /**
     * @notice Calculates and deducts the withdrawal fee when redeeming
     *         isolated underlying tokens from Blueberry Money Market.
     * @param token The address of the underlying token for which the withdrawal fee is to be calculated.
     * @param amount The gross withdrawal amount before fees.
     * @return The net withdrawal amount after the fee deduction.
     */
    function doCutWithdrawFee(address token, uint256 amount) external returns (uint256);

    /**
     * @notice Calculates and deducts the performance fee from the
     *         rewards generated due to the leveraged position.
     * @param token The address of the reward token for which the reward fee is to be calculated.
     * @param amount The gross reward amount before fees.
     * @return The net reward amount after the fee deduction.
     */
    function doCutRewardsFee(address token, uint256 amount) external returns (uint256);

    /**
     * @notice Calculates and deducts the vault withdrawal fee if
     *         the withdrawal occurs within the specified fee window in the Blueberry Money Market.
     * @param token The address of the underlying token for which the vault withdrawal fee is to be calculated.
     * @param amount The gross vault withdrawal amount before fees.
     * @return The net vault withdrawal amount after the fee deduction.
     */
    function doCutVaultWithdrawFee(address token, uint256 amount) external returns (uint256);

    /**
     * @notice Gets the protocol config contract address.
     */
    function getConfig() external view returns (IProtocolConfig);
}
