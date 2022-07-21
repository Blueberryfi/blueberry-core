pragma solidity ^0.8.9;

// import 'OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/SafeERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/math/SafeMath.sol';

import '../../interfaces/ICErc20_2.sol';

contract MockCErc20_2 is ICErc20_2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public mintRate = 1e18;
    uint256 public totalSupply = 0;
    mapping(address => uint256) public override balanceOf;

    constructor(IERC20 _token) public {
        token = _token;
    }

    function setMintRate(uint256 _mintRate) external override {
        mintRate = _mintRate;
    }

    function underlying() external override returns (address) {
        return address(token);
    }

    function mint(uint256 mintAmount) external override returns (uint256) {
        uint256 amountIn = mintAmount.mul(mintRate).div(1e18);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amountIn);
        totalSupply = totalSupply.add(mintAmount);
        balanceOf[msg.sender] = balanceOf[msg.sender].add(mintAmount);
        return 0;
    }

    function redeem(uint256 redeemAmount) external override returns (uint256) {
        uint256 amountOut = redeemAmount.mul(1e18).div(mintRate);
        IERC20(token).safeTransfer(msg.sender, amountOut);
        totalSupply = totalSupply.sub(redeemAmount);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(redeemAmount);
        return 0;
    }
}
