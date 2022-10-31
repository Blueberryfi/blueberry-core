// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '../interfaces/compound/ICErc20_2.sol';

contract MockCErc20_2 is ICErc20_2 {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public mintRate = 1e18;
    uint256 public totalSupply = 0;
    mapping(address => uint256) public override balanceOf;

    constructor(IERC20 _token) {
        token = _token;
    }

    function setMintRate(uint256 _mintRate) external override {
        mintRate = _mintRate;
    }

    function underlying() external view override returns (address) {
        return address(token);
    }

    function mint(uint256 mintAmount) external override returns (uint256) {
        uint256 amountIn = (mintAmount * mintRate) / 1e18;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amountIn);
        totalSupply = totalSupply + mintAmount;
        balanceOf[msg.sender] = balanceOf[msg.sender] + mintAmount;
        return 0;
    }

    function redeem(uint256 redeemAmount) external override returns (uint256) {
        uint256 amountOut = (redeemAmount * 1e18) / mintRate;
        IERC20(token).safeTransfer(msg.sender, amountOut);
        totalSupply = totalSupply - redeemAmount;
        balanceOf[msg.sender] = balanceOf[msg.sender] - redeemAmount;
        return 0;
    }
}
