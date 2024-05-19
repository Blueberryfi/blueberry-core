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

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseAdapter } from "./BaseAdapter.sol";
import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IBalancerV2Pool } from "../interfaces/balancer-v2/IBalancerV2Pool.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { IBalancerPriceOracle } from "../interfaces/balancer-v2/IBalancerPriceOracle.sol";

/**
 * @author BlueberryProtocol
 * @title BalancerV2 Spot Oracle
 * @notice Oracle contract which provides price feeds of tokens from Balancer V2 WeightedPool2Tokens
 *         and Meta Stable Pools
 * @dev The Oracle contract is used soley for calculating the spot price of tokens that do not have
 *      a direct price feed from an external oracle.It should be noted that the main purpose of
 *      this contract is to provide a spot price for tokens like AURA which are extra rewards in some
 *      Blueberry strategies.
 */
contract BalancerV2SpotOracle is IBaseOracle, UsingBaseOracle, BaseAdapter {
    /*//////////////////////////////////////////////////////////////////////////
                                      Structs
    //////////////////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////////////////
                                      Storage
    //////////////////////////////////////////////////////////////////////////*/

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
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IBalancerVault vault, IBaseOracle base, address owner) external initializer {
        __UsingBaseOracle_init(base, owner);
        _vault = vault;
    }

    /**
     * @notice Calculates the Spot price for an
     * @param token The
     */
    function getPrice(address token) public view override returns (uint256) {
        TokenInfo memory tokenInfo = _tokenInfo[token];

        if (tokenInfo.pool == address(0)) {
            revert Errors.NO_ORACLE_ROUTE(token);
        }

        IBalancerPriceOracle.OracleAverageQuery[] memory queries = new IBalancerPriceOracle.OracleAverageQuery[](1);
        queries[0] = IBalancerPriceOracle.OracleAverageQuery(
            IBalancerPriceOracle.Variable.PAIR_PRICE,
            tokenInfo.twapDuration,
            0
        );

        uint256[] memory results = IBalancerPriceOracle(tokenInfo.pool).getTimeWeightedAverage(queries);
        uint256 spotPrice = tokenInfo.isTokenZero ? 1e36 / results[0] : results[0];

        return (spotPrice * _base.getPrice(tokenInfo.quoteToken)) / Constants.PRICE_PRECISION;
    }

    function registerToken(address token, address pool, uint256 duration) external onlyOwner {
        if (token == address(0) || pool == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        if (_tokenInfo[token].pool == pool) {
            revert Errors.TOKEN_BPT_ALREADY_REGISTERED(token, pool);
        }

        if (duration > type(uint16).max) {
            revert Errors.VALUE_OUT_OF_RANGE();
        }

        (address[] memory tokens, , ) = _vault.getPoolTokens(IBalancerV2Pool(pool).getPoolId());

        if (tokens.length != 2) {
            revert Errors.ORACLE_NOT_SUPPORT_LP(pool);
        }

        (address quoteToken, bool isTokenOne) = tokens[0] == token ? (tokens[1], true) : (tokens[0], false);

        _tokenInfo[token] = TokenInfo(pool, quoteToken, uint16(duration), isTokenOne);

        uint256 price = getPrice(token);
        if (price == 0) revert Errors.PRICE_FAILED(token);
    }
}
