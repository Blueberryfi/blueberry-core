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
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
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
 * @dev The HardVault allows ERC1155 tokens where each LP token is associated with a unique tokenId.
 *      The tokenId is derived from the LP token address. Only LP tokens listed by the Blueberry team
 *      can be used as collateral in this vault.
 */
contract HardVault is IHardVault, Ownable2StepUpgradeable, ERC1155Upgradeable, ReentrancyGuardUpgradeable {
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

    /**
     * @dev Initializes the HardVault contract.
     * @param config Address of the protocol config.
     * @param owner Address of the owner.
     */
    function initialize(IProtocolConfig config, address owner) external initializer {
        __ReentrancyGuard_init();
        __Ownable2Step_init();
        _transferOwnership(owner);
        __ERC1155_init("HardVault");

        if (address(config) == address(0)) revert Errors.ZERO_ADDRESS();
        _config = config;
    }

    /// @inheritdoc IHardVault
    function deposit(address token, uint256 amount) external override nonReentrant returns (uint256 shareAmount) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();

        IERC20Upgradeable underlyingToken = IERC20Upgradeable(token);

        uint256 underlyingBalanceBefore = underlyingToken.balanceOf(address(this));
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 underlyingBalanceAfter = underlyingToken.balanceOf(address(this));

        shareAmount = underlyingBalanceAfter - underlyingBalanceBefore;
        _mint(msg.sender, uint256(uint160(token)), shareAmount, "");

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /// @inheritdoc IHardVault
    function withdraw(
        address token,
        uint256 shareAmount
    ) external override nonReentrant returns (uint256 withdrawAmount) {
        if (shareAmount == 0) revert Errors.ZERO_AMOUNT();

        IProtocolConfig config = getConfig();

        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        _burn(msg.sender, _encodeTokenId(token), shareAmount);

        /// Apply withdrawal fee if within the fee window (e.g., 2 months)
        IERC20(address(uToken)).universalApprove(address(config.getFeeManager()), shareAmount);

        withdrawAmount = config.getFeeManager().doCutVaultWithdrawFee(address(uToken), shareAmount);
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }

    /// @inheritdoc IHardVault
    function balanceOfToken(address token, address user) external view override returns (uint256) {
        return balanceOf(user, _encodeTokenId(token));
    }

    /// @inheritdoc IHardVault
    function getUnderlyingToken(uint256 tokenId) external pure returns (address token) {
        token = _decodeTokenId(tokenId);
        if (_encodeTokenId(token) != tokenId) revert Errors.INVALID_TOKEN_ID(tokenId);
    }

    /// @inheritdoc IHardVault
    function getConfig() public view override returns (IProtocolConfig) {
        return _config;
    }

    /**
     * @dev Decodes a given tokenId back into the ERC20 token address.
     * @param tokenId The tokenId to decode.
     * @return Address of the corresponding ERC20 token.
     */
    function _decodeTokenId(uint256 tokenId) internal pure returns (address) {
        return address(uint160(tokenId));
    }

    /**
     * @dev Encodes a given ERC20 token address into a unique tokenId.
     * @param uToken Address of the ERC20 token.
     * @return TokenId representing the token.
     */
    function _encodeTokenId(address uToken) internal pure returns (uint256) {
        return uint256(uint160(uToken));
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     *      variables without shifting down storage in the inheritance chain.
     *      See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
