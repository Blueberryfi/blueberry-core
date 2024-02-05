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

import { FixedPoint } from "../libraries/balancer-v2/FixedPoint.sol";
import { VaultReentrancyLib } from "../libraries/balancer-v2/VaultReentrancyLib.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IBalancerV2StablePool } from "../interfaces/balancer-v2/IBalancerV2StablePool.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { IRateProvider } from "../interfaces/balancer-v2/IRateProvider.sol";

/**
 * @title StableBPTOracle
 * @author BlueberryProtocol
 * @notice Oracle contract which privides price feeds of Stable Balancer LP tokens
 */
contract StableBPTOracle is IBaseOracle, UsingBaseOracle {
    using FixedPoint for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to Balancer Pool tokens
     * @param tokens An array of tokens within the pool
     * @param rateProviders An array of rate providers associated with the tokens in the pool
     */
    struct TokenInfo {
        address[] tokens;
        address[] rateProviders;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the weighted pool oracle
    IBaseOracle private _weightedPoolOracle;
    /// @dev Address of the Balancer Vault
    IBalancerVault private _vault;
    /// @dev mapping of registered bpt tokens to their token info
    mapping(address => TokenInfo) private _tokenInfo;

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    // Protects the oracle from being manipulated via read-only reentrancy
    modifier balancerNonReentrant() {
        VaultReentrancyLib.ensureNotInVaultContext(_vault);
        _;
    }

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
     * @param vault Instance of the Balancer V2 Vault
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IBalancerVault vault, IBaseOracle base, address owner) external initializer {
        __UsingBaseOracle_init(base, owner);
        _vault = vault;
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) public view override balancerNonReentrant returns (uint256) {
        TokenInfo memory tokenInfo = getBptInfo(token);
        uint256 tokenLength = tokenInfo.tokens.length;

        if (tokenLength == 0) revert Errors.ORACLE_NOT_SUPPORT_LP(token);

        uint256 minPrice = _getTokensMinPrice(tokenInfo.tokens, tokenInfo.rateProviders, tokenLength);
        uint256 rate = IBalancerV2StablePool(token).getRate();

        return minPrice.mulDown(rate);
    }

    /**
     * @notice Register Balancer Pool token to oracle
     * @dev Stores persistent data of Balancer Pool token
     * @dev An oracle cannot be used for a LP token unless it is registered
     * @param bpt Address of the Balancer Pool token to register
     */
    function registerBpt(address bpt) external onlyOwner {
        if (bpt == address(0)) revert Errors.ZERO_ADDRESS();

        IBalancerV2StablePool pool = IBalancerV2StablePool(bpt);
        (address[] memory tokens, , ) = _vault.getPoolTokens(pool.getPoolId());
        address[] memory rateProviders = pool.getRateProviders();

        uint256 tokenLength = tokens.length;
        // Only ComposableStablePools return BPT within the array of tokens when calling `getPoolTokens`.
        // In order to support all types of stable pools we need to encapsulate `getBPTIndex`
        // in a try/catch block. If the pool is not a ComposableStablePool, we will just
        // set the subTokens to the tokens array that we queried from the vault
        try pool.getBptIndex() returns (uint256 bptIndex) {
            address[] memory subTokens = new address[](tokenLength - 1);
            address[] memory subRateProviders = new address[](tokenLength - 1);

            uint256 index = 0;
            for (uint256 i = 0; i < tokenLength; ++i) {
                if (i != bptIndex) {
                    subTokens[index] = tokens[i];
                    subRateProviders[index] = rateProviders[i];
                    index++;
                }
            }
            _tokenInfo[bpt] = TokenInfo(subTokens, subRateProviders);
        } catch {
            _tokenInfo[bpt] = TokenInfo(tokens, rateProviders);
        }

        emit RegisterLpToken(bpt);
    }

    /**
     * @notice Set the weighted pool oracle
     * @dev Only owner can set the weighted pool oracle
     * @param oracle Address of the oracle to set as the weighted pool oracle
     */
    function setWeightedPoolOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert Errors.ZERO_ADDRESS();

        _weightedPoolOracle = IBaseOracle(oracle);
    }

    /**
     * @notice Fetches the TokenInfo struct of a given LP token
     * @param bpt Balancer Pool Token address
     * @return TokenInfo struct of given LP token
     */
    function getBptInfo(address bpt) public view returns (TokenInfo memory) {
        return _tokenInfo[bpt];
    }

    /// @notice Returns the weighted pool oracle address
    function getWeightedPoolOracle() external view returns (address) {
        return address(_weightedPoolOracle);
    }

    /**
     * @notice Returns the minimum price of a given array of tokens
     * @param tokens An array of tokens within the pool
     * @param rateProviders An array of rate providers associated with the tokens in the pool
     * @param length The length of the array of tokens
     * @return The minimum price of the given array of tokens
     */
    function _getTokensMinPrice(
        address[] memory tokens,
        address[] memory rateProviders,
        uint256 length
    ) internal view returns (uint256) {
        uint256 minPrice;
        address minToken;

        for (uint256 i = 0; i < length; ++i) {
            address minCandidate = tokens[i];
            IRateProvider rateProvider = IRateProvider(rateProviders[i]);
            uint256 minCandidatePrice = _calculateMinCandidatePrice(rateProvider, minCandidate);

            if (minCandidatePrice < minPrice || i == 0) {
                minToken = minCandidate;
                minPrice = minCandidatePrice;
            }
        }

        return minPrice;
    }

    /**
     * @notice Returns the price of a given token
     * @param rateProvider The rate provider associated with the token
     * @param minCandidate The token to calculate the minimum price for
     * @return The price of the given token
     */
    function _calculateMinCandidatePrice(
        IRateProvider rateProvider,
        address minCandidate
    ) internal view returns (uint256) {
        uint256 minCandidatePrice = _getMarketPrice(minCandidate);

        if (address(rateProvider) != address(0)) {
            uint256 rateProviderPrice = rateProvider.getRate();
            minCandidatePrice = minCandidatePrice.divDown(rateProviderPrice);
        }

        return minCandidatePrice;
    }

    /**
     * @notice Returns the price of a given token
     * @dev If the token is not supported by the base oracle, we assume that it is a nested pool
     *    and we will try to get the price from the weighted pool oracle or recursively
     * @param token Address of the token to fetch the price for.
     * @return The Market price of the given token
     */
    function _getMarketPrice(address token) internal view returns (uint256) {
        try _base.getPrice(token) returns (uint256 price) {
            return price;
        } catch {
            try _weightedPoolOracle.getPrice(token) returns (uint256 price) {
                return price;
            } catch {
                return getPrice(token);
            }
        }
    }
}
