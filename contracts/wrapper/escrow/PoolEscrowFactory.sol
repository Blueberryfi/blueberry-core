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

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { PoolEscrow } from "./PoolEscrow.sol";

import { IPoolEscrowFactory } from "./interfaces/IPoolEscrowFactory.sol";

/**
 * @title PoolEscrowFactory
 * @author BlueberryProtocol
 * @notice This contract acts as a factory for creating PoolEscrow contracts.
 */
contract PoolEscrowFactory is IPoolEscrowFactory, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

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
     * @notice Initializes the Pool Escrow Factory
     * @param owner The owner of the contract
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
    }

    /// @inheritdoc IPoolEscrowFactory
    function createEscrow(
        uint256 pid,
        address booster,
        address rewards,
        address lpToken
    ) external payable returns (address) {
        PoolEscrow escrow = new PoolEscrow(pid, msg.sender, booster, rewards, lpToken);

        emit EscrowCreated(address(escrow));

        return address(escrow);
    }
}
