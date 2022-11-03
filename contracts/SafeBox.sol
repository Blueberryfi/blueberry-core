// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './interfaces/ISafeBox.sol';
import './interfaces/compound/ICErc20.sol';

contract SafeBox is Ownable, ERC20, ReentrancyGuard, ISafeBox {
    using SafeERC20 for IERC20;

    /// @dev address of cToken for underlying token
    ICErc20 public immutable cToken;
    /// @dev address of underlying token
    IERC20 public immutable uToken;

    /// @dev address of Bank contract
    address public bank;

    event Deposited(address indexed account, uint256 amount, uint256 cAmount);
    event Withdrawn(address indexed account, uint256 amount, uint256 cAmount);
    event Borrowed(address indexed account, uint256 amount);
    event Repaid(address indexed account, uint256 amount, uint256 newDebt);

    modifier onlyBank() {
        require(msg.sender == bank, '!bank');
        _;
    }

    constructor(
        ICErc20 _cToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(address(_cToken) != address(0), 'zero address');
        IERC20 _uToken = IERC20(_cToken.underlying());
        cToken = _cToken;
        uToken = _uToken;
        _uToken.safeApprove(address(_cToken), type(uint256).max);
    }

    function decimals() public view override returns (uint8) {
        return cToken.decimals();
    }

    /**
     * @notice Owner privileged function to set bank address
     * @param _bank New bank address
     */
    function setBank(address _bank) external onlyOwner {
        require(_bank != address(0), 'zero address');
        bank = _bank;
    }

    /**
     * @notice Owner privileged function to claim fees
     */
    function adminClaim() external onlyOwner {
        uToken.safeTransfer(owner(), uToken.balanceOf(address(this)));
    }

    /**
     * @notice Borrow underlying assets from Compound
     * @dev Only Bank can call this function
     * @param amount Amount of underlying assets to borrow
     * @return borrowAmount Amount of borrowed assets
     */
    function borrow(uint256 amount)
        external
        override
        nonReentrant
        onlyBank
        returns (uint256 borrowAmount)
    {
        require(amount > 0, 'zero amount');

        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        require(cToken.borrow(amount) == 0, 'bad borrow');
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        borrowAmount = uBalanceAfter - uBalanceBefore;
        uToken.safeTransfer(bank, borrowAmount);

        emit Borrowed(msg.sender, borrowAmount);
    }

    /**
     * @notice Repay debt on Compound
     * @dev Only Bank can call this function
     * @param amount Amount of debt to repay
     * @return newDebt New debt after repay
     */
    function repay(uint256 amount)
        external
        override
        nonReentrant
        onlyBank
        returns (uint256 newDebt)
    {
        require(amount > 0, 'zero amount');
        require(cToken.repayBorrow(amount) == 0, 'bad repay');
        newDebt = cToken.borrowBalanceStored(address(this));

        emit Repaid(msg.sender, amount, newDebt);
    }

    /**
     * @notice Deposit underlying assets on Compound and issue share token
     * @param amount Underlying token amount to deposit
     * @return ctokenAmount cToken amount
     */
    function deposit(uint256 amount)
        external
        override
        nonReentrant
        returns (uint256 ctokenAmount)
    {
        require(amount > 0, 'zero amount');
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        uint256 cBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.mint(uBalanceAfter - uBalanceBefore) == 0, '!mint');
        uint256 cBalanceAfter = cToken.balanceOf(address(this));

        ctokenAmount = cBalanceAfter - cBalanceBefore;
        _mint(msg.sender, ctokenAmount);

        emit Deposited(msg.sender, amount, ctokenAmount);
    }

    /**
     * @notice Withdraw underlying assets from Compound
     * @param cAmount Amount of cTokens to redeem
     * @return withdrawAmount Amount of underlying assets withdrawn
     */
    function withdraw(uint256 cAmount)
        external
        override
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        require(cAmount > 0, 'zero amount');

        _burn(msg.sender, cAmount);

        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        require(cToken.redeem(cAmount) == 0, '!redeem');
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        withdrawAmount = uBalanceAfter - uBalanceBefore;
        uToken.safeTransfer(msg.sender, withdrawAmount);

        emit Withdrawn(msg.sender, withdrawAmount, cAmount);
    }
}
