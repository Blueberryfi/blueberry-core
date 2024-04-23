// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/* solhint-enable max-line-length */

import "../utils/BlueberryErrors.sol" as Errors;

import { IWERC20 } from "../interfaces/IWERC20.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";

/**
 * @title WERC20
 * @author BlueberryProtocol
 * @notice Wrapped ERC20 is the wrapper of LP positions
 * @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank and do not generate yields.
 *      LP Tokens are identified by tokenIds encoded from lp token address
 */
contract WERC20 is IWERC20, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
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

    /**
     * @notice Initializes the ERC1155 and ReentrancyGuard base contracts.
     * @param owner The owner of the contract.
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("wERC20");
    }

    /// @inheritdoc IWERC20
    function mint(address token, uint256 amount) external override nonReentrant returns (uint256 id) {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(address(this));
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20Upgradeable(token).balanceOf(address(this));

        id = _encodeTokenId(token);

        _mint(msg.sender, id, balanceAfter - balanceBefore, "");

        emit Minted(id, amount);
    }

    /// @inheritdoc IWERC20
    function burn(address token, uint256 amount) external override nonReentrant {
        uint256 id = _encodeTokenId(token);
        _burn(msg.sender, id, amount);
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);

        emit Burned(id, amount);
    }

    /// @inheritdoc IERC20Wrapper
    function getUnderlyingToken(uint256 tokenId) external pure override returns (address token) {
        token = _decodeTokenId(tokenId);
        if (_encodeTokenId(token) != tokenId) revert Errors.INVALID_TOKEN_ID(tokenId);
    }

    /// @inheritdoc IERC20Wrapper
    function pendingRewards(
        uint256 tokenId,
        uint amount
    ) public view override returns (address[] memory, uint256[] memory) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IWERC20
    function balanceOfERC20(address token, address user) external view override returns (uint256) {
        return balanceOf(user, _encodeTokenId(token));
    }

    /**
     * @dev Encodes a given ERC20 token address into a unique tokenId for ERC1155.
     * @param underlyingToken The address of the ERC20 token.
     * @return The unique tokenId.
     */
    function _encodeTokenId(address underlyingToken) internal pure returns (uint) {
        return uint256(uint160(underlyingToken));
    }

    /**
     * @dev Decodes a given tokenId back into its corresponding ERC20 token address.
     * @param tokenId The tokenId to decode.
     * @return The decoded ERC20 token address.
     */
    function _decodeTokenId(uint tokenId) internal pure returns (address) {
        return address(uint160(tokenId));
    }
}
