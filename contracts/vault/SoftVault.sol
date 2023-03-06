// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryConst.sol" as Constants;
import "../utils/BlueBerryErrors.sol" as Errors;
import "../interfaces/IProtocolConfig.sol";
import "../interfaces/ISoftVault.sol";
import "../interfaces/compound/ICErc20.sol";

/**
 * @author gmspacex
 * @title Soft Vault
 * @notice Soft Vault is a spot where users lend and borrow tokens through Blueberry Lending Protocol(Compound Fork).
 * @dev SoftVault is communicating with cTokens to lend and borrow underlying tokens from/to Compound fork.
 *      Underlying tokens can be ERC20 tokens listed by Blueberry team, such as USDC, USDT, DAI, WETH, ...
 */
contract SoftVault is
    OwnableUpgradeable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    ISoftVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev address of cToken for underlying token
    ICErc20 public cToken;
    /// @dev address of underlying token
    IERC20Upgradeable public uToken;
    /// @dev address of protocol config
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

    function initialize(
        IProtocolConfig _config,
        ICErc20 _cToken,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC20_init(_name, _symbol);

        if (address(_cToken) == address(0) || address(_config) == address(0))
            revert Errors.ZERO_ADDRESS();

        IERC20Upgradeable _uToken = IERC20Upgradeable(_cToken.underlying());
        config = _config;
        cToken = _cToken;
        uToken = _uToken;
    }

    function decimals() public view override returns (uint8) {
        return cToken.decimals();
    }

    /**
     * @notice Deposit underlying assets on Compound and issue share token
     * @param amount Underlying token amount to deposit
     * @return shareAmount same as cToken amount received
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        returns (uint256 shareAmount)
    {
        if (amount == 0) revert Errors.ZERO_AMOUNT();
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        uint256 cBalanceBefore = cToken.balanceOf(address(this));
        uToken.approve(address(cToken), amount);
        if (cToken.mint(uBalanceAfter - uBalanceBefore) != 0)
            revert Errors.LEND_FAILED(amount);
        uint256 cBalanceAfter = cToken.balanceOf(address(this));

        shareAmount = cBalanceAfter - cBalanceBefore;
        _mint(msg.sender, shareAmount);

        emit Deposited(msg.sender, amount, shareAmount);
    }

    /**
     * @notice Withdraw underlying assets from Compound
     * @dev It cuts vault withdraw fee when you withdraw within the vault withdraw window (2 months)
     * @param shareAmount Amount of cTokens to redeem
     * @return withdrawAmount Amount of underlying assets withdrawn
     */
    function withdraw(uint256 shareAmount)
        external
        override
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        if (shareAmount == 0) revert Errors.ZERO_AMOUNT();

        _burn(msg.sender, shareAmount);

        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        if (cToken.redeem(shareAmount) != 0)
            revert Errors.REDEEM_FAILED(shareAmount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        withdrawAmount = uBalanceAfter - uBalanceBefore;
        uToken.approve(address(config.feeManager()), withdrawAmount);
        withdrawAmount = config.feeManager().doCutVaultWithdrawFee(
            address(uToken),
            withdrawAmount
        );
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, shareAmount);
    }
}
