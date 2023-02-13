// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IBaseOracle.sol";
import "../utils/BlueBerryErrors.sol";

contract ManualOracle is IBaseOracle, Ownable {
    /// @dev Mapping from token to price
    mapping(address => uint256) public manualPrices;
    /// @dev Mapping from token address to bool for manualPrices existance
    mapping(address => bool) public isManualPrices;

    constructor() {}

    /// @dev Set prices for multiple tokens
    /// @param tokens List of token addresses to set oracle sources
    /// @param priceList List of max price deviations (in 1e18) for tokens
    function setMultipleManualPrices(
        address[] memory tokens,
        uint256[] memory priceList,
        bool[] memory existances
    ) external onlyOwner {
        if (
            tokens.length != priceList.length ||
            tokens.length != existances.length
        ) revert INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            manualPrices[tokens[idx]] = priceList[idx];
            isManualPrices[tokens[idx]] = existances[idx];
        }
    }

    /// @notice Get token price from manual prices
    /// @dev Return the USD based price of the given input, multiplied by 10**18.
    /// @param token The token address to check the value.
    function getPrice(address token) external view override returns (uint256) {
        if (!isManualPrices[token]) return 0;

        return manualPrices[token];
    }
}
