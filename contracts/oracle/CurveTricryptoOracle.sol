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

import "../utils/BlueBerryErrors.sol" as Errors;
import "./UsingBaseOracle.sol";
import "../libraries/BBMath.sol";
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
contract CurveTricryptoOracle is UsingBaseOracle, ICurveOracle, Ownable {
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
            _checkReentrant(pool, n);
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
            _checkReentrant(pool, n);
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
            _checkReentrant(pool, n);
            virtualPrice = ICurveCryptoSwapRegistry(registry)
                .get_virtual_price_from_lp_token(crvLp);
            return (pool, ulTokens, virtualPrice);
        }

        revert Errors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    function _checkReentrant(address _pool, uint256 _numTokens) internal {
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

        if (tokens.length == 3) {
            // tokens[2] is WETH
            uint256 ethPrice = base.getPrice(tokens[2]);
            return
                (lpPrice(
                    virtualPrice,
                    base.getPrice(tokens[1]),
                    ethPrice,
                    base.getPrice(tokens[0])
                ) * 1e18) / ethPrice;
        }
        revert Errors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    function lpPrice(
        uint256 virtualPrice,
        uint256 p1,
        uint256 p2,
        uint256 p3
    ) internal pure returns (uint256) {
        return (3 * virtualPrice * cubicRoot(((p1 * p2) / 1e18) * p3)) / 1e18;
    }

    function cubicRoot(uint256 x) internal pure returns (uint256) {
        uint256 D = x / 1e18;
        for (uint256 i; i < 255; ) {
            uint256 D_prev = D;
            D = (D * (2e18 + ((((x / D) * 1e18) / D) * 1e18) / D)) / (3e18);
            uint256 diff = (D > D_prev) ? D - D_prev : D_prev - D;
            if (diff < 2 || diff * 1e18 < D) return D;
            unchecked {
                ++i;
            }
        }
        revert("Did Not Converge");
    }

    receive() external payable {}
}
