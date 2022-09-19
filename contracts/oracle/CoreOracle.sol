// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IBaseOracle.sol';

contract CoreOracle is IBaseOracle, Ownable {
    event SetRoute(address indexed token, address route);
    mapping(address => address) public routes; // Mapping from token to oracle source

    /// @dev Set oracle source routes for tokens
    /// @param tokens List of tokens
    /// @param targets List of oracle source routes
    function setRoute(address[] calldata tokens, address[] calldata targets)
        external
        onlyOwner
    {
        require(tokens.length == targets.length, 'inconsistent length');
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            routes[tokens[idx]] = targets[idx];
            emit SetRoute(tokens[idx], targets[idx]);
        }
    }

    /// @dev Return the USD based price of the given input, multiplied by 10**18.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external view override returns (uint256) {
        uint256 px = IBaseOracle(routes[token]).getPrice(token);
        require(px != 0, 'price oracle failure');
        return px;
    }
}
