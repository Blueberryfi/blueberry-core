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

import "./BaseAdapter.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/band/IStdReference.sol";

/// @title BandAdapterOracle
/// @author BlueberryProtocol
/// @notice This contract is an adapter that fetches price feeds from Band Protocol.
contract BandAdapterOracle is IBaseOracle, BaseAdapter {

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The BandStandardRef oracle contract instance for price feeds.
    IStdReference public ref;

    /// @notice A mapping from token addresses to their respective symbol strings.
    /// Band Protocol provides price feeds based on token symbols.
    mapping(address => string) public symbols;

    /*//////////////////////////////////////////////////////////////////////////
                                     EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new Band Protocol reference instance is set.
    /// @param ref Address of the new Band Protocol reference contract.
    event SetRef(address ref);

    /// @notice Emitted when a token's symbol string is set or updated.
    /// @param token The token address whose symbol was set.
    /// @param symbol The new token symbol string.
    event SetSymbol(address token, string symbol);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructs the BandAdapterOracle contract instance.
    /// @param ref_ Address of the Band Protocol reference contract.
    constructor(IStdReference ref_) {
        if (address(ref_) == address(0)) revert Errors.ZERO_ADDRESS();

        ref = ref_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the standard reference contract used to fetch price data.
    /// @param ref_ The new Band Protocol reference contract address.
    function setRef(IStdReference ref_) external onlyOwner {
        if (address(ref_) == address(0)) revert Errors.ZERO_ADDRESS();
        ref = ref_;
        emit SetRef(address(ref_));
    }

    /// @notice Sets or updates symbols for a list of tokens.
    /// @param tokens List of token addresses.
    /// @param syms List of corresponding symbol strings.
    function setSymbols(
        address[] calldata tokens,
        string[] calldata syms
    ) external onlyOwner {
        if (syms.length != tokens.length) revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < syms.length; idx++) {
            if (tokens[idx] == address(0)) revert Errors.ZERO_ADDRESS();

            symbols[tokens[idx]] = syms[idx];
            emit SetSymbol(tokens[idx], syms[idx]);
        }
    }

    /// @notice Fetches the current USD price of the specified token.
    /// @dev The price returned has a precision of 1e18. The Band Protocol already provides prices with this precision.
    /// @param token The address of the ERC-20 token to get the price for.
    /// @return The current USD price of the token.
    function getPrice(address token) external override returns (uint256) {
        string memory sym = symbols[token];
        uint256 maxDelayTime = timeGaps[token];
        if (bytes(sym).length == 0) revert Errors.NO_SYM_MAPPING(token);
        if (maxDelayTime == 0) revert Errors.NO_MAX_DELAY(token);

        IStdReference.ReferenceData memory data = ref.getReferenceData(
            sym,
            "USD"
        );
        if (
            data.lastUpdatedBase < block.timestamp - maxDelayTime ||
            data.lastUpdatedQuote < block.timestamp - maxDelayTime
        ) revert Errors.PRICE_OUTDATED(token);

        return data.rate;
    }
}
