// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/**
 * @title IOwnable
 * @notice 2Step Ownable
 */
interface IOwnable {
    /*//////////////////////////////////////////////////////////////////////////
                                     Ownable Interface
    //////////////////////////////////////////////////////////////////////////*/
    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function pendingOwner() external view returns (address);

    function acceptOwnership() external;
}
