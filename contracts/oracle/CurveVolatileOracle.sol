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
import "../libraries/balancer/FixedPoint.sol";
import "../utils/BlueBerryConst.sol" as Constants;

/// @author BlueberryProtocol
/// @title Curve Volatile Oracle
/// @notice Oracle contract which privides price feeds for Curve volatile pool LP tokens
contract CurveVolatileOracle is CurveBaseOracle {
    using FixedPoint for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    uint16 constant PERCENTAGE_FACTOR = 1e4; /// 100% represented in fixed point format
    uint256 constant RANGE_WIDTH = 200; // Represents a 2% range width

    /// @dev The lower bound for the contract's token-to-underlying exchange rate.
    /// @notice Used to protect against LP token / share price manipulation.
    mapping(address => uint256) public lowerBound;

    /// @dev Event emitted when the bounds for the token-to-underlying exchange rate is changed.
    event NewLimiterParams(uint256 lowerBound, uint256 upperBound);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @notice Constructor to set initial values for the Curve Volatile Oracle
    /// @param base_ Address of the base oracle
    /// @param addressProvider_ Address of the curve address provider
    constructor(
        IBaseOracle base_,
        ICurveAddressProvider addressProvider_
    ) CurveBaseOracle(base_, addressProvider_) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Updates the bounds for the exchange rate value
    /// @param _crvLp The curve lp token
    /// @param _lowerBound The new lower bound (the upper bound is computed dynamically)
    ///                    from the lower bound
    function setLimiter(
        address _crvLp,
        uint256 _lowerBound
    ) external onlyOwner {
        _setLimiter(_crvLp, _lowerBound);
    }

    /// @dev Internal implementation for setting the limiter
    function _setLimiter(address _crvLp, uint256 _lowerBound) internal {
        if (
            _lowerBound == 0 ||
            !_checkCurrentValueInBounds(
                _crvLp,
                _lowerBound,
                _upperBound(_lowerBound)
            )
        ) revert BlueBerryErrors.INCORRECT_LIMITS();

        lowerBound[_crvLp] = _lowerBound;
        emit NewLimiterParams(_lowerBound, _upperBound(_lowerBound));
    }

    /// Checks if the current value is within the specified bounds
    function _checkCurrentValueInBounds(
        address _crvLp,
        uint256 _lowerBound,
        uint256 __upperBound
    ) internal returns (bool) {
        (, , uint256 virtualPrice) = _getPoolInfo(_crvLp);
        if (virtualPrice < _lowerBound || virtualPrice > __upperBound) {
            return false;
        }
        return true;
    }

    /// Override function to check for reentrancy
    function _checkReentrant(address _pool, uint256) internal override {
        ICurvePool pool = ICurvePool(_pool);
        pool.claim_admin_fees();
    }

    /// @notice Return the USD value of given Curve Lp, with 18 decimals of precision.
    /// @param crvLp The ERC-20 Curve LP token to check the value.
    function getPrice(address crvLp) external override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);
        _checkReentrant(pool, tokens.length);

        uint256 nTokens = tokens.length;

        uint256 px0 = base.getPrice(tokens[0]);
        uint256 px1 = base.getPrice(tokens[1]);

        uint256 product = (px0 * Constants.PRICE_PRECISION) / Constants.CHAINLINK_PRICE_FEED_PRECISION;
        product = product.mulDown((px1 * Constants.PRICE_PRECISION) / Constants.CHAINLINK_PRICE_FEED_PRECISION);

        if (nTokens == 3) {
            uint256 px2 = base.getPrice(tokens[2]);
            product = product.mulDown(
                (uint256(px2) * Constants.PRICE_PRECISION) / Constants.CHAINLINK_PRICE_FEED_PRECISION
            );
        }

        /// Checks that virtual_price is within bounds
        virtualPrice = _checkAndUpperBoundValue(crvLp, virtualPrice);

        uint256 answer = product.powDown(Constants.PRICE_PRECISION / nTokens).mulDown(
            nTokens * virtualPrice
        );

        return (answer * Constants.CHAINLINK_PRICE_FEED_PRECISION) / Constants.PRICE_PRECISION;
    }

    /// @dev Checks that value is within the range [lowerBound; upperBound],
    /// @notice If the value is below the lowerBound, it reverts. Otherwise, it returns min(value, upperBound).
    /// @param crvLp The curve LP token address
    /// @param value Value to be checked and bounded
    function _checkAndUpperBoundValue(
        address crvLp,
        uint256 value
    ) internal view returns (uint256) {
        uint256 lb = lowerBound[crvLp];
        if (value < lb) revert BlueBerryErrors.VALUE_OUT_OF_RANGE();

        uint256 uBound = _upperBound(lb);

        return (value > uBound) ? uBound : value;
    }

    /// Computes the upper bound based on the provided lower bound
    function _upperBound(uint256 lb) internal pure returns (uint256) {
        return (lb * (PERCENTAGE_FACTOR + RANGE_WIDTH)) / PERCENTAGE_FACTOR;
    }
}
