// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IApxEth is IERC4626 {

    /**
     * @notice Return the amount of assets per 1 (1e18) share
     * @return uint256 Assets
     */
    function assetsPerShare() external view returns (uint256);

    /**
     * @notice Reference to the PirexEth contract.
     */
    function pirexEth() external view returns (address);

    /**
     * @notice Harvest and stake available rewards after distributing fees to the platform
     * @dev This function claims and stakes the available rewards, deducting a fee for the platform.
     */
    function harvest() external;

    /**
     * @notice Returns the amount of rewards per staked token/asset
     * @return uint256 Rewards amount
     */
    function rewardPerToken() external view returns (uint256);
}
