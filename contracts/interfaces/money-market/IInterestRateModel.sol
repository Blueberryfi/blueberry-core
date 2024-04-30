// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IInterestRateModel {
    function isInterestRateModel() external view returns (bool);

    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);

    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}
