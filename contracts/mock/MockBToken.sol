// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBToken is ERC20("Mock", "Mock") {
    address public underlying;
    mapping(address => uint256) public borrowBalanceStored;

    constructor(address _underlying) {
        underlying = _underlying;
    }

    function borrowBalanceCurrent(address account) external view returns (uint256) {
        return borrowBalanceStored[account];
    }

    function borrow(uint256 borrowAmount) external returns (uint256) {
        IERC20(underlying).transfer(msg.sender, borrowAmount);
        borrowBalanceStored[msg.sender] += borrowAmount;
    }

    function repayBorrow(uint256 repayAmount) external returns (uint256) {
        IERC20(underlying).transferFrom(msg.sender, address(this), repayAmount);
        borrowBalanceStored[msg.sender] -= repayAmount;
    }

    function mint(uint256 mintAmount) external returns (uint256) {
        _mint(msg.sender, mintAmount);
        IERC20(underlying).transferFrom(msg.sender, address(this), mintAmount);
        return 0;
    }

    function exchangeRateStored() external pure returns (uint256) {
        return 1e18;
    }
}
