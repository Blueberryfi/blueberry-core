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

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "./UsingBaseOracle.sol";
import "../utils/BlueBerryErrors.sol" as BBErrors;

import "../interfaces/IBaseOracle.sol";
import "../interfaces/balancer/IBalancerPool.sol";
import "../interfaces/balancer/IBalancerVault.sol";
import "../libraries/balancer/FixedPoint.sol";
import "../libraries/balancer/VaultReentrancyLib.sol";

/// @title WeightedBPTOracle
/// @dev Provides price feeds for Weighted Balancer LP tokens.
/// @author BlueberryProtocol
///
/// This contract fetches and computes the value of a Balancer LP token in terms of USD.
/// It uses the base oracle to fetch underlying token values and then computes the
/// value of the LP token using Balancer's formula.
contract WeightedBPTOracle is UsingBaseOracle, Ownable2StepUpgradeable, IBaseOracle {
    using FixedPoint for uint256;

    IBaseOracle public stablePoolOracle;
    IBalancerVault public immutable VAULT;

    // Protects the oracle from being manipulated via read-only reentrancy
    modifier balancerNonReentrant {
        VaultReentrancyLib.ensureNotInVaultContext(VAULT);
        _;
    }
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(
        IBalancerVault _vault,
        IBaseOracle _base,
        address _owner
    ) UsingBaseOracle(_base) Ownable2StepUpgradeable() {
        VAULT = _vault;
        _transferOwnership(_owner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function setStablePoolOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert BBErrors.ZERO_ADDRESS();

        stablePoolOracle = IBaseOracle(oracle);
    }


    /// @notice Return the USD value of given Balancer Lp, with 18 decimals of precision.
    /// @param token The ERC-20 token to check the value.
    function getPrice(address token) public override balancerNonReentrant returns (uint256) {
        IBalancerPool pool = IBalancerPool(token);

        (address[] memory tokens, , ) = VAULT
            .getPoolTokens(pool.getPoolId());

        uint256[] memory weights = pool.getNormalizedWeights();

        uint256 length = weights.length;
        uint256 mult = 1e18;
        uint256 invariant = pool.getInvariant();

        for (uint256 i; i < length; ++i) {
            uint256 price = _getMarketPrice(tokens[i]);
            uint256 weight = weights[i];
            mult = mult.mulDown((price.divDown(weight)).powDown(weight));
        }
        
        uint256 totalSupply = pool.totalSupply();

        return invariant.divDown(totalSupply).mulDown(mult);
    }

    /**
     * @notice Returns the price of a given token
     * @dev If the token is not supported by the base oracle, we assume that it is a nested pool
     *    and we will try to get the price from the stable pool oracle or recursively
     * @param token Address of the token to fetch the price for.
     */
    function _getMarketPrice(address token) internal returns (uint256) {
        try base.getPrice(token) returns (uint256 price) {
            return price;
        } catch {
            try stablePoolOracle.getPrice(token) returns (uint256 price) {
                return price;
            } catch {
                return getPrice(token);
            }
        }
    }
}
