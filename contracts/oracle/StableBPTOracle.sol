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

import "./UsingBaseOracle.sol";
import "../interfaces/IBaseOracle.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IRateProvider.sol";
import "../interfaces/balancer/IBalancerVault.sol";
import "../libraries/FixedPointMathLib.sol";
import "hardhat/console.sol";

/// @title Stable Balancer LP Oracle
/// @author BlueberryProtocol
/// @notice Oracle contract which privides price feeds of Stable Balancer LP tokens
contract StableBPTOracle is UsingBaseOracle, IBaseOracle {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(IBaseOracle _base) UsingBaseOracle(_base) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Return the USD value of given Balancer Lp, with 18 decimals of precision.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) external override returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);
        IBalancerVault vault = IBalancerVault(pool.getVault());

        // Reentrancy guard to prevent flashloan attack
        checkReentrancy(vault);

        (address[] memory tokens, , ) = vault.getPoolTokens(pool.getPoolId());
        address[] memory rateProviders = pool.getRateProviders();

        uint256 length = tokens.length;
        uint256 minPrice = type(uint256).max;
        for (uint256 i; i < length; ++i) {
            if (tokens[i] == token) {
                continue;
            }
            uint256 price = base.getPrice(tokens[i]);
            address rateProvider = rateProviders[i];
            if (rateProvider != address(0)) {
                price = price.divWadDown(IRateProvider(rateProvider).getRate());
            }
            minPrice = (price < minPrice) ? price : minPrice;
        }
        return minPrice.mulWadDown(pool.getRate());
    }

    /// @dev Checks for reentrancy by calling a no-op function on the Balancer Vault.
    ///      This is a preventative measure against potential reentrancy attacks.
    /// @param vault The Balancer Vault contract instance.
    function checkReentrancy(IBalancerVault vault) internal {
        vault.manageUserBalance(new IBalancerVault.UserBalanceOp[](0));
    }
}
