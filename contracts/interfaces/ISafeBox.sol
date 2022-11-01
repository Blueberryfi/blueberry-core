// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ISafeBox is IERC20 {
    function deposit(uint256 amount) external returns (uint256 ctokenAmount);

    function borrow(uint256 amount) external returns (uint256 borrowAmount);

    function repay(uint256 amount) external returns (uint256 newDebt);

    function withdraw(uint256 amount) external returns (uint256 withdrawAmount);
}
