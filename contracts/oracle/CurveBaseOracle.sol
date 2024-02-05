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

import "../utils/BlueberryErrors.sol" as Errors;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ICurveOracle } from "../interfaces/ICurveOracle.sol";
import { ICurveRegistry } from "../interfaces/curve/ICurveRegistry.sol";
import { ICurveCryptoSwapRegistry } from "../interfaces/curve/ICurveCryptoSwapRegistry.sol";
import { ICurveAddressProvider } from "../interfaces/curve/ICurveAddressProvider.sol";

/**
 * @title Curve Base Oracle
 * @author BlueberryProtocol
 * @notice Abstract base oracle for Curve LP token price feeds.
 */
abstract contract CurveBaseOracle is ICurveOracle, UsingBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                      structs 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Struct to store token info related to Curve Tokens
     * @param pool Address of the Curve pool.
     * @param tokens tokens in the Curve liquidity pool.
     * @param registryIndex Index of the registry to use for a given pool.
     * @dev This registry index is associated with a given pool type.
     *      0 - Main Curve Registry
     *      5 - CryptoSwap Curve Registry
     *      7 - Meta Curve Registry
     */
    struct TokenInfo {
        address pool;
        address[] tokens;
        uint256 registryIndex;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address provider for Curve-related contracts.
    ICurveAddressProvider private _addressProvider;
    /// @dev Mapping of Curve Lp token to token info.
    mapping(address => TokenInfo) private _tokenInfo;

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
    /* solhint-disable func-name-mixedcase */
    /**
     * @notice Initializes the contract
     * @param addressProvider Address of the curve address provider
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function __CurveBaseOracle_init(ICurveAddressProvider addressProvider, IBaseOracle base, address owner) internal {
        __UsingBaseOracle_init(base, owner);
        _addressProvider = addressProvider;
    }

    /* solhint-enable func-name-mixedcase */

    /**
     * @notice Registers Curve LP token with the oracle.
     * @param crvLp Address of the Curve LP token.
     */
    function registerCurveLp(address crvLp) external onlyOwner {
        if (crvLp == address(0)) revert Errors.ZERO_ADDRESS();
        (address pool, address[] memory tokens, uint256 registryIndex) = _setTokens(crvLp);
        _tokenInfo[crvLp] = TokenInfo(pool, tokens, registryIndex);
    }

    /**
     * @notice Fetches the token info for a given LP token.
     * @param crvLp Curve LP Token address
     * @return TokenInfo struct of given token
     */
    function getTokenInfo(address crvLp) public view returns (TokenInfo memory) {
        return _tokenInfo[crvLp];
    }

    /// @inheritdoc ICurveOracle
    function getPoolInfo(
        address crvLp
    ) external view returns (address pool, address[] memory coins, uint256 virtualPrice) {
        return _getPoolInfo(crvLp);
    }

    /// @inheritdoc ICurveOracle
    function getAddressProvider() external view override returns (ICurveAddressProvider) {
        return _addressProvider;
    }

    /// @dev Logic for getPoolInfo.
    function _getPoolInfo(
        address crvLp
    ) internal view returns (address pool, address[] memory ulTokens, uint256 virtualPrice) {
        TokenInfo memory tokenInfo = getTokenInfo(crvLp);
        if (tokenInfo.pool == address(0)) revert Errors.ORACLE_NOT_SUPPORT_LP(crvLp);

        // If the registry index is 0, use the main Curve registry.
        if (tokenInfo.registryIndex == 0) {
            address registry = _addressProvider.get_registry();

            pool = tokenInfo.pool;
            ulTokens = tokenInfo.tokens;
            virtualPrice = ICurveRegistry(registry).get_virtual_price_from_lp_token(crvLp);

            return (pool, ulTokens, virtualPrice);
        }

        // If the registry index is 5, use the CryptoSwap Curve registry.
        // If the registry index is 7, use the Meta Curve registry.
        if (tokenInfo.registryIndex == 5 || tokenInfo.registryIndex == 7) {
            address registry = _addressProvider.get_address(tokenInfo.registryIndex);

            pool = tokenInfo.pool;
            ulTokens = tokenInfo.tokens;
            virtualPrice = ICurveCryptoSwapRegistry(registry).get_virtual_price_from_lp_token(crvLp);

            return (pool, ulTokens, virtualPrice);
        }
    }

    /**
     * @notice Internal function to fetch the tokens in a given Curve liquidity pool.
     * @param crvLp The address of the Curve liquidity pool token (LP token).
     * @return pool The address of the Curve pool.
     * @return tokens An array of tokens in the Curve liquidity pool.
     * @return registryIndex The index of the registry to use for a given pool.
     */
    function _setTokens(
        address crvLp
    ) internal view returns (address pool, address[] memory tokens, uint256 registryIndex) {
        /// 1. Attempt retrieval from main Curve registry.
        address registry = _addressProvider.get_registry();
        pool = ICurveRegistry(registry).get_pool_from_lp_token(crvLp);

        if (pool != address(0)) {
            (uint256 n, ) = ICurveRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveRegistry(registry).get_coins(pool);

            tokens = new address[](n);
            for (uint256 i = 0; i < n; ++i) {
                tokens[i] = coins[i];
            }

            // Main Curve Registry index: 0
            return (pool, tokens, 0);
        }

        /// 2. Attempt retrieval from CryptoSwap Curve registry.
        registry = _addressProvider.get_address(5);
        pool = ICurveCryptoSwapRegistry(registry).get_pool_from_lp_token(crvLp);

        if (pool != address(0)) {
            uint256 n = ICurveCryptoSwapRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveCryptoSwapRegistry(registry).get_coins(pool);

            tokens = new address[](n);
            for (uint256 i = 0; i < n; ++i) {
                tokens[i] = coins[i];
            }

            // CryptoSwap Curve Registry index: 5
            return (pool, tokens, 5);
        }

        /// 3. Attempt retrieval from Meta Curve registry.
        registry = _addressProvider.get_address(7);
        pool = ICurveCryptoSwapRegistry(registry).get_pool_from_lp_token(crvLp);

        if (pool != address(0)) {
            uint256 n = ICurveCryptoSwapRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveCryptoSwapRegistry(registry).get_coins(pool);

            tokens = new address[](n);
            for (uint256 i = 0; i < n; ++i) {
                tokens[i] = coins[i];
            }

            // Meta Curve Curve Registry index: 7
            return (pool, tokens, 7);
        }

        revert Errors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    /**
     * @notice Internal function to check for reentrancy within Curve pools.
     * @param pool The address of the Curve pool to check.
     * @param numTokens The number of tokens in the pool.
     */
    function _checkReentrant(address pool, uint256 numTokens) internal view virtual returns (bool);
}
