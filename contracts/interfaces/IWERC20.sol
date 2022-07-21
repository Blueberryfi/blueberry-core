// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import './IERC20Wrapper.sol';

interface IWERC20 is IERC1155, IERC20Wrapper {
    /// @dev Return the underlying ERC20 balance for the user.
    function balanceOfERC20(address token, address user)
        external
        view
        returns (uint256);

    /// @dev Mint ERC1155 token for the given ERC20 token.
    function mint(address token, uint256 amount) external;

    /// @dev Burn ERC1155 token to redeem ERC20 token back.
    function burn(address token, uint256 amount) external;
}
