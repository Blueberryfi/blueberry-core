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

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

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
abstract contract CurveBaseOracle is ICurveOracle, UsingBaseOracle, Ownable {
    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address provider for Curve-related contracts.
    ICurveAddressProvider private immutable _addressProvider;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor initializes the CurveBaseOracle with the provided parameters.
     * @param base The address of the base oracle.
     * @param addressProvider The address of the curve address provider.
     */
    constructor(IBaseOracle base, ICurveAddressProvider addressProvider) UsingBaseOracle(base) {
        _addressProvider = addressProvider;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

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
        /// 1. Attempt retrieval from main Curve registry.
        address registry = _addressProvider.get_registry();
        pool = ICurveRegistry(registry).get_pool_from_lp_token(crvLp);
        if (pool != address(0)) {
            (uint256 n, ) = ICurveRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveRegistry(registry).get_coins(pool);

            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; ++i) {
                ulTokens[i] = coins[i];
            }

            virtualPrice = ICurveRegistry(registry).get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        /// 2. Attempt retrieval from CryptoSwap Curve registry.
        registry = _addressProvider.get_address(5);
        pool = ICurveCryptoSwapRegistry(registry).get_pool_from_lp_token(crvLp);

        if (pool != address(0)) {
            uint256 n = ICurveCryptoSwapRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveCryptoSwapRegistry(registry).get_coins(pool);

            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; ++i) {
                ulTokens[i] = coins[i];
            }

            virtualPrice = ICurveCryptoSwapRegistry(registry).get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        /// 3. Attempt retrieval from Meta Curve registry.
        registry = _addressProvider.get_address(7);
        pool = ICurveCryptoSwapRegistry(registry).get_pool_from_lp_token(crvLp);

        if (pool != address(0)) {
            uint256 n = ICurveCryptoSwapRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveCryptoSwapRegistry(registry).get_coins(pool);

            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; ++i) {
                ulTokens[i] = coins[i];
            }

            virtualPrice = ICurveCryptoSwapRegistry(registry).get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        revert Errors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    /**
     * @notice Internal function to check for reentrancy within Curve pools.
     * @param pool The address of the Curve pool to check.
     * @param numTokens The number of tokens in the pool.
     */
    function _checkReentrant(address pool, uint256 numTokens) internal virtual;
}
