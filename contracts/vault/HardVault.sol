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
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryErrors.sol" as Errors;
import "../utils/EnsureApprove.sol";
import "../interfaces/IProtocolConfig.sol";
import "../interfaces/IHardVault.sol";

/// @title HardVault
/// @notice The HardVault contract is used to lock LP tokens as collateral.
///         This vault simply holds onto LP tokens deposited by users, serving as collateral storage.
/// @dev The HardVault is an ERC1155 contract where each LP token is associated with a unique tokenId.
///      The tokenId is derived from the LP token address. Only LP tokens listed by the Blueberry team
///      can be used as collateral in this vault.
contract HardVault is
    OwnableUpgradeable,
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    EnsureApprove,
    IHardVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev address of protocol config
    IProtocolConfig public config;

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Emitted when a user deposits ERC20 tokens into the vault.
    /// @param account Address of the user.
    /// @param amount Amount of ERC20 tokens deposited.
    /// @param shareAmount Amount of ERC1155 tokens minted.
    event Deposited(
        address indexed account,
        uint256 amount,
        uint256 shareAmount
    );

    /// @dev Emitted when a user withdraws ERC20 tokens from the vault.
    /// @param account Address of the user.
    /// @param amount Amount of ERC20 tokens withdrawn.
    /// @param shareAmount Amount of ERC1155 tokens burned.
    event Withdrawn(
        address indexed account,
        uint256 amount,
        uint256 shareAmount
    );

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

    /// @notice Initializes the HardVault contract with protocol configuration.
    /// @param _config Address of the protocol configuration.
    function initialize(IProtocolConfig _config) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC1155_init("HardVault");

        if (address(_config) == address(0)) revert Errors.ZERO_ADDRESS();
        config = _config;
    }

    /// @dev Encodes a given ERC20 token address into a unique tokenId.
    /// @param uToken Address of the ERC20 token.
    /// @return TokenId representing the token.
    function _encodeTokenId(address uToken) internal pure returns (uint) {
        return uint256(uint160(uToken));
    }

    /// @dev Decodes a given tokenId back into the ERC20 token address.
    /// @param tokenId The tokenId to decode.
    /// @return Address of the corresponding ERC20 token.
    function _decodeTokenId(uint tokenId) internal pure returns (address) {
        return address(uint160(tokenId));
    }

    /// @notice Gets the balance of a specific ERC20 token for a user.
    /// @param token Address of the ERC20 token.
    /// @param user Address of the user.
    /// @return Balance of the user for the given token.
    function balanceOfERC20(
        address token,
        address user
    ) external view override returns (uint256) {
        return balanceOf(user, _encodeTokenId(token));
    }

    /// @notice Maps a tokenId to its underlying ERC20 token.
    /// @param tokenId The tokenId to resolve.
    /// @return token Address of the corresponding ERC20 token.
    function getUnderlyingToken(
        uint256 tokenId
    ) external pure override returns (address token) {
        token = _decodeTokenId(tokenId);
        if (_encodeTokenId(token) != tokenId)
            revert Errors.INVALID_TOKEN_ID(tokenId);
    }

    /// @notice Allows a user to deposit ERC20 tokens into the vault and mint corresponding ERC1155 tokens.
    /// @dev Emits a {Deposited} event.
    /// @param token The ERC20 token to deposit.
    /// @param amount The amount of ERC20 tokens to deposit.
    /// @return shareAmount The amount of ERC1155 tokens minted in return.
    function deposit(
        address token,
        uint256 amount
    ) external override nonReentrant returns (uint256 shareAmount) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();
        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        shareAmount = uBalanceAfter - uBalanceBefore;
        _mint(msg.sender, uint256(uint160(token)), shareAmount, "");

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /// @notice Allows a user to burn their ERC1155 tokens and withdraw the underlying ERC20 tokens.
    /// @dev Emits a {Withdrawn} event.
    /// @param token The ERC20 token to withdraw.
    /// @param shareAmount The amount of ERC1155 tokens to burn.
    /// @return withdrawAmount The amount of ERC20 tokens withdrawn.
    function withdraw(
        address token,
        uint256 shareAmount
    ) external override nonReentrant returns (uint256 withdrawAmount) {
        if (shareAmount == 0) revert Errors.ZERO_AMOUNT();
        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        _burn(msg.sender, _encodeTokenId(token), shareAmount);

        /// Apply withdrawal fee if within the fee window (e.g., 2 months)
        _ensureApprove(
            address(uToken),
            address(config.feeManager()),
            shareAmount
        );
        withdrawAmount = config.feeManager().doCutVaultWithdrawFee(
            address(uToken),
            shareAmount
        );
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }
}
