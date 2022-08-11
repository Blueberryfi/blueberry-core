// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/MerkleProof.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import './Governable.sol';
import './interfaces/ICErc20.sol';
import './interfaces/UniV3/IUniswapV3Pool.sol';
import './interfaces/UniV3/ISwapRouter02.sol';
import './interfaces/UniV3/IUniswapV3PositionsNFT.sol';
import './interfaces/IWETH.sol';
import './libraries/UniV3/PoolActions.sol';

contract SafeBoxUniV3LP is Governable, ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolVariables for IUniswapV3Pool;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV3PositionsNFT public nftManager =
        IUniswapV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant uniV3Router =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    IUniswapV3Pool public pool;
    IERC20 public token0;
    IERC20 public token1;

    int24 public tick_lower;
    int24 public tick_upper;

    uint256 public tokenId;
    int24 public l_tick_lower;
    int24 public l_tick_upper;
    int24 private tickSpacing;
    int24 private tickRangeMultiplier;
    uint24 public swapPoolFee;
    uint24 private twapTime = 60;

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

    function totalLiquidity() public view returns (uint256) {
        return liquidityOfThis() + liquidityOfPool();
    }

    function liquidityOfPool() public view returns (uint256) {
        (, , , , , , , uint128 _liquidity, , , , ) = nftManager.positions(
            tokenId
        );
        return _liquidity;
    }

    function liquidityOfThis() public view returns (uint256) {
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

    function deposit(uint256 token0Amount, uint256 token1Amount)
        external
        payable
        nonReentrant
    {
        bool isEth;
        uint256 _ethAmount = address(this).balance;
        if (_ethAmount > 0) {
            IWETH(WETH).deposit{value: _ethAmount}();
            isEth = true;
            token1Amount = _ethAmount;
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
                uint256 _refundAmount = _ethAmount - token1Amount;
                IWETH(WETH).withdraw(_refundAmount);
                (bool sent, ) = (msg.sender).call{value: _refundAmount}('');
                require(sent, 'Failed to refund Ether');
            }
        }

        uint256 _poolAmount = totalLiquidity();
        uint256 _liquidityAmount = uint256(
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
            shares = _liquidityAmount;
        } else {
            shares = (_liquidityAmount * totalSupply()) / _poolAmount;
        }

        _mint(msg.sender, shares);
        if (tokenId == 0) {
            rebalance();
        } else {
            _deposit();
        }
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public nonReentrant {
        uint256 r = (totalLiquidity() * _shares) / totalSupply();
        (uint256 _expectA0, uint256 _expectA1) = pool.amountsForLiquidity(
            uint128(r),
            tick_lower,
            tick_upper
        );
        _burn(msg.sender, _shares);

        uint256[2] memory _balances = [
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        ];
        uint256 b = liquidityOfThis();
        if (b < r) {
            uint256 _withdraw = r - b;
            (uint256 _a0, uint256 _a1) = _withdrawLiquidity(_withdraw);
            _expectA0 = _balances[0] + _a0;
            _expectA1 = _balances[1] + _a1;
        }

        token0.safeTransfer(msg.sender, _expectA0);
        token1.safeTransfer(msg.sender, _expectA1);
    }

    function _withdrawLiquidity(uint256 _liquidity)
        public
        returns (uint256 a0, uint256 a1)
    {
        if (_liquidity == 0) return (0, 0);

        (uint256 _a0Expect, uint256 _a1Expect) = pool.amountsForLiquidity(
            uint128(_liquidity),
            l_tick_lower,
            l_tick_upper
        );
        (uint256 amount0, uint256 amount1) = nftManager.decreaseLiquidity(
            IUniswapV3PositionsNFT.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: uint128(_liquidity),
                amount0Min: _a0Expect,
                amount1Min: _a1Expect,
                deadline: block.timestamp + 300
            })
        );

        nftManager.collect(
            IUniswapV3PositionsNFT.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );

        return (amount0, amount1);
    }

    function _deposit() internal {
        if (liquidityOfThis() == 0) return;

        uint256 _balance0 = token0.balanceOf(address(this));
        uint256 _balance1 = token1.balanceOf(address(this));

        if (_balance0 > 0 && _balance1 > 0) {
            nftManager.increaseLiquidity(
                IUniswapV3PositionsNFT.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: _balance0,
                    amount1Desired: _balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                })
            );
        }
    }

    function rebalance() public returns (uint256 _tokenId) {
        if (tokenId != 0) {
            uint256 _initToken0 = token0.balanceOf(address(this));
            uint256 _initToken1 = token1.balanceOf(address(this));
            (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(
                tokenId
            );
            (uint256 _liqAmt0, uint256 _liqAmt1) = nftManager.decreaseLiquidity(
                IUniswapV3PositionsNFT.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: uint128(_liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 300
                })
            );

            nftManager.collect(
                IUniswapV3PositionsNFT.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

            nftManager.sweepToken(address(token0), 0, address(this));
            nftManager.sweepToken(address(token1), 0, address(this));
            nftManager.burn(tokenId);

            _distributePerformanceFees(
                token0.balanceOf(address(this)) - _liqAmt0 - _initToken0,
                token1.balanceOf(address(this)) - _liqAmt1 - _initToken1
            );
        }

        (int24 _tickLower, int24 _tickUpper) = determineTicks();
        _balanceProportion(_tickLower, _tickUpper);

        uint256 _amount0Desired = token0.balanceOf(address(this));
        uint256 _amount1Desired = token1.balanceOf(address(this));

        (_tokenId, , , ) = nftManager.mint(
            IUniswapV3PositionsNFT.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: pool.fee(),
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount0Desired: _amount0Desired,
                amount1Desired: _amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 300
            })
        );

        tokenId = _tokenId;
        // tick_lower = _tickLower; // TODO: Check if this is required
        // tick_upper = _tickUpper; // TODO: Check if this is required
        l_tick_lower = _tickLower; // TODO: Check if this is required
        l_tick_upper = _tickUpper; // TODO: Check if this is required

        // TODO: Emit an event
    }

    function _balanceProportion(int24 _tickLower, int24 _tickUpper) internal {
        PoolVariables.Info memory _cache;

        _cache.amount0Desired = token0.balanceOf(address(this));
        _cache.amount1Desired = token1.balanceOf(address(this));

        _cache.liquidity = pool.liquidityForAmounts(
            _cache.amount0Desired,
            _cache.amount1Desired,
            _tickLower,
            _tickUpper
        );

        (_cache.amount0, _cache.amount1) = pool.amountsForLiquidity(
            _cache.liquidity,
            _tickLower,
            _tickUpper
        );

        bool _zeroForOne;
        if (_cache.amount1Desired == 0) {
            _zeroForOne = true;
        } else {
            _zeroForOne = PoolVariables.amountsDirection(
                _cache.amount0Desired,
                _cache.amount1Desired,
                _cache.amount0,
                _cache.amount1
            );
        }

        uint256 _amountSpecified = _zeroForOne
            ? (_cache.amount0Desired - _cache.amount0) / 2
            : (_cache.amount1Desired - _cache.amount1) / 2;

        if (_amountSpecified > 0) {
            address _inputToken = _zeroForOne
                ? address(token0)
                : address(token1);

            IERC20(_inputToken).safeApprove(uniV3Router, 0);
            IERC20(_inputToken).safeApprove(uniV3Router, _amountSpecified);

            ISwapRouter02(uniV3Router).exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                    tokenIn: _inputToken,
                    tokenOut: _zeroForOne ? address(token1) : address(token0),
                    fee: swapPoolFee,
                    recipient: address(this),
                    amountIn: _amountSpecified,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function _distributePerformanceFees(uint256 _amount0, uint256 _amount1)
        internal
    {}

    function determineTicks() public view returns (int24, int24) {
        uint32[] memory observeTime = new uint32[](2);
        observeTime[0] = twapTime;
        observeTime[1] = 0;
        (int56[] memory cumulativeTicks, ) = pool.observe(observeTime);
        int56 averageTick = (cumulativeTicks[1] - cumulativeTicks[1]) /
            int24(twapTime);
        int24 baseThreshold = tickSpacing * tickRangeMultiplier;
        return
            PoolVariables.baseTicks(
                int24(averageTick),
                baseThreshold,
                tickSpacing
            );
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

    function getRatio() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (totalLiquidity() * 1e18) / totalSupply();
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
