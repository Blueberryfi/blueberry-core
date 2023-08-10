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

/// @title Curve Stable Oracle
/// @author BlueberryProtocol
/// @notice Oracle contract that provides price feeds for Curve stable LP tokens.
contract CurveStableOracle is CurveBaseOracle {

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructor initializes the CurveBaseOracle with the provided parameters.
    /// @param base_ The address of the base oracle.
    /// @param addressProvider_ The address of the curve address provider.
    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) CurveBaseOracle(base_, addressProvider_) {
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Overrides the base oracle's reentrancy check based on the number of tokens.
    /// @param _pool The address of the pool to check.
    /// @param _numTokens The number of tokens in the pool.
    function _checkReentrant(address _pool, uint256 _numTokens) internal override {
        ICurvePool pool = ICurvePool(_pool);
        if (_numTokens == 2) {
            uint256[2] memory amounts;
            pool.remove_liquidity(0, amounts);
        } else if (_numTokens == 3) {
            uint256[3] memory amounts;
            pool.remove_liquidity(0, amounts);
        } else if (_numTokens == 4) {
            uint256[4] memory amounts;
            pool.remove_liquidity(0, amounts);
        }
    }

    /// @notice Returns the USD value of the specified Curve LP token with 18 decimals of precision.
    /// @dev Uses the minimum underlying token price for calculation.
    /// @param crvLp The ERC-20 Curve LP token address.
    /// @return The USD value of the Curve LP token.
    function getPrice(address crvLp) external override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);
        _checkReentrant(pool, tokens.length);

        uint256 minPrice = type(uint256).max;
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            uint256 tokenPrice = base.getPrice(tokens[idx]);
            if (tokenPrice < minPrice) minPrice = tokenPrice;
        }

        // Calculate LP token price using the minimum underlying token price
        return (minPrice * virtualPrice) / 1e18;
    }

    /// @notice Fallback function to receive Ether.
    receive() external payable {}
}
