// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import "./BaseAdapter.sol";
import "../utils/BlueBerryErrors.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/band/IStdReference.sol";

contract BandAdapterOracle is IBaseOracle, BaseAdapter {
    IStdReference public ref; // Standard reference

    mapping(address => string) public symbols; // Mapping from token to symbol string

    event SetRef(address ref);
    event SetSymbol(address token, string symbol);

    constructor(IStdReference _ref) {
        if (address(_ref) == address(0)) revert ZERO_ADDRESS();

        ref = _ref;
    }

    /// @dev Set standard reference source
    /// @param _ref Standard reference source
    function setRef(IStdReference _ref) external onlyOwner {
        if (address(_ref) == address(0)) revert ZERO_ADDRESS();
        ref = _ref;
        emit SetRef(address(_ref));
    }

    /// @dev Set token symbols
    /// @param tokens List of tokens
    /// @param syms List of string symbols
    function setSymbols(address[] memory tokens, string[] memory syms)
        external
        onlyOwner
    {
        if (syms.length != tokens.length) revert INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < syms.length; idx++) {
            if (tokens[idx] == address(0)) revert ZERO_ADDRESS();

            symbols[tokens[idx]] = syms[idx];
            emit SetSymbol(tokens[idx], syms[idx]);
        }
    }

    /// @dev Return the USD based price of the given input, multiplied by 10**18.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external view override returns (uint256) {
        string memory sym = symbols[token];
        uint256 maxDelayTime = maxDelayTimes[token];
        if (bytes(sym).length == 0) revert NO_SYM_MAPPING(token);
        if (maxDelayTime == 0) revert NO_MAX_DELAY(token);

        IStdReference.ReferenceData memory data = ref.getReferenceData(
            sym,
            "USD"
        );
        if (
            data.lastUpdatedBase < block.timestamp - maxDelayTime ||
            data.lastUpdatedQuote < block.timestamp - maxDelayTime
        ) revert PRICE_OUTDATED(token);

        return data.rate;
    }
}
