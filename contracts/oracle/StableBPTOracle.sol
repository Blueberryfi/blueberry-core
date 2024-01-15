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
contract StableBPTOracle is UsingBaseOracle, Ownable2StepUpgradeable, IBaseOracle {
    using FixedPoint for uint256;

    IBaseOracle public weightedPoolOracle;
    IBalancerVault private immutable _VAULT;

    // Protects the oracle from being manipulated via read-only reentrancy
    modifier balancerNonReentrant() {
        VaultReentrancyLib.ensureNotInVaultContext(_VAULT);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(IBalancerVault vault, IBaseOracle base, address owner) UsingBaseOracle(base) Ownable2StepUpgradeable() {
        _VAULT = vault;
        _transferOwnership(owner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Return the USD value of given Balancer Lp, with 18 decimals of precision.
     * @param token The ERC-20 token to check the value.
     */
    function getPrice(address token) public override balancerNonReentrant returns (uint256) {
        uint256 minPrice;
        IBalancerV2StablePool pool = IBalancerV2StablePool(token);

        (address[] memory tokens, , ) = _VAULT.getPoolTokens(pool.getPoolId());
        address[] memory rateProviders = pool.getRateProviders();

        // Only ComposableStablePools return BPT within the array of tokens when calling `getPoolTokens`.
        // In order to support all types of stable pools we need to encapsulate `getBPTIndex`
        // in a try/catch block. If the pool is not a ComposableStablePool, we will just
        // set the subTokens to the tokens array that we queried from the vault
        try pool.getBptIndex() returns (uint256 bptIndex) {
            address[] memory subTokens = new address[](tokens.length - 1);
            address[] memory subRateProviders = new address[](tokens.length - 1);

            uint256 index = 0;
            for (uint256 i = 0; i < tokens.length; ++i) {
                if (i != bptIndex) {
                    subTokens[index] = tokens[i];
                    subRateProviders[index] = rateProviders[i];
                    index++;
                }
            }

            minPrice = _getTokensMinPrice(subTokens, subRateProviders);
        } catch {
            minPrice = _getTokensMinPrice(tokens, rateProviders);
        }

        uint256 rate = pool.getRate();

        return minPrice.mulDown(rate);
    }

    /**
     * @notice Set the weighted pool oracle
     * @dev Only owner can set the weighted pool oracle
     * @param oracle Address of the oracle to set as the weighted pool oracle
     */
    function setWeightedPoolOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert Errors.ZERO_ADDRESS();

        weightedPoolOracle = IBaseOracle(oracle);
    }

    /**
     * @notice Returns the minimum price of a given array of tokens
     * @param tokens An array of tokens within the pool
     * @param rateProviders An array of rate providers associated with the tokens in the pool
     */
    function _getTokensMinPrice(address[] memory tokens, address[] memory rateProviders) internal returns (uint256) {
        uint256 minPrice;
        address minToken;
        uint256 length = tokens.length;

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
     */
    function _calculateMinCandidatePrice(IRateProvider rateProvider, address minCandidate) internal returns (uint256) {
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
     */
    function _getMarketPrice(address token) internal returns (uint256) {
        try _base.getPrice(token) returns (uint256 price) {
            return price;
        } catch {
            try weightedPoolOracle.getPrice(token) returns (uint256 price) {
                return price;
            } catch {
                return getPrice(token);
            }
        }
    }
}
