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

/**
 * @author BlueberryProtocol
 * @title ChainlinkAdapterOracleL2 for L2 chains including Arb, Optimism
 * @notice Oracle Adapter contract which provides price feeds from Chainlink
 */
contract ChainlinkAdapterOracleL2 is IBaseOracle, BaseAdapter {
    using SafeCast for int256;

    ISequencerUptimeFeed public sequencerUptimeFeed;

    /// @dev Mapping from token to price feed (e.g. ETH -> ETH/USD price feed)
    mapping(address => address) public priceFeeds;

    event SetRegistry(address registry);
    event SetRequencerUptimeFeed(address registry);
    event SetTokenPriceFeed(address indexed token, address indexed priceFeed);

    constructor(ISequencerUptimeFeed sequencerUptimeFeed_) {
        if (address(sequencerUptimeFeed_) == address(0))
            revert Errors.ZERO_ADDRESS();

        sequencerUptimeFeed = sequencerUptimeFeed_;
    }

    /**
     * @notice Set chainlink L2 sequencer uptime feed registry source
     * @param sequencerUptimeFeed_ Chainlink L2 sequencer uptime feed source
     */
    function setSequencerUptimeFeed(
        ISequencerUptimeFeed sequencerUptimeFeed_
    ) external onlyOwner {
        if (address(sequencerUptimeFeed_) == address(0))
            revert Errors.ZERO_ADDRESS();

        sequencerUptimeFeed = sequencerUptimeFeed_;
        emit SetRequencerUptimeFeed(address(sequencerUptimeFeed_));
    }

    /**
     * @notice Set token price feeds
     * @param tokens_ List of tokens to get price
     * @param priceFeeds_ List of chainlink price feed
     */
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

    /**
     * @notice Returns the USD price of given token, price value has 18 decimals
     * @param token_ Token address to get price of
     * @return price USD price of token in 18 decimal
     */
    function getPrice(address token_) external view override returns (uint256) {
        // 1. Check max delay time
        uint256 maxDelayTime = timeGaps[token_];
        if (maxDelayTime == 0) revert Errors.NO_MAX_DELAY(token_);

        // 2. L2 sequencer status check
        (, int256 answer, uint256 startedAt, , ) = sequencerUptimeFeed
            .latestRoundData();

        // Answer == 0: Sequencer is up, Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert Errors.SEQURENCE_DOWN(address(sequencerUptimeFeed));
        }

        // Make sure the grace period has passed after the sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= Constants.SEQUENCE_GRACE_PERIOD_TIME) {
            revert Errors.SEQURENCE_GRACE_PERIOD_NOT_OVER(
                address(sequencerUptimeFeed)
            );
        }

        // 3. Get price from price feed
        address priceFeed = priceFeeds[token_];
        if (priceFeed == address(0)) revert Errors.ZERO_ADDRESS();

        // Get token-USD price
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
