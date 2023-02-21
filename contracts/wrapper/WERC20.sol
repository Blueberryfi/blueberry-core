// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryErrors.sol" as Errors;
import "../interfaces/IWERC20.sol";

contract WERC20 is ERC1155Upgradeable, ReentrancyGuardUpgradeable, IWERC20 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize() external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("WERC20");
    }

    /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
    /// @param id token id (corresponds to token address for wrapped ERC20)
    function getUnderlyingToken(uint256 id)
        external
        pure
        override
        returns (address)
    {
        address token = address(uint160(id));
        if (uint256(uint160(token)) != id) revert Errors.INVALID_TOKEN_ID(id);
        return token;
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
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(
            address(this)
        );
        IERC20Upgradeable(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        uint256 balanceAfter = IERC20Upgradeable(token).balanceOf(
            address(this)
        );
        _mint(
            msg.sender,
            uint256(uint160(token)),
            balanceAfter - balanceBefore,
            ""
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
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
    }
}
