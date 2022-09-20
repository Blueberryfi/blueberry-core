// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ISafeBox {
    function lend(uint256 amount) external returns (uint256 lendAmount);

    function borrow(uint256 amount) external returns (uint256 borrowAmount);

    function repay(uint256 amount) external returns (uint256 newDebt);
}
