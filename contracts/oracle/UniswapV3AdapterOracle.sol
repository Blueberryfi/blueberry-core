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
                                      STRUCTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to ICHI Vaults
     * @param token0 Address of token0
     * @param token1 Address of token1
     * @param stablePool Address of stable pool
     * @param token0Decimals Decimals of token0
     * @param token1Decimals Decimals of token1
     */
    struct TokenInfo {
        address token0;
        address token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
        address stablePool;
    }

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
    /// @dev Mapping of a token address to token info
    mapping(address => TokenInfo) private _tokenInfo;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IBaseOracle base, address owner) external initializer {
        __UsingBaseOracle_init(base, owner);
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        TokenInfo memory tokenInfo = getTokenInfo(token);
        address stablePool = tokenInfo.stablePool;
        if (stablePool == address(0)) revert Errors.ORACLE_NOT_SUPPORT_LP(token);

        /// Maximum cap of timeGap is 2 days(172,800), safe to convert
        uint32 secondsAgo = _timeGaps[token].toUint32();
        if (secondsAgo == 0) revert Errors.NO_MEAN(token);

        address poolToken0 = tokenInfo.token0;
        address poolToken1 = tokenInfo.token1;

        address stablecoin;
        uint8 stableDecimals;
        uint8 tokenDecimals;

        if (poolToken0 == token) {
            stablecoin = poolToken1;
            stableDecimals = tokenInfo.token1Decimals;
            tokenDecimals = tokenInfo.token0Decimals;
        } else {
            stablecoin = poolToken0;
            stableDecimals = tokenInfo.token0Decimals;
            tokenDecimals = tokenInfo.token1Decimals;
        }

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
     * @notice Register uniswap V3 pool to oracle
     * @param token Address of the token to register
     */
    function registerToken(address token) external onlyOwner {
        if (token == address(0)) revert Errors.ZERO_ADDRESS();

        address stablePool = getStablePool(token);
        if (stablePool == address(0)) revert Errors.NO_STABLEPOOL(token);

        address token0 = IUniswapV3Pool(stablePool).token0();
        address token1 = IUniswapV3Pool(stablePool).token1();

        _tokenInfo[token] = TokenInfo({
            token0: token0,
            token1: token1,
            token0Decimals: IERC20Metadata(token0).decimals(),
            token1Decimals: IERC20Metadata(token1).decimals(),
            stablePool: stablePool
        });

        emit RegisterLpToken(stablePool);
    }

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

    /**
     * @notice Get the stable pool for a given token
     * @param token The address of the token to get the stable pool for
     * @return The address of the stable pool
     */
    function getStablePool(address token) public view returns (address) {
        return _stablePools[token];
    }

    /**
     * @notice Get token info of the pair
     * @param pair Address of the Uniswap V2 pair
     * @return tokenInfo Token info of the pair
     */
    function getTokenInfo(address pair) public view returns (TokenInfo memory) {
        return _tokenInfo[pair];
    }
}
