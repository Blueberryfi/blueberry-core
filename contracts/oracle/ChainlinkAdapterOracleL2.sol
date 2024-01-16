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

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseAdapter } from "./BaseAdapter.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ISequencerUptimeFeed } from "../interfaces/chainlink/ISequencerUptimeFeed.sol";

/**
 * @title ChainlinkAdapterOracleL2
 * @author BlueberryProtocol
 * @notice This contract integrates Chainlink's Oracle to fetch price data on Layer 2 networks.
 *         It also monitors the uptime status of the L2 sequencer.
 */
contract ChainlinkAdapterOracleL2 is IBaseOracle, BaseAdapter {
    using SafeCast for int256;

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Reference to the sequencer uptime feed (used to monitor L2 chain status).
    ISequencerUptimeFeed private _sequencerUptimeFeed;

    /// @dev A mapping from a token address to its associated Chainlink price feed.
    mapping(address => address) private _priceFeeds;

    /*//////////////////////////////////////////////////////////////////////////
                                     EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the Chainlink feed registry used by the adapter is updated.
     * @param registry The address of the updated registry.
     */
    event SetRegistry(address registry);

    /**
     * @notice Emitted when the L2 sequencer uptime feed registry source is updated.
     * @param registry The address of the updated L2 sequencer uptime feed registry.
     */
    event SetSequencerUptimeFeed(address registry);

    /**
     * @notice Emitted when a new price feed for a token is set or updated.
     * @param token The address of the token for which the price feed is set or updated.
     * @param priceFeed The address of the Chainlink price feed for the token.
     */
    event SetTokenPriceFeed(address indexed token, address indexed priceFeed);

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
     * @param sequencerUptimeFeed Chainlink L2 sequencer uptime feed registry source.
     * @param owner Address of the owner of the contract.
     */
    function initialize(ISequencerUptimeFeed sequencerUptimeFeed, address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);

        if (address(sequencerUptimeFeed) == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        _sequencerUptimeFeed = sequencerUptimeFeed;
    }

    /**
     * @notice Sets the Chainlink L2 sequencer uptime feed registry source.
     * @param sequencerUptimeFeed The Chainlink L2 sequencer uptime feed source.
     */
    function setSequencerUptimeFeed(ISequencerUptimeFeed sequencerUptimeFeed) external onlyOwner {
        if (address(sequencerUptimeFeed) == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _sequencerUptimeFeed = sequencerUptimeFeed;
        emit SetSequencerUptimeFeed(address(sequencerUptimeFeed));
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
            _priceFeeds[tokens[i]] = priceFeeds[i];

            emit SetTokenPriceFeed(tokens[i], priceFeeds[i]);
        }
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        /// 1. Check for the maximum acceptable delay time.
        uint256 maxDelayTime = _timeGaps[token];
        if (maxDelayTime == 0) revert Errors.NO_MAX_DELAY(token);

        ISequencerUptimeFeed sequencerUptimeFeed = getSequencerUptimeFeed();

        /// 2. L2 sequencer status check (0 = up, 1 = down).
        (, int256 answer, uint256 startedAt, , ) = sequencerUptimeFeed.latestRoundData();

        /// Ensure the grace period has passed after the sequencer is back up.
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert Errors.SEQUENCER_DOWN(address(sequencerUptimeFeed));
        }

        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= Constants.SEQUENCER_GRACE_PERIOD_TIME) {
            revert Errors.SEQUENCER_GRACE_PERIOD_NOT_OVER(address(sequencerUptimeFeed));
        }

        /// 3. Retrieve the price from the Chainlink feed.
        address priceFeed = getPriceFeed(token);
        if (priceFeed == address(0)) revert Errors.ZERO_ADDRESS();

        /// Get token-USD price
        (uint80 roundID, int256 price, , uint256 updatedAt, uint80 answeredInRound) = AggregatorV3Interface(priceFeed)
            .latestRoundData();
        if (updatedAt < block.timestamp - maxDelayTime) revert Errors.PRICE_OUTDATED(token);
        if (price <= 0) revert Errors.PRICE_NEGATIVE(token);
        if (answeredInRound < roundID) revert Errors.PRICE_OUTDATED(token);

        return (price.toUint256() * Constants.PRICE_PRECISION) / Constants.CHAINLINK_PRICE_FEED_PRECISION;
    }

    /// @notice Returns the Chainlink L2 sequencer uptime feed source
    function getSequencerUptimeFeed() public view returns (ISequencerUptimeFeed) {
        return _sequencerUptimeFeed;
    }

    /// @notice Returns the Chainlink price feed for the specified token.
    function getPriceFeed(address token) public view returns (address) {
        return _priceFeeds[token];
    }
}
