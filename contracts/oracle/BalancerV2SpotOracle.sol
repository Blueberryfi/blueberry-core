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

import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseAdapter } from "./BaseAdapter.sol";
import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IBalancerV2WeightedPool } from "../interfaces/balancer-v2/IBalancerV2WeightedPool.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { IBalancerPriceOracle } from "../interfaces/balancer-v2/IBalancerPriceOracle.sol";

/**
 * @author BlueberryProtocol
 * @title BalancerV2 Spot Oracle
 * @dev The Oracle contract is used soley for calculating the spot price of tokens that do not have
 *      a direct price feed from an external oracle. The contract is designed to work with Balancer V2
 *      Weighted Pools. It should be noted that the main purpose of this contract is to provide a spot
 *      price for tokens like AURA which are extra rewards in some Blueberry strategies.
 * @dev This oracle should only be used for WeightedPool2Tokens and Meta
 * @notice Oracle contract which provides price feeds of tokens from Balancer V2 WeightedPool2Tokens
 */
contract BalancerV2SpotOracle is IBaseOracle, UsingBaseOracle, BaseAdapter {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    /**
     * @dev Struct to store token info related to Balancer Pools
     * @param Pool The address of the Balancer pool to derive the tokens spot price from
     * @param quoteToken The token paired against the asset whos price is being calculated
     * @param twapDuration
     */
    struct TokenInfo {
        address pool;
        address quoteToken;
        uint16 twapDuration;
        bool isTokenZero;
    }

    /// @notice Balancer V2 Vault
    IBalancerVault private _vault;

    /// @notice Maps token addresses to their corresponding token info
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

    /**
     * @notice Initializes the contract
     * @param vault Instance of the Balancer V2 Vault
     * @param baseOracle The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IBalancerVault vault, IBaseOracle baseOracle, address owner) external initializer {
        __UsingBaseOracle_init(baseOracle, owner);
        _vault = vault;
    }

    /**
     * @notice Calculates the Spot price for an
     * @param token The
     */
    function getPrice(address token) public view override returns (uint256) {
        TokenInfo memory tokenInfo = _tokenInfo[token];

        if (tokenInfo.tokens.length == 0) {
            revert Errors.TOKEN_NOT_REGISTERED(token);
        }

        IBalancerPriceOracle.OracleAverageQuery[] memory queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery(
            IBalancerPriceOracle.Variable.PAIR_PRICE,
            tokenInfo.twapDuration,
            0
        );

        uint256[] memory results = IBalancerPriceOracle(tokenInfo.pool).getTimeWeightedAverage(queries);
        uint256 spotPrice = tokenInfo.isTokenZero ? 1e36 / results[0] : results[0];

        return (spotPrice * _baseOracle.getPrice(tokenInfo.quoteToken)) / Constants.PRICE_PRECISION;
    }

    function registerToken(address token, address pool, uint256 duration) external {
        if (token == address(0) || pool == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        if (_weightedPools[token].contains(pool)) {
            revert Errors.TOKEN_BPT_ALREADY_REGISTERED(token, pool);
        }

        (address[] memory tokens, , ) = _vault.getPoolTokens(weightedPool.getPoolId());

        if (tokens.length != 2) {
            revert Errors.ORACLE_NOT_SUPPORT_LP(pool);
        }

        (address quoteToken, bool isTokenOne) = tokens[0] == token ? (tokens[0], true) : (tokens[1], false);

        _tokenInfo[token] = TokenInfo(pool, quoteToken, duration, isTokenOne);

        uint256 price = getPrice(token);

        if (price == 0) revert Errors.PRICE_FAILED();
    }
}
