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
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
/* solhint-enable max-line-length */

import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { IProtocolConfig } from "../interfaces/IProtocolConfig.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";
import { IBErc20 } from "../interfaces/money-market/IBErc20.sol";

/**
 * @title SoftVault
 * @author BlueberryProtocol
 * @notice The SoftVault contract is used to lock LP tokens as collateral.
 *         This vault simply holds onto LP tokens deposited by users, serving as collateral storage.
 * @dev The SoftVault is an ERC20 contract where each LP token is associated with a unique tokenId.
 *      The tokenId is derived from the LP token address. Only LP tokens listed by the Blueberry team
 */
contract SoftVault is OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable, ISoftVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev address of bToken for underlying token
    IBErc20 private _bToken;
    /// @dev address of underlying token
    IERC20Upgradeable private _uToken;
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

    /// @inheritdoc ISoftVault
    function initialize(
        IProtocolConfig config,
        IBErc20 bToken,
        string memory name,
        string memory symbol
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC20_init(name, symbol);

        if (address(bToken) == address(0) || address(config) == address(0)) revert Errors.ZERO_ADDRESS();

        IERC20Upgradeable uToken = IERC20Upgradeable(bToken.underlying());
        _config = config;
        _bToken = bToken;
        _uToken = uToken;
    }

    /*
     * @dev Vault has same decimal as bToken, bToken has same decimal as underlyingToken
     * @notice gets the decimals of the underlying token
     * @return decimals of the underlying token
     */
    function decimals() public view override returns (uint8) {
        return _bToken.decimals();
    }

    /// @inheritdoc ISoftVault
    function deposit(uint256 amount) external override nonReentrant returns (uint256 shareAmount) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();
        uint256 uBalanceBefore = _uToken.balanceOf(address(this));
        _uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = _uToken.balanceOf(address(this));

        uint256 cBalanceBefore = _bToken.balanceOf(address(this));
        IERC20(address(_uToken)).universalApprove(address(_bToken), amount);
        if (_bToken.mint(uBalanceAfter - uBalanceBefore) != 0) revert Errors.LEND_FAILED(amount);
        uint256 cBalanceAfter = _bToken.balanceOf(address(this));

        shareAmount = cBalanceAfter - cBalanceBefore;
        _mint(msg.sender, shareAmount);

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /// @inheritdoc ISoftVault
    function withdraw(uint256 shareAmount) external override nonReentrant returns (uint256 withdrawAmount) {
        if (shareAmount == 0) revert Errors.ZERO_AMOUNT();

        _burn(msg.sender, shareAmount);

        uint256 uBalanceBefore = _uToken.balanceOf(address(this));
        if (_bToken.redeem(shareAmount) != 0) revert Errors.REDEEM_FAILED(shareAmount);
        uint256 uBalanceAfter = _uToken.balanceOf(address(this));

        withdrawAmount = uBalanceAfter - uBalanceBefore;
        IERC20(address(_uToken)).universalApprove(address(_config.feeManager()), withdrawAmount);

        withdrawAmount = _config.feeManager().doCutVaultWithdrawFee(address(_uToken), withdrawAmount);
        _uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }

    /// @inheritdoc ISoftVault
    function getBToken() external view override returns (IBErc20) {
        return _bToken;
    }

    /// @inheritdoc ISoftVault
    function getUToken() external view override returns (IERC20Upgradeable) {
        return _uToken;
    }

    /// @inheritdoc ISoftVault
    function getConfig() external view returns (IProtocolConfig) {
        return _config;
    }
}
