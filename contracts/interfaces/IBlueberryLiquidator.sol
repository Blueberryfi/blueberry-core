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
import { AutomationCompatibleInterface } from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

interface IBlueberryLiquidator is AutomationCompatibleInterface {
    /**
     * @notice Liquidate position using a flash loan
     * @param positionId position id to liquidate
     */
    function liquidate(uint256 positionId) external;

    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @dev This function is only called if the flash loan was from Aave
     * @param asset The addresses of the flash-borrowed assets
     * @param amount The amounts of the flash-borrowed assets
     * @param premium The fee of each flash-borrowed asset
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata data
    ) external returns (bool);


    // /**
    //  * @dev Receive a flash loan from the Blueberry Money Market.
    //  * @param initiator The initiator of the loan.
    //  * @param token The loan currency.
    //  * @param amount The amount of tokens lent.
    //  * @param fee The additional amount of tokens to repay.
    //  * @param data Arbitrary data structure, intended to contain user-defined parameters.
    //  * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
    //  */
    // function onFlashLoan(
    //     address initiator,
    //     address token,
    //     uint256 amount,
    //     uint256 fee,
    //     bytes calldata data
    // ) external returns (bytes32);

}
