// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '../Governable.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/band/IStdReference.sol';

contract BandAdapterOracle is IBaseOracle, Governable {
    event SetSymbol(address token, string symbol);
    event SetRef(address ref);
    event SetMaxDelayTime(address token, uint256 maxDelayTime);

    string public constant ETH = 'ETH';
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IStdReference public ref; // Standard reference

    mapping(address => string) public symbols; // Mapping from token to symbol string
    mapping(address => uint256) public maxDelayTimes; // Mapping from token address to max delay time

    constructor(IStdReference _ref) {
        __Governable__init();
        ref = _ref;
    }

    /// @dev Set token symbols
    /// @param tokens List of tokens
    /// @param syms List of string symbols
    function setSymbols(address[] memory tokens, string[] memory syms)
        external
        onlyGov
    {
        require(syms.length == tokens.length, 'length mismatch');
        for (uint256 idx = 0; idx < syms.length; idx++) {
            symbols[tokens[idx]] = syms[idx];
            emit SetSymbol(tokens[idx], syms[idx]);
        }
    }

    /// @dev Set standard reference source
    /// @param _ref Standard reference source
    function setRef(IStdReference _ref) external onlyGov {
        ref = _ref;
        emit SetRef(address(_ref));
    }

    /// @dev Set max delay time for each token
    /// @param tokens list of tokens to set max delay
    /// @param maxDelays list of max delay times to set to
    function setMaxDelayTimes(
        address[] calldata tokens,
        uint256[] calldata maxDelays
    ) external onlyGov {
        require(tokens.length == maxDelays.length, 'length mismatch');
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            maxDelayTimes[tokens[idx]] = maxDelays[idx];
            emit SetMaxDelayTime(tokens[idx], maxDelays[idx]);
        }
    }

    /// @dev Return the value of the given input as ETH per unit, multiplied by 2**112.
    /// @param token The ERC-20 token to check the value.
    function getETHPx(address token) external view override returns (uint256) {
        if (
            token == WETH || token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        ) return uint256(2**112);

        string memory sym = symbols[token];
        uint256 maxDelayTime = maxDelayTimes[token];
        require(bytes(sym).length != 0, 'no mapping');
        require(maxDelayTime != 0, 'max delay time not set');
        IStdReference.ReferenceData memory data = ref.getReferenceData(
            sym,
            ETH
        );
        require(
            data.lastUpdatedBase >= block.timestamp - maxDelayTime,
            'delayed base data'
        );
        require(
            data.lastUpdatedQuote >= block.timestamp - maxDelayTime,
            'delayed quote data'
        );
        return (data.rate * 2**112) / 10**18;
    }
}
