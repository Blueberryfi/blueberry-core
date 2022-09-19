// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '../Governable.sol';
import '../interfaces/IBaseOracle.sol';

contract SimpleOracle is IBaseOracle, Governable {
    mapping(address => uint256) public prices; // Mapping from token to price in ETH (times 2**112).

    /// The governor sets oracle price for a token.
    event SetETHPx(address token, uint256 px);

    /// @dev Create the contract and initialize the first governor.
    constructor() {
        __Governable__init();
    }

    /// @dev Return the USD based price of the given input, multiplied by 10**18.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external view override returns (uint256) {
        uint256 px = prices[token];
        require(px != 0, 'no px');
        return px;
    }

    /// @dev Set the prices of the given token addresses.
    /// @param tokens The token addresses to set the prices.
    /// @param pxs The price data points, representing token value in ETH times 1e18.
    function setPrice(address[] memory tokens, uint256[] memory pxs)
        external
        onlyGov
    {
        require(tokens.length == pxs.length, 'inconsistent length');
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            prices[tokens[idx]] = pxs[idx];
            emit SetETHPx(tokens[idx], pxs[idx]);
        }
    }
}
