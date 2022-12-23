// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryConst.sol";
import "../utils/BlueBerryErrors.sol";
import "../interfaces/IProtocolConfig.sol";
import "../interfaces/IHardVault.sol";

contract HardVault is
    OwnableUpgradeable,
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    IHardVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IProtocolConfig public config;

    event Deposited(
        address indexed account,
        uint256 amount,
        uint256 shareAmount
    );
    event Withdrawn(
        address indexed account,
        uint256 amount,
        uint256 shareAmount
    );

    function initialize(IProtocolConfig _config) external initializer {
        __ERC1155_init("HardVault");
        __Ownable_init();
        if (address(_config) == address(0)) revert ZERO_ADDRESS();
        config = _config;
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

    /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
    /// @param id token id (corresponds to token address for wrapped ERC20)
    function getUnderlyingToken(uint256 id) external pure returns (address) {
        address token = address(uint160(id));
        if (uint256(uint160(token)) != id) revert INVALID_TOKEN_ID(id);
        return token;
    }

    /**
     * @notice Deposit underlying assets on Compound and issue share token
     * @param amount Underlying token amount to deposit
     * @return shareAmount cToken amount
     */
    function deposit(address token, uint256 amount)
        external
        override
        nonReentrant
        returns (uint256 shareAmount)
    {
        if (amount == 0) revert ZERO_AMOUNT();
        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        shareAmount = uBalanceAfter - uBalanceBefore;
        _mint(msg.sender, uint256(uint160(token)), shareAmount, "");

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /**
     * @notice Withdraw underlying assets from Compound
     * @param shareAmount Amount of cTokens to redeem
     * @return withdrawAmount Amount of underlying assets withdrawn
     */
    function withdraw(address token, uint256 shareAmount)
        external
        override
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        if (shareAmount == 0) revert ZERO_AMOUNT();
        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        _burn(msg.sender, uint256(uint160(token)), shareAmount);
        withdrawAmount = shareAmount;

        // Cut withdraw fee if it is in withdrawVaultFee Window (2 months)
        if (
            block.timestamp <
            config.withdrawVaultFeeWindowStartTime() +
                config.withdrawVaultFeeWindow()
        ) {
            uint256 fee = (withdrawAmount * config.withdrawVaultFee()) /
                DENOMINATOR;
            uToken.safeTransfer(config.treasury(), fee);
            withdrawAmount -= fee;
        }
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }
}
