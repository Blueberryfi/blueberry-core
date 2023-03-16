// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./compound/ICErc20.sol";

interface ISoftVault is IERC20Upgradeable {
    function bToken() external view returns (ICErc20);

    function uToken() external view returns (IERC20Upgradeable);

    function deposit(uint256 amount) external returns (uint256 shareAmount);

    function withdraw(uint256 amount) external returns (uint256 withdrawAmount);
}
