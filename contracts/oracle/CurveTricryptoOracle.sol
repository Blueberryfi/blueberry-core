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

import "./CurveBaseOracle.sol";

/**
 * @author BlueberryProtocol
 * @title Curve Volatile Oracle
 * @notice Oracle contract which privides price feeds of Curve volatile pool LP tokens
 */
contract CurveTricryptoOracle is CurveBaseOracle {
    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) CurveBaseOracle(base_, addressProvider_) {}

    function _checkReentrant(address _pool, uint256) internal override {
        ICurvePool pool = ICurvePool(_pool);
        pool.claim_admin_fees();
    }

    /**
     * @notice Return the USD value of given Curve Lp, with 18 decimals of precision.
     * @param crvLp The ERC-20 Curve LP token to check the value.
     */
    function getPrice(address crvLp) external override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);
        _checkReentrant(pool, tokens.length);

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
        revert BlueBerryErrors.ORACLE_NOT_SUPPORT_LP(crvLp);
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
}
