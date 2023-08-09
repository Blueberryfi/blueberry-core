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

import "./UsingBaseOracle.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IBalancerVault.sol";
import "../libraries/FixedPointMathLib.sol";

/// @title Composable Stable Balancer LP Oracle
/// @author BlueberryProtocol
/// @notice Oracle contract which privides price feeds of Composable Stable Balancer LP tokens
contract CompStableBPTOracle is UsingBaseOracle, IBaseOracle {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructs the `CompStableBPTOracle` with a reference to a base oracle.
    /// @param _base The base oracle used for fetching price data.
    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Provides the USD value of the given Balancer LP token, with 18 decimals of precision.
    /// @param token The address of the Balancer LP token whose USD value is to be fetched.
    /// @return The USD value of the specified Balancer LP token.
    function getPrice(address token) external override returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);
        IBalancerVault vault = IBalancerVault(pool.getVault());

        /// Use a reentrancy guard to protect against potential flashloan attacks.
        checkReentrancy(vault);

        /// Get the list of tokens from the associated Balancer pool.
        (address[] memory tokens, , ) = vault
            .getPoolTokens(pool.getPoolId());

        uint256 length = tokens.length;
        uint256 minPrice = type(uint256).max;
        /// Iterate over tokens to get their respective prices and determine the minimum.
        for(uint256 i; i != length; ++i) {
            if (tokens[i] == token) continue;
            uint256 price = base.getPrice(tokens[i]);
            minPrice = (price < minPrice) ? price : minPrice;
        }
        /// Return the USD value of the LP token by multiplying the minimum price with the rate from the pool.
        return minPrice.mulWadDown(pool.getRate());
    }

    /// @dev Checks for reentrancy by calling a no-op function on the Balancer Vault.
    ///      This is a preventative measure against potential reentrancy attacks.
    /// @param vault The Balancer Vault contract instance.
    function checkReentrancy(IBalancerVault vault) internal {
        vault.manageUserBalance(new IBalancerVault.UserBalanceOp[](0));
    }
}
