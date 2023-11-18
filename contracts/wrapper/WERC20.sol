// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryErrors.sol" as Errors;
import "../interfaces/IWERC20.sol";

/// @title WERC20
/// @author BlueberryProtocol
/// @notice Wrapped ERC20 is the wrapper of LP positions
/// @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank and do not generate yields.
///      LP Tokens are identified by tokenIds encoded from lp token address
contract WERC20 is ERC1155Upgradeable, ReentrancyGuardUpgradeable, IWERC20 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    ///@notice Initializes the ERC1155 and ReentrancyGuard base contracts.
    function initialize() external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("WERC20");
    }

    /// @dev Encodes a given ERC20 token address into a unique tokenId for ERC1155.
    /// @param uToken The address of the ERC20 token.
    /// @return The unique tokenId.
    function _encodeTokenId(address uToken) internal pure returns (uint) {
        return uint256(uint160(uToken));
    }

    /// @dev Decodes a given tokenId back into its corresponding ERC20 token address.
    /// @param tokenId The tokenId to decode.
    /// @return The decoded ERC20 token address.
    function _decodeTokenId(uint tokenId) internal pure returns (address) {
        return address(uint160(tokenId));
    }

    /// @notice Fetches the underlying ERC20 token address for a given ERC1155 tokenId.
    /// @param tokenId The tokenId of the wrapped ERC20.
    /// @return token The underlying ERC20 token address.
    function getUnderlyingToken(
        uint256 tokenId
    ) external pure override returns (address token) {
        token = _decodeTokenId(tokenId);
        if (_encodeTokenId(token) != tokenId)
            revert Errors.INVALID_TOKEN_ID(tokenId);
    }

    /// @notice Retrieves pending rewards from the farming pool for a given tokenId.
    /// @dev Reward tokens can be multiple types.
    /// @param tokenId The tokenId to check rewards for.
    /// @param amount The amount of share.
    /// @return The list of reward addresses and their corresponding amounts.
    function pendingRewards(
        uint256 tokenId,
        uint amount
    ) public view override returns (address[] memory, uint256[] memory) {}

    /// @notice Fetches the balance of the underlying ERC20 token for a specific user.
    /// @param token The ERC20 token address.
    /// @param user The user's address.
    /// @return The user's balance of the specified ERC20 token.
    function balanceOfERC20(
        address token,
        address user
    ) external view override returns (uint256) {
        return balanceOf(user, _encodeTokenId(token));
    }

    /// @notice Allows users to wrap their ERC20 tokens into the corresponding ERC1155 tokenId.
    /// @param token The address of the ERC20 token to wrap.
    /// @param amount The amount of the ERC20 token to wrap.
    /// @return id The tokenId of the wrapped ERC20 token.
    function mint(
        address token,
        uint256 amount
    ) external override nonReentrant returns (uint256 id) {
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
        id = _encodeTokenId(token);
        _mint(msg.sender, id, balanceAfter - balanceBefore, "");
    }

    /// @notice Allows users to burn their ERC1155 token to retrieve the original ERC20 tokens.
    /// @param token The address of the ERC20 token to unwrap.
    /// @param amount The amount of the ERC20 token to unwrap.
    function burn(
        address token,
        uint256 amount
    ) external override nonReentrant {
        _burn(msg.sender, _encodeTokenId(token), amount);
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
    }
}
