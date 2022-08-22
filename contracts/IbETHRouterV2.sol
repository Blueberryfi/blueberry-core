// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './utils/BBMath.sol';

interface IbETHRouterV2IbETHv2 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

interface IbETHRouterV2UniswapPair is IERC20 {
    function token0() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

interface IbETHRouterV2UniswapRouter {
    function factory() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IbETHRouterV2UniswapFactory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address);
}

contract IbETHRouterV2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable blueberry;
    IbETHRouterV2IbETHv2 public immutable ibETHv2;
    IbETHRouterV2UniswapPair public immutable lpToken;
    IbETHRouterV2UniswapRouter public immutable router;

    constructor(
        IERC20 _blueberry,
        IbETHRouterV2IbETHv2 _ibETHv2,
        IbETHRouterV2UniswapRouter _router
    ) {
        IbETHRouterV2UniswapPair _lpToken = IbETHRouterV2UniswapPair(
            IbETHRouterV2UniswapFactory(_router.factory()).getPair(
                address(_blueberry),
                address(_ibETHv2)
            )
        );
        blueberry = _blueberry;
        ibETHv2 = _ibETHv2;
        lpToken = _lpToken;
        router = _router;
        IERC20(_blueberry).safeApprove(address(_router), type(uint256).max);
        IERC20(_ibETHv2).safeApprove(address(_router), type(uint256).max);
        IERC20(_lpToken).safeApprove(address(_router), type(uint256).max);
    }

    function optimalDeposit(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256 swapAmt, bool isReversed) {
        if (amtA.mul(resB) >= amtB.mul(resA)) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    function _optimalDepositA(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256) {
        require(amtA.mul(resB) >= amtB.mul(resA), 'Reversed');
        uint256 a = 997;
        uint256 b = uint256(1997).mul(resA);
        uint256 _c = (amtA.mul(resB)).sub(amtB.mul(resA));
        uint256 c = _c.mul(1000).div(amtB.add(resB)).mul(resA);
        uint256 d = a.mul(c).mul(4);
        uint256 e = BBMath.sqrt(b.mul(b).add(d));
        uint256 numerator = e.sub(b);
        uint256 denominator = a.mul(2);
        return numerator.div(denominator);
    }

    function swapExactETHToBLB(
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external payable {
        ibETHv2.deposit{value: msg.value}();
        address[] memory path = new address[](2);
        path[0] = address(ibETHv2);
        path[1] = address(blueberry);
        router.swapExactTokensForTokens(
            ibETHv2.balanceOf(address(this)),
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    function swapExactBLBToETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external {
        blueberry.transferFrom(msg.sender, address(this), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(blueberry);
        path[1] = address(ibETHv2);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            deadline
        );
        ibETHv2.withdraw(ibETHv2.balanceOf(address(this)));
        uint256 ethBalance = address(this).balance;
        require(ethBalance >= amountOutMin, '!amountOutMin');
        (bool success, ) = to.call{value: ethBalance}(new bytes(0));
        require(success, '!eth');
    }

    function addLiquidityETHBLBOptimal(
        uint256 amountBlb,
        uint256 minLp,
        address to,
        uint256 deadline
    ) external payable {
        if (amountBlb > 0)
            blueberry.transferFrom(msg.sender, address(this), amountBlb);
        ibETHv2.deposit{value: msg.value}();
        uint256 amountIbETHv2 = ibETHv2.balanceOf(address(this));
        uint256 swapAmt;
        bool isReversed;
        {
            (uint256 r0, uint256 r1, ) = lpToken.getReserves();
            (uint256 ibETHv2Reserve, uint256 blbReserve) = lpToken.token0() ==
                address(ibETHv2)
                ? (r0, r1)
                : (r1, r0);
            (swapAmt, isReversed) = optimalDeposit(
                amountIbETHv2,
                amountBlb,
                ibETHv2Reserve,
                blbReserve
            );
        }
        if (swapAmt > 0) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = isReversed
                ? (address(blueberry), address(ibETHv2))
                : (address(ibETHv2), address(blueberry));
            router.swapExactTokensForTokens(
                swapAmt,
                0,
                path,
                address(this),
                deadline
            );
        }
        (, , uint256 liquidity) = router.addLiquidity(
            address(blueberry),
            address(ibETHv2),
            blueberry.balanceOf(address(this)),
            ibETHv2.balanceOf(address(this)),
            0,
            0,
            to,
            deadline
        );
        require(liquidity >= minLp, '!minLP');
    }

    function addLiquidityIbETHv2BLBOptimal(
        uint256 amountIbETHv2,
        uint256 amountBlb,
        uint256 minLp,
        address to,
        uint256 deadline
    ) external {
        if (amountBlb > 0)
            blueberry.transferFrom(msg.sender, address(this), amountBlb);
        if (amountIbETHv2 > 0)
            ibETHv2.transferFrom(msg.sender, address(this), amountIbETHv2);
        uint256 swapAmt;
        bool isReversed;
        {
            (uint256 r0, uint256 r1, ) = lpToken.getReserves();
            (uint256 ibETHv2Reserve, uint256 blbReserve) = lpToken.token0() ==
                address(ibETHv2)
                ? (r0, r1)
                : (r1, r0);
            (swapAmt, isReversed) = optimalDeposit(
                amountIbETHv2,
                amountBlb,
                ibETHv2Reserve,
                blbReserve
            );
        }
        if (swapAmt > 0) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = isReversed
                ? (address(blueberry), address(ibETHv2))
                : (address(ibETHv2), address(blueberry));
            router.swapExactTokensForTokens(
                swapAmt,
                0,
                path,
                address(this),
                deadline
            );
        }
        (, , uint256 liquidity) = router.addLiquidity(
            address(blueberry),
            address(ibETHv2),
            blueberry.balanceOf(address(this)),
            ibETHv2.balanceOf(address(this)),
            0,
            0,
            to,
            deadline
        );
        require(liquidity >= minLp, '!minLP');
    }

    function removeLiquidityETHBLB(
        uint256 liquidity,
        uint256 minETH,
        uint256 minBLB,
        address to,
        uint256 deadline
    ) external {
        lpToken.transferFrom(msg.sender, address(this), liquidity);
        router.removeLiquidity(
            address(blueberry),
            address(ibETHv2),
            liquidity,
            minBLB,
            0,
            address(this),
            deadline
        );
        blueberry.transfer(msg.sender, blueberry.balanceOf(address(this)));
        ibETHv2.withdraw(ibETHv2.balanceOf(address(this)));
        uint256 ethBalance = address(this).balance;
        require(ethBalance >= minETH, '!minETH');
        (bool success, ) = to.call{value: ethBalance}(new bytes(0));
        require(success, '!eth');
    }

    function removeLiquidityBLBOnly(
        uint256 liquidity,
        uint256 minBLB,
        address to,
        uint256 deadline
    ) external {
        lpToken.transferFrom(msg.sender, address(this), liquidity);
        router.removeLiquidity(
            address(blueberry),
            address(ibETHv2),
            liquidity,
            0,
            0,
            address(this),
            deadline
        );
        address[] memory path = new address[](2);
        path[0] = address(ibETHv2);
        path[1] = address(blueberry);
        router.swapExactTokensForTokens(
            ibETHv2.balanceOf(address(this)),
            0,
            path,
            address(this),
            deadline
        );
        uint256 blbBalance = blueberry.balanceOf(address(this));
        require(blbBalance >= minBLB, '!minBLB');
        blueberry.transfer(to, blbBalance);
    }

    receive() external payable {
        require(msg.sender == address(ibETHv2), '!ibETHv2');
    }
}
