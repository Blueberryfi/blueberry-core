// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/// @title IWETH
/// @notice This is the interface for the Wrapped Ether (WETH) contract.
/// @dev WETH is an ERC20-compatible version of Ether, facilitating interactions in smart contracts.
interface IWETH {
    /// @notice Fetch the balance of `user` in terms of WETH.
    /// @param user The address of the account whose balance will be retrieved.
    /// @return The balance of the given user's address.
    function balanceOf(address user) external view returns (uint256);

    /// @notice Approve an address to spend WETH on behalf of the message sender.
    /// @param to The address to grant spending rights.
    /// @param value The amount of WETH the spender is allowed to transfer.
    /// @return A boolean value indicating whether the operation succeeded.
    function approve(address to, uint256 value) external returns (bool);

    /// @notice Transfer WETH from the message sender to another address.
    /// @param to The recipient address.
    /// @param value The amount of WETH to be transferred.
    /// @return A boolean value indicating whether the transfer was successful.
    function transfer(address to, uint256 value) external returns (bool);

    /// @notice Convert Ether to WETH by sending Ether to the contract.
    /// @dev This function should be called with a payable modifier to attach Ether.
    function deposit() external payable;

    /// @notice Convert WETH back into Ether and send it to the message sender.
    function withdraw(uint256) external;
}
