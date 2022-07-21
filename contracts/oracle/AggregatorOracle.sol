// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '../Governable.sol';
import '../interfaces/IBaseOracle.sol';

contract AggregatorOracle is IBaseOracle, Governable {
    event SetPrimarySources(
        address indexed token,
        uint256 maxPriceDeviation,
        IBaseOracle[] oracles
    );

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH address
    mapping(address => uint256) public primarySourceCount; // Mapping from token to number of sources
    /// @dev Mapping from token to (mapping from index to oracle source)
    mapping(address => mapping(uint256 => IBaseOracle)) public primarySources;
    /// @dev Mapping from token to max price deviation (multiplied by 1e18)
    mapping(address => uint256) public maxPriceDeviations;

    uint256 public constant MIN_PRICE_DEVIATION = 1e18; // min price deviation
    uint256 public constant MAX_PRICE_DEVIATION = 1.5e18; // max price deviation

    constructor() {
        __Governable__init();
    }

    /// @dev Set oracle primary sources for the token
    /// @param token Token address to set oracle sources
    /// @param maxPriceDeviation Max price deviation (in 1e18) for token
    /// @param sources Oracle sources for the token
    function setPrimarySources(
        address token,
        uint256 maxPriceDeviation,
        IBaseOracle[] memory sources
    ) external onlyGov {
        _setPrimarySources(token, maxPriceDeviation, sources);
    }

    /// @dev Set oracle primary sources for multiple tokens
    /// @param tokens List of token addresses to set oracle sources
    /// @param maxPriceDeviationList List of max price deviations (in 1e18) for tokens
    /// @param allSources List of oracle sources for tokens
    function setMultiPrimarySources(
        address[] memory tokens,
        uint256[] memory maxPriceDeviationList,
        IBaseOracle[][] memory allSources
    ) external onlyGov {
        require(tokens.length == allSources.length, 'inconsistent length');
        require(
            tokens.length == maxPriceDeviationList.length,
            'inconsistent length'
        );
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            _setPrimarySources(
                tokens[idx],
                maxPriceDeviationList[idx],
                allSources[idx]
            );
        }
    }

    /// @dev Set oracle primary sources for tokens
    /// @param token Token to set oracle sources
    /// @param maxPriceDeviation Max price deviation (in 1e18) for token
    /// @param sources Oracle sources for the token
    function _setPrimarySources(
        address token,
        uint256 maxPriceDeviation,
        IBaseOracle[] memory sources
    ) internal {
        primarySourceCount[token] = sources.length;
        require(
            maxPriceDeviation >= MIN_PRICE_DEVIATION &&
                maxPriceDeviation <= MAX_PRICE_DEVIATION,
            'bad max deviation value'
        );
        require(sources.length <= 3, 'sources length exceed 3');
        maxPriceDeviations[token] = maxPriceDeviation;
        for (uint256 idx = 0; idx < sources.length; idx++) {
            primarySources[token][idx] = sources[idx];
        }
        emit SetPrimarySources(token, maxPriceDeviation, sources);
    }

    /// @dev Return token price relative to ETH, multiplied by 2**112
    /// @param token Token to get price of
    /// NOTE: Support at most 3 oracle sources per token
    function getETHPx(address token) public view override returns (uint256) {
        uint256 candidateSourceCount = primarySourceCount[token];
        require(candidateSourceCount > 0, 'no primary source');
        uint256[] memory prices = new uint256[](candidateSourceCount);

        // Get valid oracle sources
        uint256 validSourceCount = 0;
        for (uint256 idx = 0; idx < candidateSourceCount; idx++) {
            try primarySources[token][idx].getETHPx(token) returns (
                uint256 px
            ) {
                prices[validSourceCount++] = px;
            } catch {}
        }
        require(validSourceCount > 0, 'no valid source');
        for (uint256 i = 0; i < validSourceCount - 1; i++) {
            for (uint256 j = 0; j < validSourceCount - i - 1; j++) {
                if (prices[j] > prices[j + 1]) {
                    (prices[j], prices[j + 1]) = (prices[j + 1], prices[j]);
                }
            }
        }
        uint256 maxPriceDeviation = maxPriceDeviations[token];

        // Algo:
        // - 1 valid source --> return price
        // - 2 valid sources
        //     --> if the prices within deviation threshold, return average
        //     --> else revert
        // - 3 valid sources --> check deviation threshold of each pair
        //     --> if all within threshold, return median
        //     --> if one pair within threshold, return average of the pair
        //     --> if none, revert
        // - revert otherwise
        if (validSourceCount == 1) {
            return prices[0]; // if 1 valid source, return
        } else if (validSourceCount == 2) {
            require(
                (prices[1] * 1e18) / prices[0] <= maxPriceDeviation,
                'too much deviation (2 valid sources)'
            );
            return (prices[0] + prices[1]) / 2; // if 2 valid sources, return average
        } else if (validSourceCount == 3) {
            bool midMinOk = (prices[1] * 1e18) / prices[0] <= maxPriceDeviation;
            bool maxMidOk = (prices[2] * 1e18) / prices[1] <= maxPriceDeviation;
            if (midMinOk && maxMidOk) {
                return prices[1]; // if 3 valid sources, and each pair is within thresh, return median
            } else if (midMinOk) {
                return (prices[0] + prices[1]) / 2; // return average of pair within thresh
            } else if (maxMidOk) {
                return (prices[1] + prices[2]) / 2; // return average of pair within thresh
            } else {
                revert('too much deviation (3 valid sources)');
            }
        } else {
            revert('more than 3 valid sources not supported');
        }
    }

    /// @dev Return the price of token0/token1, multiplied by 1e18
    /// @notice One of the input tokens must be WETH
    function getPrice(address token0, address token1)
        external
        view
        returns (uint256, uint256)
    {
        require(
            token0 == WETH || token1 == WETH,
            'one of the requested tokens must be ETH or WETH'
        );
        if (token0 == WETH) {
            return (
                (uint256(2**112) * 1e18) / getETHPx(token1),
                block.timestamp
            );
        } else {
            return ((getETHPx(token0) * 1e18) / 2**112, block.timestamp);
        }
    }
}
