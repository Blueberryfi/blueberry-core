// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './Governable.sol';
import './interfaces/ICErc20.sol';
import './interfaces/UniV3/IUniswapV3Pool.sol';
import './interfaces/IWETH.sol';
import './libraries/UniV3/PoolActions.sol';

contract SafeBoxUniV3LP is Governable, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolVariables for IUniswapV3Pool;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IUniswapV3Pool public pool;
    IERC20 public token0;
    IERC20 public token1;

    int24 public tick_lower;
    int24 public tick_upper;

    event Claim(address user, uint256 amount);

    ICErc20 public cToken;
    IERC20 public uToken;

    address public relayer;
    bytes32 public root;
    mapping(address => uint256) public claimed;

    constructor(
        string memory _name,
        string memory _symbol,
        address _pool,
        int24 _tick_lower,
        int24 _tick_upper
    ) ERC20(_name, _symbol) {
        __Governable__init();
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        tick_lower = _tick_lower;
        tick_upper = _tick_upper;

        relayer = msg.sender;
    }

    function setRelayer(address _relayer) external onlyGov {
        relayer = _relayer;
    }

    function updateRoot(bytes32 _root) external {
        require(msg.sender == relayer || msg.sender == governor, '!relayer');
        root = _root;
    }

    function deposit(uint256 token0Amount, uint256 token1Amount)
        external
        payable
        nonReentrant
    {
        bool isEth;
        uint256 ethAmount = address(this).balance;
        if (ethAmount > 0) {
            IWETH(WETH).deposit{value: ethAmount}();
            isEth = true;
            token1Amount = ethAmount;
        }

        uint256 amount0ForAmount1 = (getDepositAmount(
            address(token1),
            token1Amount
        ) * (1e18)) / (getProportion());
        uint256 amount1ForAmount0 = (getDepositAmount(
            address(token0),
            token0Amount
        ) * getProportion()) / 1e18;

        if (token0Amount > amount0ForAmount1) {
            token0Amount = amount0ForAmount1;
        } else {
            token1Amount = amount1ForAmount0;

            if (isEth && address(token1) == WETH) {
                uint256 refundAmount = ethAmount - token1Amount;
                IWETH(WETH).withdraw(refundAmount);
                (bool sent, bytes memory data) = (msg.sender).call{
                    value: refundAmount
                }('');
                require(sent, 'Failed to refund Ether');
            }
        }

        uint256 poolAmount = totalLiquidity();
        uint256 liquidityAmount = uint256(
            pool.liquidityForAmounts(
                token0Amount,
                token1Amount,
                tick_lower,
                tick_upper
            )
        );

        if (token0Amount > 0)
            token0.safeTransferFrom(msg.sender, address(this), token0Amount);
        if (token1Amount > 0 && !isEth)
            token1.safeTransferFrom(msg.sender, address(this), token1Amount);

        uint256 shares;
        if (totalSupply() == 0) {
            shares = liquidityAmount;
        } else {
            shares = (liquidityAmount * totalSupply()) / poolAmount;
        }

        _mint(msg.sender, shares);
    }

    function withdraw(uint256 _shares) public nonReentrant {
        uint256 r = (totalLiquidity() * _shares) / totalSupply();
        (uint256 expectA0, uint256 expectA1) = pool.amountsForLiquidity(
            uint128(r),
            tick_lower,
            tick_upper
        );
        _burn(msg.sender, _shares);

        uint256[2] memory _balances = [
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        ];
        uint256 b = totalLiquidity();
        if (b < r) {
            // TODO
        }

        token0.safeTransfer(msg.sender, expectA0);
        token1.safeTransfer(msg.sender, expectA1);
    }

    function getDepositAmount(address tokenAddr, uint256 amount)
        internal
        view
        returns (uint256 depositAmount)
    {
        if (tokenAddr == WETH) {
            uint256 _weth = IERC20(WETH).balanceOf(address(this));
            if (_weth > 0) {
                depositAmount = _weth;
            } else {
                depositAmount = amount;
            }
        } else {
            depositAmount = amount;
        }
    }

    function getProportion() public view returns (uint256) {
        (uint256 a1, uint256 a2) = pool.amountsForLiquidity(
            1e18,
            tick_lower,
            tick_upper
        );
        return (a2 * (10**18)) / a1;
    }

    function totalLiquidity() public view returns (uint256) {
        uint256 _balance0 = token0.balanceOf(address(this));
        uint256 _balance1 = token1.balanceOf(address(this));
        return
            uint256(
                pool.liquidityForAmounts(
                    _balance0,
                    _balance1,
                    tick_lower,
                    tick_upper
                )
            );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}

    fallback() external payable {}
}
