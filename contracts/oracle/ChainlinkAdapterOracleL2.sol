// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./BaseAdapter.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/chainlink/ISequencerUptimeFeed.sol";

/// @title Chainlink Adapter Oracle for L2 chains including Arb, Optimism, etc.
/// @author BlueberryProtocol
/// @notice This contract integrates Chainlink's Oracle to fetch price data on Layer 2 networks.
///         It also monitors the uptime status of the L2 sequencer.
contract ChainlinkAdapterOracleL2 is IBaseOracle, BaseAdapter {
    using SafeCast for int256;

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// Reference to the sequencer uptime feed (used to monitor L2 chain status).
    ISequencerUptimeFeed public sequencerUptimeFeed;

    /// @dev A mapping from a token address to its associated Chainlink price feed.
    mapping(address => address) public priceFeeds;

    /*//////////////////////////////////////////////////////////////////////////
                                     EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the registry is updated.
    /// @param registry The address of the updated registry.
    event SetRegistry(address registry);

    /// @notice Emitted when the L2 sequencer uptime feed registry source is updated.
    /// @param registry The address of the updated L2 sequencer uptime feed registry.
    event SetSequencerUptimeFeed(address registry);

    /// @notice Emitted when a new price feed for a token is set or updated.
    /// @param token The address of the token for which the price feed is set or updated.
    /// @param priceFeed The address of the Chainlink price feed for the token.    
    event SetTokenPriceFeed(address indexed token, address indexed priceFeed);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructs the ChainlinkAdapterOracleL2 and sets the L2 sequencer uptime feed.
    /// @param sequencerUptimeFeed_ The Chainlink L2 sequencer uptime feed source.
    constructor(ISequencerUptimeFeed sequencerUptimeFeed_) {
        if (address(sequencerUptimeFeed_) == address(0))
            revert Errors.ZERO_ADDRESS();

        sequencerUptimeFeed = sequencerUptimeFeed_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets the Chainlink L2 sequencer uptime feed registry source.
    /// @param sequencerUptimeFeed_ Chainlink L2 sequencer uptime feed source.
    function setSequencerUptimeFeed(
        ISequencerUptimeFeed sequencerUptimeFeed_
    ) external onlyOwner {
        if (address(sequencerUptimeFeed_) == address(0))
            revert Errors.ZERO_ADDRESS();

        sequencerUptimeFeed = sequencerUptimeFeed_;
        emit SetSequencerUptimeFeed(address(sequencerUptimeFeed_));
    }

    /// @notice Sets the price feeds for specified tokens.
    /// @param tokens_ List of tokens for which the price feeds are being set.
    /// @param priceFeeds_ Corresponding list of Chainlink price feeds.
    function setPriceFeeds(
        address[] calldata tokens_,
        address[] calldata priceFeeds_
    ) external onlyOwner {
        if (tokens_.length != priceFeeds_.length)
            revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens_.length; idx++) {
            if (tokens_[idx] == address(0)) revert Errors.ZERO_ADDRESS();
            if (priceFeeds_[idx] == address(0)) revert Errors.ZERO_ADDRESS();

            priceFeeds[tokens_[idx]] = priceFeeds_[idx];
            emit SetTokenPriceFeed(tokens_[idx], priceFeeds_[idx]);
        }
    }

    /// @notice Returns the USD price of the specified token. Price value is with 18 decimals.
    /// @param token_ Token address to get the price of.
    /// @return price USD price of the specified token.
    /// @dev Fetches the price from the Chainlink price feed, checks sequencer status, and verifies price validity.
    function getPrice(address token_) external view override returns (uint256) {
        /// 1. Check for the maximum acceptable delay time.
        uint256 maxDelayTime = timeGaps[token_];
        if (maxDelayTime == 0) revert Errors.NO_MAX_DELAY(token_);

        /// 2. L2 sequencer status check (0 = up, 1 = down).
        (, int256 answer, uint256 startedAt, , ) = sequencerUptimeFeed
            .latestRoundData();

        /// Ensure the grace period has passed after the sequencer is back up.
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert Errors.SEQUENCER_DOWN(address(sequencerUptimeFeed));
        }

        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= Constants.SEQUENCER_GRACE_PERIOD_TIME) {
            revert Errors.SEQUENCER_GRACE_PERIOD_NOT_OVER(
                address(sequencerUptimeFeed)
            );
        }

        /// 3. Retrieve the price from the Chainlink feed.
        address priceFeed = priceFeeds[token_];
        if (priceFeed == address(0)) revert Errors.ZERO_ADDRESS();

        /// Get token-USD price
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(priceFeed).latestRoundData();
        if (updatedAt < block.timestamp - maxDelayTime)
            revert Errors.PRICE_OUTDATED(token_);
        if (price <= 0) revert Errors.PRICE_NEGATIVE(token_);
        if (answeredInRound < roundID) revert Errors.PRICE_OUTDATED(token_);

        return
            (price.toUint256() * Constants.PRICE_PRECISION) /
            Constants.CHAINLINK_PRICE_FEED_PRECISION;
    }
}
