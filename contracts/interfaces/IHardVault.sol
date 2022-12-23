// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "./IERC20Wrapper.sol";

interface IHardVault is IERC1155Upgradeable, IERC20Wrapper {
    /// @dev Return the underlying ERC20 balance for the user.
    function balanceOfERC20(address uToken, address user)
        external
        view
        returns (uint256);

    function deposit(address uToken, uint256 amount)
        external
        returns (uint256 shareAmount);

    function withdraw(address uToken, uint256 shareAmount)
        external
        returns (uint256 withdrawAmount);
}
