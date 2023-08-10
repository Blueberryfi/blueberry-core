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

/// @title Curve Volatile Oracle
/// @author BlueberryProtocol 
/// @notice Oracle contract which privides price feeds of Curve volatile pool LP tokens
contract CurveTricryptoOracle is CurveBaseOracle {
    
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructor initializes the CurveBaseOracle with the provided parameters.
    /// @param base_ The address of the base oracle.
    /// @param addressProvider_ The address of the curve address provider.
    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) CurveBaseOracle(base_, addressProvider_) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Overrides the base oracle's reentrancy check.
    /// @param _pool The address of the pool to check.
    /// @param (unnamed) Unused parameter for overriding.
    function _checkReentrant(address _pool, uint256) internal override {
        ICurvePool pool = ICurvePool(_pool);
        pool.claim_admin_fees();
    }

    /// @notice Returns the USD value of the specified Curve LP token with 18 decimals of precision.
    /// @dev If the length of tokens is not 3, the function will revert.
    /// @param crvLp The ERC-20 Curve LP token address.
    /// @return The USD value of the Curve LP token.
    function getPrice(address crvLp) external override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);
        _checkReentrant(pool, tokens.length);

        /// Check if the token list length is 3 (tricrypto)
        if (tokens.length == 3) {
            /// tokens[2] is WETH
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

    /// @dev Calculates the LP price using provided token prices and virtual price.
    /// @param virtualPrice The virtual price from the pool.
    /// @param p1 Price of the first token.
    /// @param p2 Price of the second token (usually ETH).
    /// @param p3 Price of the third token.
    /// @return The calculated LP price.
    function lpPrice(
        uint256 virtualPrice,
        uint256 p1,
        uint256 p2,
        uint256 p3
    ) internal pure returns (uint256) {
        return (3 * virtualPrice * cubicRoot(((p1 * p2) / 1e18) * p3)) / 1e18;
    }

    /// @dev Calculates the cubic root of the provided value using the Newton-Raphson method.
    /// @param x The value to find the cubic root for.
    /// @return The calculated cubic root.

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
