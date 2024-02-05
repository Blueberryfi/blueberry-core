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
contract WeightedBPTOracle is IBaseOracle, UsingBaseOracle {
    using FixedPoint for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to Balancer Pool tokens
     * @param tokens An array of tokens within the pool
     * @param normalizedWeights An array of normalized weights associated with the tokens in the pool
     */
    struct TokenInfo {
        address[] tokens;
        uint256[] normalizedWeights;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Stable pool oracle
    IBaseOracle private _stablePoolOracle;
    /// @notice Balancer Vault
    IBalancerVault private _vault;
    /// @notice Mapping of registered bpt tokens to their token info
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

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseOracle
    function getPrice(address token) public view override balancerNonReentrant returns (uint256) {
        IBalancerV2WeightedPool pool = IBalancerV2WeightedPool(token);

        TokenInfo memory tokenInfo = getBptInfo(token);

        address[] memory tokens = tokenInfo.tokens;
        uint256[] memory weights = tokenInfo.normalizedWeights;

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
     * @notice Register Balancer Pool token to oracle
     * @dev Stores persistent data of Balancer Pool token
     * @dev An oracle cannot be used for a LP token unless it is registered
     * @param bpt Address of the Balancer Pool token to register
     */
    function registerBpt(address bpt) external onlyOwner {
        if (bpt == address(0)) revert Errors.ZERO_ADDRESS();

        IBalancerV2WeightedPool pool = IBalancerV2WeightedPool(bpt);
        (address[] memory tokens, , ) = _vault.getPoolTokens(pool.getPoolId());
        uint256[] memory weights = pool.getNormalizedWeights();

        _tokenInfo[bpt] = TokenInfo(tokens, weights);
    }

    /**
     * @notice Set the stable pool oracle
     * @dev Only owner can set the stable pool oracle
     * @param oracle Address of the oracle to set as the stable pool oracle
     */
    function setStablePoolOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert Errors.ZERO_ADDRESS();

        _stablePoolOracle = IBaseOracle(oracle);
    }

    /**
     * @notice Fetches the TokenInfo struct of a given LP token
     * @param bpt Balancer Pool Token address
     * @return TokenInfo struct of given LP token
     */
    function getBptInfo(address bpt) public view returns (TokenInfo memory) {
        return _tokenInfo[bpt];
    }

    /// @notice Returns the stable pool oracle address
    function getStablePoolOracle() external view returns (address) {
        return address(_stablePoolOracle);
    }

    /**
     * @notice Returns the price of a given token
     * @dev If the token is not supported by the base oracle, we assume that it is a nested pool
     *    and we will try to get the price from the stable pool oracle or recursively
     * @param token Address of the token to fetch the price for.
     * @return The Market price of the given token
     */
    function _getMarketPrice(address token) internal view returns (uint256) {
        try _base.getPrice(token) returns (uint256 price) {
            return price;
        } catch {
            try _stablePoolOracle.getPrice(token) returns (uint256 price) {
                return price;
            } catch {
                return getPrice(token);
            }
        }
    }
}
