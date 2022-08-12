// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './WhitelistSpell.sol';
import '../utils/BBMath.sol';
import '../interfaces/IUniswapV2Factory.sol';
import '../interfaces/IUniswapV2Router02.sol';
import '../interfaces/IUniswapV2Pair.sol';
import '../interfaces/IWMasterChef.sol';

contract SushiswapSpellV1 is WhitelistSpell {
    using BBMath for uint256;

    IUniswapV2Factory public immutable factory; // Sushiswap factory
    IUniswapV2Router02 public immutable router; // Sushiswap router

    /// @dev Mapping from tokenA to (mapping from tokenB to LP token)
    mapping(address => mapping(address => address)) public pairs;

    IWMasterChef public immutable wmasterchef; // Wrapped masterChef

    address public immutable sushi; // Sushi token address

    constructor(
        IBank _bank,
        address _werc20,
        IUniswapV2Router02 _router,
        address _wmasterchef
    ) WhitelistSpell(_bank, _werc20, _router.WETH()) {
        router = _router;
        factory = IUniswapV2Factory(_router.factory());
        wmasterchef = IWMasterChef(_wmasterchef);
        IWMasterChef(_wmasterchef).setApprovalForAll(address(_bank), true);
        sushi = address(IWMasterChef(_wmasterchef).sushi());
    }

    /// @dev Return the LP token for the token pairs (can be in any order)
    /// @param tokenA Token A to get LP token
    /// @param tokenB Token B to get LP token
    function getAndApprovePair(address tokenA, address tokenB)
        public
        returns (address)
    {
        address lp = pairs[tokenA][tokenB];
        if (lp == address(0)) {
            lp = factory.getPair(tokenA, tokenB);
            require(lp != address(0), 'no lp token');
            ensureApprove(tokenA, address(router));
            ensureApprove(tokenB, address(router));
            ensureApprove(lp, address(router));
            pairs[tokenA][tokenB] = lp;
            pairs[tokenB][tokenA] = lp;
        }
        return lp;
    }

    /// @dev Compute optimal deposit amount
    /// @param amtA amount of token A desired to deposit
    /// @param amtB amount of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    function optimalDeposit(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256 swapAmt, bool isReversed) {
        if (amtA * resB >= amtB * resA) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    /// @dev Compute optimal deposit amount helper.
    /// @param amtA amount of token A desired to deposit
    /// @param amtB amount of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    /// Formula: https://blog.alphafinance.io/byot/
    function _optimalDepositA(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256) {
        require(amtA * resB >= amtB * resA, 'Reversed');
        uint256 a = 997;
        uint256 b = 1997 * resA;
        uint256 _c = (amtA * resB) - (amtB * resA);
        uint256 c = (_c * 1000 * resA) / (amtB + resB);
        uint256 d = a * c * 4;
        uint256 e = BBMath.sqrt(b * b + d);
        uint256 numerator = e - b;
        uint256 denominator = a * 2;
        return numerator / denominator;
    }

    struct Amounts {
        uint256 amtAUser; // Supplied tokenA amount
        uint256 amtBUser; // Supplied tokenB amount
        uint256 amtLPUser; // Supplied LP token amount
        uint256 amtABorrow; // Borrow tokenA amount
        uint256 amtBBorrow; // Borrow tokenB amount
        uint256 amtLPBorrow; // Borrow LP token amount
        uint256 amtAMin; // Desired tokenA amount (slippage control)
        uint256 amtBMin; // Desired tokenB amount (slippage control)
    }

    /// @dev Add liquidity to Sushiswap pool
    /// @param tokenA Token A for the pair
    /// @param tokenB Token B for the pair
    /// @param amt Amounts of tokens to supply, borrow, and get.
    function addLiquidityInternal(
        address tokenA,
        address tokenB,
        Amounts calldata amt,
        address lp
    ) internal {
        require(whitelistedLpTokens[lp], 'lp token not whitelisted');

        // 1. Get user input amounts
        doTransmitETH();
        doTransmit(tokenA, amt.amtAUser);
        doTransmit(tokenB, amt.amtBUser);
        doTransmit(lp, amt.amtLPUser);

        // 2. Borrow specified amounts
        doBorrow(tokenA, amt.amtABorrow);
        doBorrow(tokenB, amt.amtBBorrow);
        doBorrow(lp, amt.amtLPBorrow);

        // 3. Calculate optimal swap amount
        uint256 swapAmt;
        bool isReversed;
        {
            uint256 amtA = IERC20(tokenA).balanceOf(address(this));
            uint256 amtB = IERC20(tokenB).balanceOf(address(this));
            uint256 resA;
            uint256 resB;
            if (IUniswapV2Pair(lp).token0() == tokenA) {
                (resA, resB, ) = IUniswapV2Pair(lp).getReserves();
            } else {
                (resB, resA, ) = IUniswapV2Pair(lp).getReserves();
            }
            (swapAmt, isReversed) = optimalDeposit(amtA, amtB, resA, resB);
        }

        // 4. Swap optimal amount
        if (swapAmt > 0) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = isReversed
                ? (tokenB, tokenA)
                : (tokenA, tokenB);
            router.swapExactTokensForTokens(
                swapAmt,
                0,
                path,
                address(this),
                block.timestamp
            );
        }

        // 5. Add liquidity
        uint256 balA = IERC20(tokenA).balanceOf(address(this));
        uint256 balB = IERC20(tokenB).balanceOf(address(this));
        if (balA > 0 || balB > 0) {
            router.addLiquidity(
                tokenA,
                tokenB,
                balA,
                balB,
                amt.amtAMin,
                amt.amtBMin,
                address(this),
                block.timestamp
            );
        }
    }

    /// @dev Add liquidity to Sushiswap pool, with no staking rewards (use WERC20 wrapper)
    /// @param tokenA Token A for the pair
    /// @param tokenB Token B for the pair
    /// @param amt Amounts of tokens to supply, borrow, and get.
    function addLiquidityWERC20(
        address tokenA,
        address tokenB,
        Amounts calldata amt
    ) external payable {
        address lp = getAndApprovePair(tokenA, tokenB);
        // 1-5. add liquidity
        addLiquidityInternal(tokenA, tokenB, amt, lp);

        // 6. Put collateral
        doPutCollateral(lp, IERC20(lp).balanceOf(address(this)));

        // 7. Refund leftovers to users
        doRefundETH();
        doRefund(tokenA);
        doRefund(tokenB);
    }

    /// @dev Add liquidity to Sushiswap pool, with staking to masterChef
    /// @param tokenA Token A for the pair
    /// @param tokenB Token B for the pair
    /// @param amt Amounts of tokens to supply, borrow, and get.
    /// @param pid Pool id
    function addLiquidityWMasterChef(
        address tokenA,
        address tokenB,
        Amounts calldata amt,
        uint256 pid
    ) external payable {
        address lp = getAndApprovePair(tokenA, tokenB);
        (address lpToken, , , ) = wmasterchef.chef().poolInfo(pid);
        require(lpToken == lp, 'incorrect lp token');

        // 1-5. add liquidity
        addLiquidityInternal(tokenA, tokenB, amt, lp);

        // 6. Take out collateral
        (, address collToken, uint256 collId, uint256 collSize) = bank
            .getCurrentPositionInfo();
        if (collSize > 0) {
            (uint256 decodedPid, ) = wmasterchef.decodeId(collId);
            require(pid == decodedPid, 'incorrect pid');
            require(
                collToken == address(wmasterchef),
                'collateral token & wmasterchef mismatched'
            );
            bank.takeCollateral(address(wmasterchef), collId, collSize);
            wmasterchef.burn(collId, collSize);
        }

        // 7. Put collateral
        ensureApprove(lp, address(wmasterchef));
        uint256 amount = IERC20(lp).balanceOf(address(this));
        uint256 id = wmasterchef.mint(pid, amount);
        bank.putCollateral(address(wmasterchef), id, amount);

        // 8. Refund leftovers to users
        doRefundETH();
        doRefund(tokenA);
        doRefund(tokenB);

        // 9. Refund sushi
        doRefund(sushi);
    }

    struct RepayAmounts {
        uint256 amtLPTake; // Take out LP token amount (from BlueBerry)
        uint256 amtLPWithdraw; // Withdraw LP token amount (back to caller)
        uint256 amtARepay; // Repay tokenA amount
        uint256 amtBRepay; // Repay tokenB amount
        uint256 amtLPRepay; // Repay LP token amount
        uint256 amtAMin; // Desired tokenA amount
        uint256 amtBMin; // Desired tokenB amount
    }

    /// @dev Remove liquidity from Sushiswap pool
    /// @param tokenA Token A for the pair
    /// @param tokenB Token B for the pair
    /// @param amt Amounts of tokens to take out, withdraw, repay, and get.
    function removeLiquidityInternal(
        address tokenA,
        address tokenB,
        RepayAmounts calldata amt,
        address lp
    ) internal {
        require(whitelistedLpTokens[lp], 'lp token not whitelisted');
        uint256 positionId = bank.POSITION_ID();

        uint256 amtARepay = amt.amtARepay;
        uint256 amtBRepay = amt.amtBRepay;
        uint256 amtLPRepay = amt.amtLPRepay;

        // 2. Compute repay amount if MAX_INT is supplied (max debt)
        if (amtARepay == type(uint256).max) {
            amtARepay = bank.borrowBalanceCurrent(positionId, tokenA);
        }
        if (amtBRepay == type(uint256).max) {
            amtBRepay = bank.borrowBalanceCurrent(positionId, tokenB);
        }
        if (amtLPRepay == type(uint256).max) {
            amtLPRepay = bank.borrowBalanceCurrent(positionId, lp);
        }

        // 3. Compute amount to actually remove
        uint256 amtLPToRemove = IERC20(lp).balanceOf(address(this)) -
            amt.amtLPWithdraw;

        // 4. Remove liquidity
        uint256 amtA;
        uint256 amtB;
        if (amtLPToRemove > 0) {
            (amtA, amtB) = router.removeLiquidity(
                tokenA,
                tokenB,
                amtLPToRemove,
                0,
                0,
                address(this),
                block.timestamp
            );
        }

        // 5. MinimizeTrading
        uint256 amtADesired = amtARepay + amt.amtAMin;
        uint256 amtBDesired = amtBRepay + amt.amtBMin;

        if (amtA < amtADesired && amtB > amtBDesired) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = (tokenB, tokenA);
            router.swapTokensForExactTokens(
                amtADesired - amtA,
                amtB - amtBDesired,
                path,
                address(this),
                block.timestamp
            );
        } else if (amtA > amtADesired && amtB < amtBDesired) {
            address[] memory path = new address[](2);
            (path[0], path[1]) = (tokenA, tokenB);
            router.swapTokensForExactTokens(
                amtBDesired - amtB,
                amtA - amtADesired,
                path,
                address(this),
                block.timestamp
            );
        }

        // 6. Repay
        doRepay(tokenA, amtARepay);
        doRepay(tokenB, amtBRepay);
        doRepay(lp, amtLPRepay);

        // 7. Slippage control
        require(IERC20(tokenA).balanceOf(address(this)) >= amt.amtAMin);
        require(IERC20(tokenB).balanceOf(address(this)) >= amt.amtBMin);
        require(IERC20(lp).balanceOf(address(this)) >= amt.amtLPWithdraw);

        // 8. Refund leftover
        doRefundETH();
        doRefund(tokenA);
        doRefund(tokenB);
        doRefund(lp);
    }

    /// @dev Remove liquidity from Sushiswap pool, with no staking rewards (use WERC20 wrapper)
    /// @param tokenA Token A for the pair
    /// @param tokenB Token B for the pair
    /// @param amt Amounts of tokens to take out, withdraw, repay, and get.
    function removeLiquidityWERC20(
        address tokenA,
        address tokenB,
        RepayAmounts calldata amt
    ) external {
        address lp = getAndApprovePair(tokenA, tokenB);

        // 1. Take out collateral
        doTakeCollateral(lp, amt.amtLPTake);

        // 2-8. remove liquidity
        removeLiquidityInternal(tokenA, tokenB, amt, lp);
    }

    /// @dev Remove liquidity from Sushiswap pool, from masterChef staking
    /// @param tokenA Token A for the pair
    /// @param tokenB Token B for the pair
    /// @param amt Amounts of tokens to take out, withdraw, repay, and get.
    function removeLiquidityWMasterChef(
        address tokenA,
        address tokenB,
        RepayAmounts calldata amt
    ) external {
        address lp = getAndApprovePair(tokenA, tokenB);
        (, address collToken, uint256 collId, ) = bank.getCurrentPositionInfo();
        require(
            IWMasterChef(collToken).getUnderlyingToken(collId) == lp,
            'incorrect underlying'
        );
        require(
            collToken == address(wmasterchef),
            'collateral token & wmasterchef mismatched'
        );

        // 1. Take out collateral
        bank.takeCollateral(address(wmasterchef), collId, amt.amtLPTake);
        wmasterchef.burn(collId, amt.amtLPTake);

        // 2-8. remove liquidity
        removeLiquidityInternal(tokenA, tokenB, amt, lp);

        // 9. Refund sushi
        doRefund(sushi);
    }

    /// @dev Harvest SUSHI reward tokens to in-exec position's owner
    function harvestWMasterChef() external {
        (, address collToken, uint256 collId, ) = bank.getCurrentPositionInfo();
        (uint256 pid, ) = wmasterchef.decodeId(collId);
        address lp = wmasterchef.getUnderlyingToken(collId);
        require(whitelistedLpTokens[lp], 'lp token not whitelisted');
        require(
            collToken == address(wmasterchef),
            'collateral token & wmasterchef mismatched'
        );

        // 1. Take out collateral
        bank.takeCollateral(address(wmasterchef), collId, type(uint256).max);
        wmasterchef.burn(collId, type(uint256).max);

        // 2. put collateral
        uint256 amount = IERC20(lp).balanceOf(address(this));
        ensureApprove(lp, address(wmasterchef));
        uint256 id = wmasterchef.mint(pid, amount);
        bank.putCollateral(address(wmasterchef), id, amount);

        // 3. Refund sushi
        doRefund(sushi);
    }
}
