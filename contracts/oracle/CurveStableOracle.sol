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
 * @title Curve Stable Oracle
 * @notice Oracle contract which privides price feeds of Curve stable Lp tokens
 */
contract CurveStableOracle is CurveBaseOracle {
    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) CurveBaseOracle(base_, addressProvider_) {
    }

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

    /**
     * @notice Return the USD value of given Curve Lp, with 18 decimals of precision.
     * @param crvLp The ERC-20 Curve LP token to check the value.
     */
    function getPrice(address crvLp) external override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);
        _checkReentrant(pool, tokens.length);

        uint256 minPrice = type(uint256).max;
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            uint256 tokenPrice = base.getPrice(tokens[idx]);
            if (tokenPrice < minPrice) minPrice = tokenPrice;
        }

        // Use min underlying token prices
        return (minPrice * virtualPrice) / 1e18;
    }

    receive() external payable {}
}
