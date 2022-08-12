// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '../Governable.sol';
import '../interfaces/IERC20Ex.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/UniV3/IUniswapV3Pool.sol';
import '../libraries/UniV3/OracleLibrary.sol';

contract UniswapV3AdapterOracle is IBaseOracle, Governable {
    event SetPoolETH(address token, address pool);
    event SetPoolStable(address token, address pool);
    event SetTimeAgo(address token, uint32 timeAgo);

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    mapping(address => uint32) public timeAgos; // Mapping from token address to elapsed time from checkpoint
    mapping(address => address) public poolsETH; // Mapping from token address to token/ETH pool address
    mapping(address => address) public poolsStable; // Mapping from token address to token/(USDT/USDC/DAI) pool address

    constructor() {
        __Governable__init();
    }

    /// @dev Set price reference for ETH pair
    /// @param tokens list of tokens to set reference
    /// @param pools list of reference pool contract addresses
    function setPoolsETH(address[] calldata tokens, address[] calldata pools)
        external
        onlyGov
    {
        require(
            tokens.length == pools.length,
            'tokens & pools length mismatched'
        );
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            poolsETH[tokens[idx]] = pools[idx];
            emit SetPoolETH(tokens[idx], pools[idx]);
        }
    }

    /// @dev Set price reference for Stable pair
    /// @param tokens list of tokens to set reference
    /// @param pools list of reference pool contract addresses
    function setPoolsStable(address[] calldata tokens, address[] calldata pools)
        external
        onlyGov
    {
        require(
            tokens.length == pools.length,
            'tokens & pools length mismatched'
        );
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            poolsStable[tokens[idx]] = pools[idx];
            emit SetPoolStable(tokens[idx], pools[idx]);
        }
    }

    /// @dev Set timeAgos for each token
    /// @param tokens list of tokens to set timeAgos
    /// @param times list of timeAgos to set to
    function SetTimeAgos(address[] calldata tokens, uint32[] calldata times)
        external
        onlyGov
    {
        require(
            tokens.length == times.length,
            'tokens & times length mismatched'
        );
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            timeAgos[tokens[idx]] = times[idx];
            emit SetTimeAgo(tokens[idx], times[idx]);
        }
    }

    /// @dev Return the value of the given input as ETH per unit, multiplied by 2**112.
    /// @param token The ERC-20 token to check the value.
    function getETHPx(address token) external view override returns (uint256) {
        if (
            token == WETH || token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) return uint256(2**112);
        uint32 secondsAgo = timeAgos[token];
        require(secondsAgo != 0, 'seconds ago not set');

        address poolETH = poolsETH[token];
        if (poolETH != address(0)) {
            return getETHPxFromETHPool(token, poolETH, secondsAgo);
        }

        address poolStable = poolsStable[token];
        if (poolStable != address(0)) {
            (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
                poolStable,
                secondsAgo
            );

            address token0 = IUniswapV3Pool(poolStable).token0();
            address token1 = IUniswapV3Pool(poolStable).token1();
            token1 = token0 == token ? token1 : token0; // get stable token address
            token0 = token;
            address poolETHForStable = poolsStable[token0];
            if (poolETHForStable != address(0)) {
                uint32 secondsAgoForStable = timeAgos[token0];
                require(secondsAgoForStable != 0, 'seconds ago not set');
                uint256 stableDecimals = uint256(IERC20Ex(token0).decimals());
                uint256 tokenDecimals = uint256(IERC20Ex(token).decimals());
                uint256 quoteTokenAmountForStable = OracleLibrary
                    .getQuoteAtTick(
                        arithmeticMeanTick,
                        uint128(10**stableDecimals),
                        token0,
                        token1
                    );
                uint256 quoateStableAmountForETH = getETHPxFromETHPool(
                    token0,
                    poolETHForStable,
                    secondsAgoForStable
                );
                return
                    (quoteTokenAmountForStable * quoateStableAmountForETH) /
                    10**tokenDecimals;
            }
        }

        revert('no valid price pool for token');
    }

    function getETHPxFromETHPool(
        address token,
        address poolETH,
        uint32 secondsAgo
    ) internal view returns (uint256) {
        uint256 decimals = uint256(IERC20Ex(token).decimals());
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(
            poolETH,
            secondsAgo
        );
        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            arithmeticMeanTick,
            1 ether,
            WETH,
            token
        );
        return (quoteAmount * 2**112) / 10**decimals;
    }
}
