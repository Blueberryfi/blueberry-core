// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface ISoftVault is IERC20Upgradeable {
    function uToken() external view returns (IERC20Upgradeable);

    function deposit(uint256 amount) external returns (uint256 shareAmount);

    function withdraw(uint256 amount) external returns (uint256 withdrawAmount);
}
