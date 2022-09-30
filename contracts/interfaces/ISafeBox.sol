// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ISafeBox is IERC20 {
    function lend(uint256 amount) external returns (uint256 lendAmount);

    function withdraw(uint256 amount) external returns (uint256 withdrawAmount);
}
