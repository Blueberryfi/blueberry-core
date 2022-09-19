// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../interfaces/IWERC20.sol';

contract WERC20 is ERC1155('WERC20'), ReentrancyGuard, IWERC20 {
    using SafeERC20 for IERC20;

    /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
    /// @param id token id (corresponds to token address for wrapped ERC20)
    function getUnderlyingToken(uint256 id)
        external
        pure
        override
        returns (address)
    {
        address token = address(uint160(id));
        require(uint256(uint160(token)) == id, 'id overflow');
        return token;
    }

    /// @dev Return the conversion rate from ERC-1155 to ERC-20, multiplied by 10**18.
    function getUnderlyingRate(uint256)
        external
        pure
        override
        returns (uint256)
    {
        return 1e18;
    }

    /// @dev Return the underlying ERC20 balance for the user.
    /// @param token token address to get balance of
    /// @param user user address to get balance of
    function balanceOfERC20(address token, address user)
        external
        view
        override
        returns (uint256)
    {
        return balanceOf(user, uint256(uint160(token)));
    }

    /// @dev Mint ERC1155 token for the given ERC20 token.
    /// @param token token address to wrap
    /// @param amount token amount to wrap
    function mint(address token, uint256 amount)
        external
        override
        nonReentrant
    {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        _mint(
            msg.sender,
            uint256(uint160(token)),
            balanceAfter - balanceBefore,
            ''
        );
    }

    /// @dev Burn ERC1155 token to redeem ERC20 token back.
    /// @param token token address to burn
    /// @param amount token amount to burn
    function burn(address token, uint256 amount)
        external
        override
        nonReentrant
    {
        _burn(msg.sender, uint256(uint160(token)), amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
