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

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { BaseAdapter } from "./BaseAdapter.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { IAnkrETH } from "../interfaces/IAnkrETH.sol";
import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IAggregatorV3Interface } from "../interfaces/chainlink/IAggregatorV3Interface.sol";
import { IWstETH } from "../interfaces/IWstETH.sol";

/**
 * @title ChainlinkAdapterOracle
 * @dev This Oracle Adapter is for L1 Chains
 * @author BlueberryProtocol
 * @notice This Oracle Adapter leverages Chainlink's decentralized price feeds to provide accurate price data.
 *         It also supports remapping of tokens to their canonical forms (e.g., WBTC to BTC).
 */
contract ChainlinkAdapterOracle is IBaseOracle, BaseAdapter {
    using SafeCast for int256;

    /**
     * @dev Struct to store price feed data.
     * @param feed The address of the Chainlink price feed.
     * @param decimals The number of decimals returned by the Chainlink feed.
     */
    struct PriceFeed {
        address feed;
        uint8 decimals;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev A mapping from a token address to its associated Chainlink price feed.
    mapping(address => PriceFeed) private _priceFeeds;

    /// @dev Maps tokens to their canonical form for price querying.
    ///      For example, WETH may be remapped to ETH, WBTC to BTC, etc.
    mapping(address => address) private _remappedTokens;

    /// @dev Token mapping if its pricing is quoted in ETH.
    mapping(address => bool) private _isQuotedInEth;

    /// @dev Address representing ETH in Chainlink's denominations.
    address private constant _ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev WstETH address
    address private constant _WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev ankrETH address
    address private constant _ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;

    /*//////////////////////////////////////////////////////////////////////////
                                     EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new price feed for a token is set or updated.
     * @param token The address of the token for which the price feed is set or updated.
     * @param priceFeed The address of the Chainlink price feed for the token.
     */
    event SetTokenPriceFeed(address indexed token, address indexed priceFeed);

    /**
     * @notice Emitted when a token is remapped to its canonical form.
     * @param token The original token address that's being remapped.
     * @param remappedToken The canonical form of the token to which the original is remapped.
     */
    event SetTokenRemapping(address indexed token, address indexed remappedToken);

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
     * @param owner Address of the owner of the contract.
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
    }

    /**
     * @notice Maps a list of tokens to their canonical form for price queries.
     * @param tokens The list of tokens to be remapped.
     * @param remappedTokens The list of tokens to remap to.
     */
    function setTokenRemappings(address[] calldata tokens, address[] calldata remappedTokens) external onlyOwner {
        uint256 tokensLength = tokens.length;
        if (tokensLength != remappedTokens.length) revert Errors.INPUT_ARRAY_MISMATCH();

        for (uint256 i = 0; i < tokensLength; ++i) {
            if (tokens[i] == address(0)) revert Errors.ZERO_ADDRESS();

            _remappedTokens[tokens[i]] = remappedTokens[i];
            emit SetTokenRemapping(tokens[i], remappedTokens[i]);
        }
    }

    /**
     * @notice Sets the price feeds for specified tokens.
     * @param tokens List of tokens for which the price feeds are being set.
     * @param priceFeeds Corresponding list of Chainlink price feeds.
     */
    function setPriceFeeds(address[] calldata tokens, address[] calldata priceFeeds) external onlyOwner {
        uint256 tokensLength = tokens.length;
        if (tokensLength != priceFeeds.length) revert Errors.INPUT_ARRAY_MISMATCH();

        for (uint256 i = 0; i < tokensLength; ++i) {
            if (tokens[i] == address(0)) revert Errors.ZERO_ADDRESS();
            if (priceFeeds[i] == address(0)) revert Errors.ZERO_ADDRESS();

            uint8 decimals = IAggregatorV3Interface(priceFeeds[i]).decimals();

            _priceFeeds[tokens[i]] = PriceFeed(priceFeeds[i], decimals);

            emit SetTokenPriceFeed(tokens[i], priceFeeds[i]);
        }
    }

    /**
     * @notice Registers a token as being quoted in ETH
     * @param token The token address to register
     * @param isQuoteEth Whether the token is quoted in ETH or not
     */
    function setEthDenominatedToken(address token, bool isQuoteEth) external onlyOwner {
        if (token == address(0)) revert Errors.ZERO_ADDRESS();
        _isQuotedInEth[token] = isQuoteEth;
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        /// remap token if possible
        address remappedToken = _remappedTokens[token];
        if (remappedToken == address(0)) remappedToken = token;

        (uint256 answer, uint8 decimals) = _getPriceInUsd(remappedToken);

        // special case pricing for WstETH and ankrETH
        if (token == _WSTETH) {
            return _calculateWstETH(answer, decimals);
        } else if (token == _ANKRETH) {
            return _calculateAnkrETH(answer, decimals);
        }

        return (answer * Constants.PRICE_PRECISION) / 10 ** decimals;
    }

    /**
     * @notice Returns the Chainlink feed used to price a token.
     * @param token The token address to check the price feed of.
     * @return The address of the Chainlink price feed.
     */
    function getPriceFeed(address token) public view returns (address) {
        return _priceFeeds[token].feed;
    }

    /**
     * @notice Returns the canonical form of the specified token, if it exists.
     * @param token The token address to check.
     * @return The canonical form of the token, if it exists.
     */
    function getTokenRemapping(address token) external view returns (address) {
        return _remappedTokens[token];
    }

    /**
     * @notice Gets the price of the specified token in USD.
     * @param token The token address to fecth the price of.
     * @return answer The price of the token in USD.
     * @return decimals The number of decimals of the token.
     */
    function _getPriceInUsd(address token) internal view returns (uint256 answer, uint8 decimals) {
        uint256 maxDelayTime = _timeGaps[token];
        if (maxDelayTime == 0) revert Errors.NO_MAX_DELAY(token);

        PriceFeed memory tokenPriceFeed = _priceFeeds[token];

        if (_isQuotedInEth[token] == true) {
            uint256 tokenPriceInEth = _getTokenPrice(tokenPriceFeed.feed, maxDelayTime);

            PriceFeed memory ethPriceFeed = _priceFeeds[_ETH];

            uint256 ethUsdPrice = _getTokenPrice(ethPriceFeed.feed, maxDelayTime);
            uint256 ethUsdDecimals = ethPriceFeed.decimals;
            uint256 scaledEthUsdPrice = (ethUsdPrice * Constants.PRICE_PRECISION) / 10 ** ethUsdDecimals;

            answer = (tokenPriceInEth * scaledEthUsdPrice) / 10 ** tokenPriceFeed.decimals;

            // Decimals will always be 18 since we are scaling the ETH/USD price by 18 decimals
            //    and token's price feed decimals will cancel out with the token's return value
            return (answer, 18);
        } else {
            decimals = tokenPriceFeed.decimals;
            answer = _getTokenPrice(tokenPriceFeed.feed, maxDelayTime);
        }
    }

    /**
     * @notice Gets the token price from the Chainlink registry and validates it.
     * @param priceFeed The Chainlink feed to use.
     * @param maxDelayTime The max delay allowed for price feed updates
     * @return The price of the token.
     */
    function _getTokenPrice(address priceFeed, uint256 maxDelayTime) internal view returns (uint256) {
        (uint80 roundID, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = IAggregatorV3Interface(priceFeed)
            .latestRoundData();

        if (updatedAt < block.timestamp - maxDelayTime) revert Errors.PRICE_OUTDATED(priceFeed);
        if (answer <= 0) revert Errors.PRICE_NEGATIVE(priceFeed);
        if (answeredInRound < roundID) revert Errors.PRICE_OUTDATED(priceFeed);

        return answer.toUint256();
    }

    /**
     * @notice Calculates the price of WstETH in USD.
     * @param answer The price of the remapped token in USD.
     * @param decimals The number of decimals returned by the Chainlink feed.
     * @return The price of WstETH in USD.
     */
    function _calculateWstETH(uint256 answer, uint8 decimals) internal view returns (uint256) {
        return ((answer * Constants.PRICE_PRECISION) * IWstETH(_WSTETH).stEthPerToken()) / 10 ** (18 + decimals);
    }

    /**
     * @notice Calculates the price of AnkrETH in USD.
     * @param answer The price of the remapped token in USD.
     * @param decimals The number of decimals returned by the Chainlink feed.
     * @return The price of AnkrETH in USD.
     */
    function _calculateAnkrETH(uint256 answer, uint256 decimals) internal view returns (uint256) {
        return
            ((answer * Constants.PRICE_PRECISION) * IAnkrETH(_ANKRETH).sharesToBonds(Constants.PRICE_PRECISION)) /
            10 ** (18 + decimals);
    }
}
