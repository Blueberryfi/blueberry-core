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
import { IFeedRegistry } from "../interfaces/chainlink/IFeedRegistry.sol";
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

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Chainlink feed registry for accessing price feeds.
    /// (source: https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/Denominations.sol)
    IFeedRegistry private _registry;

    /// @dev Maps tokens to their canonical form for price querying.
    ///      For example, WETH may be remapped to ETH, WBTC to BTC, etc.
    mapping(address => address) private _remappedTokens;

    /// @dev Address representing USD in Chainlink's denominations.
    address private constant _USD = address(840);

    /// @dev WstETH address
    address private constant _WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @dev ankrETH address
    address private constant _ANKRETH = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;

    /*//////////////////////////////////////////////////////////////////////////
                                     EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the Chainlink feed registry used by the adapter is updated.
     * @param registry The address of the updated registry.
     */
    event SetRegistry(address registry);

    /**
     * @notice Emitted when a token is remapped to its canonical form.
     * @param token The original token address that's being remapped.
     * @param remappedToken The canonical form of the token to which the original is remapped.
     */
    event SetTokenRemapping(address indexed token, address indexed remappedToken);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param registry Chainlink feed registry address.
    constructor(IFeedRegistry registry) {
        if (address(registry) == address(0)) revert Errors.ZERO_ADDRESS();

        _registry = registry;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the Chainlink feed registry used by this adapter.
     * @param registry The new Chainlink feed registry address.
     */
    function setFeedRegistry(IFeedRegistry registry) external onlyOwner {
        if (address(registry) == address(0)) revert Errors.ZERO_ADDRESS();
        registry = registry;
        emit SetRegistry(address(registry));
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

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        /// remap token if possible
        address remappedToken = _remappedTokens[token];
        if (remappedToken == address(0)) remappedToken = token;

        uint256 maxDelayTime = timeGaps[remappedToken];
        if (maxDelayTime == 0) revert Errors.NO_MAX_DELAY(token);

        IFeedRegistry registry = getFeedRegistry();

        /// Get token-USD price
        uint256 decimals = registry.decimals(remappedToken, _USD);
        (uint80 roundID, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = registry.latestRoundData(
            remappedToken,
            _USD
        );

        if (updatedAt < block.timestamp - maxDelayTime) revert Errors.PRICE_OUTDATED(token);
        if (answer <= 0) revert Errors.PRICE_NEGATIVE(token);
        if (answeredInRound < roundID) revert Errors.PRICE_OUTDATED(token);

        if (token == _WSTETH) {
            return
                ((answer.toUint256() * Constants.PRICE_PRECISION) * IWstETH(_WSTETH).stEthPerToken()) /
                10 ** (18 + decimals);
        } else if (token == _ANKRETH) {
            return
                ((answer.toUint256() * Constants.PRICE_PRECISION) *
                    IAnkrETH(_ANKRETH).sharesToBonds(Constants.PRICE_PRECISION)) / 10 ** (18 + decimals);
        }

        return (answer.toUint256() * Constants.PRICE_PRECISION) / 10 ** decimals;
    }

    /// @notice Returns the Chainlink feed registry used by this adapter.
    function getFeedRegistry() public view returns (IFeedRegistry) {
        return _registry;
    }

    /**
     * @notice Returns the canonical form of the specified token, if it exists.
     * @param token The token address to check.
     * @return The canonical form of the token, if it exists.
     */
    function getTokenRemapping(address token) public view returns (address) {
        return _remappedTokens[token];
    }
}
