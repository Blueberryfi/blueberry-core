// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import './IERC20Wrapper.sol';

interface IWStakingRewards is IERC1155, IERC20Wrapper {
    /// @dev Mint ERC1155 token for the given ERC20 token.
    function mint(uint256 amount) external returns (uint256 id);

    /// @dev Burn ERC1155 token to redeem ERC20 token back.
    function burn(uint256 id, uint256 amount) external returns (uint256);

    function reward() external returns (address);
}
