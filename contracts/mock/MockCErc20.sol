// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../interfaces/compound/ICErc20.sol';

contract MockCErc20 is ICErc20 {
    IERC20 public token;
    uint256 public interestPerYear = 10e16; // 10% per year

    mapping(address => uint256) public borrows;
    mapping(address => uint256) public lastBlock;

    constructor(IERC20 _token) {
        token = _token;
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function underlying() external view override returns (address) {
        return address(token);
    }

    function mint(uint256) external pure override returns (uint256) {
        // Not implemented
        return 0;
    }

    function redeem(uint256) external pure override returns (uint256) {
        // Not implemented
        return 0;
    }

    function balanceOf(address) external pure override returns (uint256) {
        // Not implemented
        return 0;
    }

    function exchangeRateStored() external pure override returns (uint256) {
        return 10**8;
    }

    function borrowBalanceCurrent(address account)
        public
        override
        returns (uint256)
    {
        uint256 timePast = block.timestamp - lastBlock[account];
        if (timePast > 0) {
            uint256 interest = (((borrows[account] * interestPerYear) /
                100e16) * timePast) / 365 days;
            borrows[account] = borrows[account] + interest;
            lastBlock[account] = block.timestamp;
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
        borrows[msg.sender] = borrows[msg.sender] + borrowAmount;
        return 0;
    }

    function repayBorrow(uint256 repayAmount)
        external
        override
        returns (uint256)
    {
        borrowBalanceCurrent(msg.sender);
        token.transferFrom(msg.sender, address(this), repayAmount);
        borrows[msg.sender] = borrows[msg.sender] - repayAmount;
        return 0;
    }
}
