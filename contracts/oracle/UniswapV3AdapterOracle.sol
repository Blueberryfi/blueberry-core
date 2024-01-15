// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.22;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { UniV3WrappedLibContainer } from "../libraries/UniV3/UniV3WrappedLibContainer.sol";
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseAdapter } from "./BaseAdapter.sol";
import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @author BlueberryProtocol
 * @title Uniswap V3 Adapter Oracle
 * @notice Oracle contract which provides price feeds of tokens from Uni V3 pool paired with stablecoins
 */
contract UniswapV3AdapterOracle is IBaseOracle, UsingBaseOracle, BaseAdapter {
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new stablecoin pool is set
    event SetPoolStable(address token, address pool);

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Mapping from token address to Uni V3 pool of token/(USDT|USDC|DAI) pair
    mapping(address => address) private _stablePools;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(IBaseOracle base) UsingBaseOracle(base) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set stablecoin pools for multiple tokens
     * @param tokens list of tokens to set stablecoin pool references
     * @param pools list of reference pool addresses
     */
    function setStablePools(address[] calldata tokens, address[] calldata pools) external onlyOwner {
        uint256 tokenLength = tokens.length;
        if (tokenLength != pools.length) revert Errors.INPUT_ARRAY_MISMATCH();

        for (uint256 i = 0; i < tokenLength; ++i) {
            if (tokens[i] == address(0) || pools[i] == address(0)) revert Errors.ZERO_ADDRESS();
            if (tokens[i] != IUniswapV3Pool(pools[i]).token0() && tokens[i] != IUniswapV3Pool(pools[i]).token1()) {
                revert Errors.NO_STABLEPOOL(pools[i]);
            }

            _stablePools[tokens[i]] = pools[i];
            emit SetPoolStable(tokens[i], pools[i]);
        }
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external override returns (uint256) {
        /// Maximum cap of timeGap is 2 days(172,800), safe to convert
        uint32 secondsAgo = _timeGaps[token].toUint32();
        if (secondsAgo == 0) revert Errors.NO_MEAN(token);

        address stablePool = getStablePool(token);
        if (stablePool == address(0)) revert Errors.NO_STABLEPOOL(token);

        address poolToken0 = IUniswapV3Pool(stablePool).token0();
        address poolToken1 = IUniswapV3Pool(stablePool).token1();
        address stablecoin = poolToken0 == token ? poolToken1 : poolToken0; // get stable token address

        uint8 stableDecimals = IERC20Metadata(stablecoin).decimals();
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        (int24 arithmeticMeanTick, ) = UniV3WrappedLibContainer.consult(stablePool, secondsAgo);
        uint256 quoteTokenAmountForStable = UniV3WrappedLibContainer.getQuoteAtTick(
            arithmeticMeanTick,
            uint256(10 ** tokenDecimals).toUint128(),
            token,
            stablecoin
        );

        return (quoteTokenAmountForStable * _base.getPrice(stablecoin)) / 10 ** stableDecimals;
    }

    /**
     * @notice Get the stable pool for a given token
     * @param token The address of the token to get the stable pool for
     * @return The address of the stable pool
     */
    function getStablePool(address token) public view returns (address) {
        return _stablePools[token];
    }
}
