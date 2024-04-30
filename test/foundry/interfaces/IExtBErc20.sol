// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IExtBErc20 {
    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    function balanceOf(address user) external view returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);

    function exchangeRateCurrent() external returns (uint256);

    function getCash() external view returns (uint256);
}
