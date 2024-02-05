// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface ILiquidityGauge {
    function minter() external view returns (address);

    function crv_token() external view returns (address);

    function lp_token() external view returns (address);

    function balanceOf(address addr) external view returns (uint256);

    function deposit(uint256 value) external;

    function withdraw(uint256 value) external;

    function claimable_tokens(address user) external view returns (uint256);
}
