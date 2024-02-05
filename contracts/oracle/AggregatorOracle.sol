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

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseOracleExt } from "./BaseOracleExt.sol";
import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @title AggregatorOracle
 * @author BlueberryProtocol
 * @notice This contract aggregates price feeds from multiple oracle sources,
 *         ensuring a more reliable and resilient price data.
 */
contract AggregatorOracle is IBaseOracle, Ownable2StepUpgradeable, BaseOracleExt {
    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Mapping of primary oracle sources associated with each token.
    mapping(address => uint256) private _primarySourceCount;
    /// @notice Mapping from token to (mapping from index to oracle source)
    mapping(address => mapping(uint256 => IBaseOracle)) private _primarySources;
    //// @notice Maximum allowed price deviation between oracle sources, expressed in base 10000.
    mapping(address => uint256) private _maxPriceDeviations;

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when primary oracle sources are set or updated for a token.
     * @param token Address of the token whose oracle sources were updated.
     * @param maxPriceDeviation Maximum allowed price deviation.
     * @param oracles List of oracle sources set for the token.
     */
    event SetPrimarySources(address indexed token, uint256 maxPriceDeviation, IBaseOracle[] oracles);

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
     * @param owner Address of the owner of the contract.
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
    }

    /**
     * @notice Set primary oracle sources for the given token
     * @dev Only owner can set primary sources
     * @param token Token address to set oracle sources
     * @param maxPriceDeviation Maximum price deviation (in 1e18) of price feeds
     * @param sources Oracle sources for the token
     */
    function setPrimarySources(
        address token,
        uint256 maxPriceDeviation,
        IBaseOracle[] memory sources
    ) external onlyOwner {
        _setPrimarySources(token, maxPriceDeviation, sources);
    }

    /**
     * @notice Set or update the primary oracle sources for multiple tokens at once.
     * @dev Can only be called by the contract owner.
     * @param tokens List of token addresses.
     * @param maxPriceDeviationList List of maximum allowed price deviations (in 1e18).
     * @param allSources list of oracle sources, one list for each token.
     */
    function setMultiPrimarySources(
        address[] memory tokens,
        uint256[] memory maxPriceDeviationList,
        IBaseOracle[][] memory allSources
    ) external onlyOwner {
        // Validate inputs
        if (tokens.length != allSources.length || tokens.length != maxPriceDeviationList.length) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            _setPrimarySources(tokens[i], maxPriceDeviationList[i], allSources[i]);
        }
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        uint256 candidateSourceCount = getPrimarySourceCount(token);
        if (candidateSourceCount == 0) revert Errors.NO_PRIMARY_SOURCE(token);

        uint256[] memory prices = new uint256[](candidateSourceCount);
        /// Get valid oracle sources
        uint256 validSourceCount = 0;
        for (uint256 i = 0; i < candidateSourceCount; ++i) {
            try _primarySources[token][i].getPrice(token) returns (uint256 px) {
                if (px != 0) prices[validSourceCount++] = px;
            } catch {
                // solhint-disable-previous-line no-empty-blocks
            }
        }

        if (validSourceCount == 0) revert Errors.NO_VALID_SOURCE(token);
        /// Sort prices in ascending order
        for (uint256 i = 0; i < validSourceCount - 1; ++i) {
            for (uint256 j = 0; j < validSourceCount - i - 1; ++j) {
                if (prices[j] > prices[j + 1]) {
                    (prices[j], prices[j + 1]) = (prices[j + 1], prices[j]);
                }
            }
        }
        uint256 maxPriceDeviation = _maxPriceDeviations[token];

        /// Algo:
        /// - 1 valid source --> return price
        /// - 2 valid sources
        ///     --> if the prices within deviation threshold, return average
        ///     --> else revert
        /// - 3 valid sources --> check deviation threshold of each pair
        ///     --> if all within threshold, return median
        ///     --> if one pair within threshold, return average of the pair
        ///     --> if none, revert
        /// - revert Errors.otherwise
        if (validSourceCount == 1) {
            return prices[0]; // if 1 valid source, return
        } else if (validSourceCount == 2) {
            if (!_isValidPrices(prices[0], prices[1], maxPriceDeviation)) revert Errors.EXCEED_DEVIATION();
            return (prices[0] + prices[1]) / 2; /// if 2 valid sources, return average
        } else {
            bool midMinOk = _isValidPrices(prices[0], prices[1], maxPriceDeviation);
            bool maxMidOk = _isValidPrices(prices[1], prices[2], maxPriceDeviation);

            if (midMinOk && maxMidOk) {
                return prices[1]; /// if 3 valid sources, and each pair is within thresh, return median
            } else if (midMinOk) {
                return (prices[0] + prices[1]) / 2; /// return average of pair within thresh
            } else if (maxMidOk) {
                return (prices[1] + prices[2]) / 2; /// return average of pair within thresh
            } else {
                revert Errors.EXCEED_DEVIATION();
            }
        }
    }

    /**
     * @notice Fetch the amount of primary source oracles associated with a token
     * @param token Token address to check the primary source count.
     * @return Number of primary source oracles.
     */
    function getPrimarySourceCount(address token) public view returns (uint256) {
        return _primarySourceCount[token];
    }

    /**
     * @notice Fetch the source oracle associate with a given token and index
     * @param token Token address to check the primary source count.
     * @param index Index of the primary source oracle.
     * @return Source Oracle.
     */
    function getPrimarySource(address token, uint256 index) external view returns (IBaseOracle) {
        return _primarySources[token][index];
    }

    /**
     * @notice Fetches the upper bound for a token's price deviation
     * @param token Address of the token to check the deviation cap.
     * @return The maximum allowed price deviation.
     */
    function getMaxPriceDeviation(address token) external view returns (uint256) {
        return _maxPriceDeviations[token];
    }

    /**
     * @notice Set primary oracle sources for given token
     * @dev Emit SetPrimarySources event when primary oracles set successfully
     * @param token Token to set oracle sources
     * @param maxPriceDeviation Maximum price deviation (in 1e18) of price feeds
     * @param sources Oracle sources for the token
     */
    function _setPrimarySources(address token, uint256 maxPriceDeviation, IBaseOracle[] memory sources) internal {
        // Validate inputs
        if (token == address(0)) revert Errors.ZERO_ADDRESS();
        if (maxPriceDeviation > Constants.MAX_PRICE_DEVIATION) {
            revert Errors.OUT_OF_DEVIATION_CAP(maxPriceDeviation);
        }

        uint256 sourcesLength = sources.length;

        if (sourcesLength > 3) revert Errors.EXCEED_SOURCE_LEN(sourcesLength);

        _primarySourceCount[token] = sourcesLength;
        _maxPriceDeviations[token] = maxPriceDeviation;

        for (uint256 i = 0; i < sourcesLength; ++i) {
            if (address(sources[i]) == address(0)) revert Errors.ZERO_ADDRESS();
            _primarySources[token][i] = sources[i];
        }

        emit SetPrimarySources(token, maxPriceDeviation, sources);
    }
}
