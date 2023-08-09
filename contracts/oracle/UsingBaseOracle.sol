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

import "../interfaces/IBaseOracle.sol";

/// @title UsingBaseOracle
/// @dev This contract serves as a base for other contracts that need access 
/// to an external oracle service. It provides an immutable reference to a 
/// specified oracle source.
contract UsingBaseOracle {
    IBaseOracle public immutable base; // Base oracle source

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructs a new instance of the contract.
    /// @dev Initializes the contract with a given oracle source.
    /// @param _base The address of the oracle to be used as a data source.
    constructor(IBaseOracle _base) {
        base = _base;
    }
}
