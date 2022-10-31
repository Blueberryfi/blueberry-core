// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './interfaces/ISafeBox.sol';
import './interfaces/compound/ICErc20.sol';

contract SafeBox is Ownable, ERC20, ReentrancyGuard, ISafeBox {
    using SafeERC20 for IERC20;
    event Claim(address user, uint256 amount);

    ICErc20 public immutable cToken;
    IERC20 public immutable uToken;

    address public bank;
    bytes32 public root;
    mapping(address => uint256) public claimed;

    modifier onlyBank() {
        require(msg.sender == bank, '!bank');
        _;
    }

    constructor(
        ICErc20 _cToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        IERC20 _uToken = IERC20(_cToken.underlying());
        cToken = _cToken;
        uToken = _uToken;
        _uToken.safeApprove(address(_cToken), type(uint256).max);
    }

    function decimals() public view override returns (uint8) {
        return cToken.decimals();
    }

    function setBank(address _bank) external onlyOwner {
        bank = _bank;
    }

    function updateRoot(bytes32 _root) external onlyOwner {
        root = _root;
    }

    function borrow(uint256 amount)
        external
        nonReentrant
        onlyBank
        returns (uint256 borrowAmount)
    {
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        require(cToken.borrow(amount) == 0, 'bad borrow');
        uint256 uBalanceAfter = uToken.balanceOf(address(this));
        borrowAmount = uBalanceAfter - uBalanceBefore;
        uToken.safeTransfer(bank, borrowAmount);
    }

    function repay(uint256 amount)
        external
        nonReentrant
        onlyBank
        returns (uint256 newDebt)
    {
        require(cToken.repayBorrow(amount) == 0, 'bad repay');
        newDebt = cToken.borrowBalanceStored(address(this));
    }

    function _deposit(address account, uint256 amount)
        internal
        returns (uint256 ctokenAmount)
    {
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        uToken.safeTransferFrom(account, address(this), amount);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));
        uint256 cBalanceBefore = cToken.balanceOf(address(this));
        require(cToken.mint(uBalanceAfter - uBalanceBefore) == 0, '!mint');
        uint256 cBalanceAfter = cToken.balanceOf(address(this));
        ctokenAmount = cBalanceAfter - cBalanceBefore;
        _mint(account, ctokenAmount);
    }

    function lend(uint256 amount)
        external
        nonReentrant
        onlyBank
        returns (uint256 lendAmount)
    {
        lendAmount = _deposit(msg.sender, amount);
    }

    function deposit(uint256 amount)
        external
        nonReentrant
        returns (uint256 ctokenAmount)
    {
        ctokenAmount = _deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        _burn(msg.sender, amount);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        require(cToken.redeem(amount) == 0, '!redeem');
        uint256 uBalanceAfter = uToken.balanceOf(address(this));
        withdrawAmount = uBalanceAfter - uBalanceBefore;
        uToken.safeTransfer(msg.sender, withdrawAmount);
    }

    function claim(uint256 totalAmount, bytes32[] memory proof)
        public
        nonReentrant
    {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, totalAmount));
        require(MerkleProof.verify(proof, root, leaf), '!proof');
        uint256 send = totalAmount - claimed[msg.sender];
        claimed[msg.sender] = totalAmount;
        uToken.safeTransfer(msg.sender, send);
        emit Claim(msg.sender, send);
    }

    function adminClaim(uint256 amount) external onlyOwner {
        uToken.safeTransfer(msg.sender, amount);
    }

    function claimAndWithdraw(
        uint256 totalAmount,
        bytes32[] memory proof,
        uint256 withdrawAmount
    ) external {
        claim(totalAmount, proof);
        withdraw(withdrawAmount);
    }
}
