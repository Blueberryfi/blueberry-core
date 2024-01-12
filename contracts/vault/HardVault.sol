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
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
/* solhint-enable max-line-length */

import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { IHardVault } from "../interfaces/IHardVault.sol";
import { IProtocolConfig } from "../interfaces/IProtocolConfig.sol";

/**
 * @title HardVault
 * @author BlueberryProtocol
 * @notice The HardVault contract is used to lock LP tokens as collateral.
 *         This vault simply holds onto LP tokens deposited by users, serving as collateral storage.
 * @dev The HardVault is an ERC1155 contract where each LP token is associated with a unique tokenId.
 *      The tokenId is derived from the LP token address. Only LP tokens listed by the Blueberry team
 *      can be used as collateral in this vault.
 */
contract HardVault is OwnableUpgradeable, ERC1155Upgradeable, ReentrancyGuardUpgradeable, IHardVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev address of protocol config
    IProtocolConfig private _config;

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

    /// @inheritdoc IHardVault
    function initialize(IProtocolConfig config) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC1155_init("HardVault");

        if (address(config) == address(0)) revert Errors.ZERO_ADDRESS();
        _config = config;
    }

    /// @dev Encodes a given ERC20 token address into a unique tokenId.
    /// @param uToken Address of the ERC20 token.
    /// @return TokenId representing the token.
    function _encodeTokenId(address uToken) internal pure returns (uint256) {
        return uint256(uint160(uToken));
    }

    /// @dev Decodes a given tokenId back into the ERC20 token address.
    /// @param tokenId The tokenId to decode.
    /// @return Address of the corresponding ERC20 token.
    function _decodeTokenId(uint256 tokenId) internal pure returns (address) {
        return address(uint160(tokenId));
    }

    /// @inheritdoc IHardVault
    function balanceOfERC20(address token, address user) external view override returns (uint256) {
        return balanceOf(user, _encodeTokenId(token));
    }

    /// @inheritdoc IHardVault
    function getUnderlyingToken(uint256 tokenId) external pure override returns (address token) {
        token = _decodeTokenId(tokenId);
        if (_encodeTokenId(token) != tokenId) revert Errors.INVALID_TOKEN_ID(tokenId);
    }

    /// @inheritdoc IHardVault
    function deposit(address token, uint256 amount) external override nonReentrant returns (uint256 shareAmount) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();
        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        shareAmount = uBalanceAfter - uBalanceBefore;
        _mint(msg.sender, uint256(uint160(token)), shareAmount, "");

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /// @inheritdoc IHardVault
    function withdraw(
        address token,
        uint256 shareAmount
    ) external override nonReentrant returns (uint256 withdrawAmount) {
        if (shareAmount == 0) revert Errors.ZERO_AMOUNT();
        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        _burn(msg.sender, _encodeTokenId(token), shareAmount);

        /// Apply withdrawal fee if within the fee window (e.g., 2 months)
        IERC20(address(uToken)).universalApprove(address(_config.feeManager()), shareAmount);

        withdrawAmount = _config.feeManager().doCutVaultWithdrawFee(address(uToken), shareAmount);
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }

    /// @inheritdoc IHardVault
    function getConfig() external view returns (IProtocolConfig) {
        return _config;
    }
}
