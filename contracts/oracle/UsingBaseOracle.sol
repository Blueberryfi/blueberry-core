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

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @title UsingBaseOracle
 * @author BlueberryProtocol
 * @dev This contract serves as a base for other contracts that need access
 *      to an external oracle service. It provides an immutable reference to a
 *      specified oracle source.
 */
contract UsingBaseOracle {
    /// @dev Base oracle source
    IBaseOracle internal immutable _base;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructs a new instance of the contract.
     * @dev Initializes the contract with a given oracle source.
     * @param base The address of the oracle to be used as a data source.
     */
    constructor(IBaseOracle base) {
        _base = base;
    }

    /// @notice Returns the address of the Base oracle source.
    function getBaseOracle() public view returns (IBaseOracle) {
        return _base;
    }
}
