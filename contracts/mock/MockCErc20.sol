pragma solidity ^0.8.9;

import 'OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol';

import '../../interfaces/ICErc20.sol';

contract MockCErc20 is ICErc20 {
    using SafeMath for uint256;

    IERC20 public token;
    uint256 public interestPerYear = 10e16; // 10% per year

    mapping(address => uint256) public borrows;
    mapping(address => uint256) public lastBlock;

    constructor(IERC20 _token) public {
        token = _token;
    }

    function decimals() external override returns (uint8) {
        return 8;
    }

    function underlying() external override returns (address) {
        return address(token);
    }

    function mint(uint256 mintAmount) external override returns (uint256) {
        // Not implemented
        return 0;
    }

    function redeem(uint256 redeemTokens) external override returns (uint256) {
        // Not implemented
        return 0;
    }

    function balanceOf(address user) external view override returns (uint256) {
        // Not implemented
        return 0;
    }

    function borrowBalanceCurrent(address account)
        public
        override
        returns (uint256)
    {
        uint256 timePast = now - lastBlock[account];
        if (timePast > 0) {
            uint256 interest = borrows[account]
                .mul(interestPerYear)
                .div(100e16)
                .mul(timePast)
                .div(365 days);
            borrows[account] = borrows[account].add(interest);
            lastBlock[account] = now;
        }
        return borrows[account];
    }

    function borrowBalanceStored(address account)
        external
        view
        override
        returns (uint256)
    {
        return borrows[account];
    }

    function borrow(uint256 borrowAmount) external override returns (uint256) {
        borrowBalanceCurrent(msg.sender);
        token.transfer(msg.sender, borrowAmount);
        borrows[msg.sender] = borrows[msg.sender].add(borrowAmount);
        return 0;
    }

    function repayBorrow(uint256 repayAmount)
        external
        override
        returns (uint256)
    {
        borrowBalanceCurrent(msg.sender);
        token.transferFrom(msg.sender, address(this), repayAmount);
        borrows[msg.sender] = borrows[msg.sender].sub(repayAmount);
        return 0;
    }
}
