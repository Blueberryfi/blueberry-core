// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IInterestRateModel {
    /// @dev Return the interest rate per year in basis point given the parameters.
    /// @param token The token address to query for interest rate.
    /// @param supply The current total supply value from lenders.
    /// @param borrow The current total borrow value from borrowers.
    /// @param reserve The current unwithdrawn reserve funds.
    function getBorrowRate(
        address token,
        uint256 supply,
        uint256 borrow,
        uint256 reserve
    ) external view returns (uint256);
}
