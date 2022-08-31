// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ISafeBox {
    function borrow(uint256 amount) external returns (uint256 borrowAmount);
}
