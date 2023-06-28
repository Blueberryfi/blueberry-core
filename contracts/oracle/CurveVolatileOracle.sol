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
import "../libraries/balancer/FixedPoint.sol";
import "../interfaces/ICurveOracle.sol";
import "../interfaces/curve/ICurveRegistry.sol";
import "../interfaces/curve/ICurveCryptoSwapRegistry.sol";
import "../interfaces/curve/ICurveAddressProvider.sol";
import "../interfaces/curve/ICurvePool.sol";

/**
 * @author BlueberryProtocol
 * @title Curve Volatile Oracle
 * @notice Oracle contract which privides price feeds of Curve volatile pool LP tokens
 */
contract CurveVolatileOracle is UsingBaseOracle, ICurveOracle, Ownable {
    using FixedPoint for uint256;

    uint256 constant DECIMALS = 10 ** 18;
    uint256 constant USD_FEED_DECIMALS = 10 ** 8;

    ICurveAddressProvider public immutable addressProvider;

    event CurveLpRegistered(
        address crvLp,
        address pool,
        address[] underlyingTokens
    );

    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) UsingBaseOracle(base_) {
        addressProvider = addressProvider_;
    }

    /**
     * @dev Get Curve pool info of given curve lp
     * @param crvLp Curve LP token address to get the pool info of
     * @return pool The address of curve pool
     * @return ulTokens Underlying tokens of curve pool
     * @return virtualPrice Virtual price of curve pool
     */
    function _getPoolInfo(
        address crvLp
    )
        internal
        returns (address pool, address[] memory ulTokens, uint256 virtualPrice)
    {
        // 1. Try from main registry
        address registry = addressProvider.get_registry();
        pool = ICurveRegistry(registry).get_pool_from_lp_token(crvLp);
        if (pool != address(0)) {
            (uint256 n, ) = ICurveRegistry(registry).get_n_coins(pool);
            address[8] memory coins = ICurveRegistry(registry).get_coins(pool);
            ulTokens = new address[](n);
            for (uint256 i = 0; i < n; i++) {
                ulTokens[i] = coins[i];
            }
            _checkReentrant(pool);
            virtualPrice = ICurveRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        // 2. Try from CryptoSwap Registry
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
            _checkReentrant(pool);
            virtualPrice = ICurveCryptoSwapRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        // 3. Try from Metaregistry
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
            _checkReentrant(pool);
            virtualPrice = ICurveCryptoSwapRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        revert BlueBerryErrors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    function _checkReentrant(address _pool) internal {
        ICurvePool pool = ICurvePool(_pool);
        pool.claim_admin_fees();
    }

    function getPoolInfo(
        address crvLp
    )
        external
        returns (address pool, address[] memory coins, uint256 virtualPrice)
    {
        return _getPoolInfo(crvLp);
    }

    /**
     * @notice Return the USD value of given Curve Lp, with 18 decimals of precision.
     * @param crvLp The ERC-20 Curve LP token to check the value.
     */
    function getPrice(address crvLp) external override returns (uint256) {
        (, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);

        if (tokens.length != 2) {
            revert BlueBerryErrors.ORACLE_NOT_SUPPORT_LP(crvLp);
        }

        uint256 px0 = base.getPrice(tokens[0]);
        uint256 px1 = base.getPrice(tokens[1]);

        uint256 product = px0 * DECIMALS / USD_FEED_DECIMALS;
        product = product.mulDown(px1 * DECIMALS / USD_FEED_DECIMALS);

        uint256 answer = product.powDown(DECIMALS / 2).mulDown(2 * virtualPrice);

        return answer * USD_FEED_DECIMALS / DECIMALS;
    }
}
