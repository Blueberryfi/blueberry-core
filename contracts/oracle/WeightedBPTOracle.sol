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

import { FixedPoint } from "../libraries//balancer-v2/FixedPoint.sol";
import { VaultReentrancyLib } from "../libraries/balancer-v2/VaultReentrancyLib.sol";

import "../utils/BlueberryErrors.sol" as Errors;
import "../utils/BlueberryConst.sol" as Constants;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IBalancerV2WeightedPool } from "../interfaces/balancer-v2/IBalancerV2WeightedPool.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";

/**
 * @title WeightedBPTOracle
 * @author BlueberryProtocol
 * @notice Oracle contract which privides price feeds of Balancer LP tokens for weighted pools
 */
contract WeightedBPTOracle is UsingBaseOracle, Ownable2StepUpgradeable, IBaseOracle {
    using FixedPoint for uint256;

    IBaseOracle public stablePoolOracle;
    IBalancerVault public immutable VAULT;

    // Protects the oracle from being manipulated via read-only reentrancy
    modifier balancerNonReentrant() {
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

    /**
     * @notice Return the USD value of given Balancer Lp, with 18 decimals of precision.
     * @param token The ERC-20 token to check the value.
     */
    function getPrice(address token) public override balancerNonReentrant returns (uint256) {
        IBalancerV2WeightedPool pool = IBalancerV2WeightedPool(token);

        (address[] memory tokens, , ) = VAULT.getPoolTokens(pool.getPoolId());

        uint256[] memory weights = pool.getNormalizedWeights();

        uint256 length = weights.length;
        uint256 mult = Constants.PRICE_PRECISION;
        uint256 invariant = pool.getInvariant();

        for (uint256 i; i < length; ++i) {
            uint256 price = _getMarketPrice(tokens[i]);
            uint256 weight = weights[i];
            mult = mult.mulDown((price.divDown(weight)).powDown(weight));
        }

        uint256 totalSupply = pool.totalSupply();

        return invariant.mulDown(mult).divDown(totalSupply);
    }

    /**
     * @notice Set the stable pool oracle
     * @dev Only owner can set the stable pool oracle
     * @param oracle Address of the oracle to set as the stable pool oracle
     */
    function setStablePoolOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert Errors.ZERO_ADDRESS();

        stablePoolOracle = IBaseOracle(oracle);
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
