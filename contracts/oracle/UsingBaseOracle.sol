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

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @title UsingBaseOracle
 * @author BlueberryProtocol
 * @dev This contract serves as a base for other contracts that need access
 *      to an external oracle service. It provides an immutable reference to a
 *      specified oracle source.
 */
abstract contract UsingBaseOracle is Ownable2StepUpgradeable {
    /// @dev Base oracle source
    IBaseOracle internal _base;

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

    /* solhint-disable func-name-mixedcase */
    /**
     * @dev Initializes the Base oracle source.
     * @param base Address of the Base oracle source.
     * @param owner Address of the owner.
     */
    function __UsingBaseOracle_init(IBaseOracle base, address owner) internal onlyInitializing {
        _base = base;
        __Ownable2Step_init();
        _transferOwnership(owner);
    }

    /* solhint-enable func-name-mixedcase */

    /// @notice Returns the address of the Base oracle source.
    function getBaseOracle() public view returns (IBaseOracle) {
        return _base;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     *      variables without shifting down storage in the inheritance chain.
     *      See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[10] private __gap;
}
