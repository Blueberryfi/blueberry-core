// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../utils/BlueBerryErrors.sol" as BlueBerryErrors;
import "./UsingBaseOracle.sol";
import "../interfaces/ICurveOracle.sol";
import "../interfaces/curve/ICurveRegistry.sol";
import "../interfaces/curve/ICurveCryptoSwapRegistry.sol";
import "../interfaces/curve/ICurveAddressProvider.sol";
import "../interfaces/curve/ICurvePool.sol";

/// @title Curve Base Oracle
/// @author BlueberryProtocol
/// @notice Abstract base oracle for Curve LP token price feeds.
abstract contract CurveBaseOracle is UsingBaseOracle, ICurveOracle, Ownable {

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/
    
    /// Address provider for Curve-related contracts.
    ICurveAddressProvider public immutable addressProvider;

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS 
    //////////////////////////////////////////////////////////////////////////*/

    /// Emitted when a Curve LP token is registered with its associated pool and underlying tokens.
    event CurveLpRegistered(
        address crvLp,
        address pool,
        address[] underlyingTokens
    );

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructor initializes the CurveBaseOracle with the provided parameters.
    /// @param base_ The address of the base oracle.
    /// @param addressProvider_ The address of the curve address provider.
    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) UsingBaseOracle(base_) {
        addressProvider = addressProvider_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Fetches Curve pool information for a given Curve LP token address.
    /// @param crvLp Curve LP token address.
    /// @return pool The address of the associated Curve pool.
    /// @return ulTokens Underlying tokens of the Curve pool.
    /// @return virtualPrice Virtual price of the Curve pool.
    function _getPoolInfo(
        address crvLp
    )
        internal
        returns (address pool, address[] memory ulTokens, uint256 virtualPrice)
    {
        /// 1. Attempt retrieval from main Curve registry.
        address registry = addressProvider.get_registry();
        pool = ICurveRegistry(registry).get_pool_from_lp_token(crvLp);
        if (pool != address(0)) {
            (uint256 n, ) = ICurveRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveRegistry(registry).get_coins(pool);
            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; i++) {
                ulTokens[i] = coins[i];
            }
            virtualPrice = ICurveRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        /// 2. Attempt retrieval from CryptoSwap Curve registry.
        registry = addressProvider.get_address(5);
        pool = ICurveCryptoSwapRegistry(registry).get_pool_from_lp_token(crvLp);
        if (pool != address(0)) {
            uint256 n = ICurveCryptoSwapRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveCryptoSwapRegistry(registry)
                .get_coins(pool);
            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; i++) {
                ulTokens[i] = coins[i];
            }
            virtualPrice = ICurveCryptoSwapRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        /// 3. Attempt retrieval from Meta Curve registry.
        registry = addressProvider.get_address(7);
        pool = ICurveCryptoSwapRegistry(registry).get_pool_from_lp_token(crvLp);
        if (pool != address(0)) {
            uint256 n = ICurveCryptoSwapRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveCryptoSwapRegistry(registry)
                .get_coins(pool);
            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; i++) {
                ulTokens[i] = coins[i];
            }
            virtualPrice = ICurveCryptoSwapRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        revert BlueBerryErrors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    /// @dev Internal function to check for reentrancy issues with Curve pools.
    /// @param _pool The address of the Curve pool to check.
    /// @param _numTokens The number of tokens in the pool.
    function _checkReentrant(address _pool, uint256 _numTokens) internal virtual;

    /// @notice Fetches Curve pool details for the provided Curve LP token.
    /// @param crvLp The Curve LP token address.
    /// @return pool The Curve pool address.
    /// @return coins The list of underlying tokens in the pool.
    /// @return virtualPrice The virtual price of the Curve pool.
    function getPoolInfo(
        address crvLp
    )
        external
        returns (address pool, address[] memory coins, uint256 virtualPrice)
    {
        return _getPoolInfo(crvLp);
    }

    /// @notice Fetches the USD value of a given Curve LP token.
    /// @dev To be implemented in inheriting contracts.
    /// @param crvLp The Curve LP token address.
    /// @return The USD value of the Curve LP token.
    function getPrice(address crvLp) external virtual returns (uint256);
}
