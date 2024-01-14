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

import { CurveBaseOracle } from "./CurveBaseOracle.sol";

import "../utils/BlueberryConst.sol" as Constants;

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ICurveAddressProvider } from "../interfaces/curve/ICurveAddressProvider.sol";
import { ICurvePool } from "../interfaces/curve/ICurvePool.sol";

/**
 * @title CurveStableOracle
 * @author BlueberryProtocol
 * @notice Oracle contract that provides price feeds for Curve stable LP tokens.
 */
contract CurveStableOracle is CurveBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Constructor initializes the CurveBaseOracle with the provided parameters.
     * @param base The address of the base oracle.
     * @param addressProvider The address of the curve address provider.
     */
    constructor(IBaseOracle base, ICurveAddressProvider addressProvider) CurveBaseOracle(base, addressProvider) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseOracle
    function getPrice(address crvLp) external override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);
        _checkReentrant(pool, tokens.length);

        uint256 minPrice = type(uint256).max;
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 tokenPrice = base.getPrice(tokens[i]);
            if (tokenPrice < minPrice) minPrice = tokenPrice;
        }

        // Calculate LP token price using the minimum underlying token price
        return (minPrice * virtualPrice) / Constants.PRICE_PRECISION;
    }

    /// @inheritdoc CurveBaseOracle
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

    /// @notice Fallback function to receive Ether.
    receive() external payable {}
}
