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

import { FixedPoint } from "../libraries/balancer-v2/FixedPoint.sol";
import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ICurveAddressProvider } from "../interfaces/curve/ICurveAddressProvider.sol";
import { ICurveReentrencyWrapper } from "../interfaces/ICurveReentrencyWrapper.sol";

/**
 * @title CurveVolatileOracle
 * @author BlueberryProtocol
 * @notice Oracle contract which privides price feeds for Curve volatile pool LP tokens
 */
contract CurveVolatileOracle is CurveBaseOracle {
    using FixedPoint for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    uint16 private constant _PERCENTAGE_FACTOR = 1e4; /// 100% represented in fixed point format
    uint256 private constant _RANGE_WIDTH = 200; // Represents a 2% range width

    /// @dev LP Token to lower bound of token-to-underlying exchange rate
    mapping(address => uint256) private _lowerBound;

    /*//////////////////////////////////////////////////////////////////////////
                                      CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Max gas for reentrancy check.
    uint256 internal constant _MAX_GAS = 10_000;

    /// @dev Event emitted when the bounds for the token-to-underlying exchange rate is changed.
    event NewLimiterParams(uint256 lowerBound, uint256 upperBound);

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
     * @param addressProvider Address of the curve address provider
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(ICurveAddressProvider addressProvider, IBaseOracle base, address owner) external initializer {
        __CurveBaseOracle_init(addressProvider, base, owner);
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address crvLp) external view override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);

        if (_checkReentrant(pool, tokens.length)) revert Errors.REENTRANCY_RISK(pool);

        uint256 nTokens = tokens.length;

        IBaseOracle base = getBaseOracle();

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

        uint256 answer = product.powDown(Constants.PRICE_PRECISION / nTokens).mulDown(nTokens * virtualPrice);

        return (answer * Constants.CHAINLINK_PRICE_FEED_PRECISION) / Constants.PRICE_PRECISION;
    }

    /**
     * @notice Fetches the lower bound for the token-to-underlying exchange rate.
     * @dev Used to protect against LP token / share price manipulation.
     */
    function getLowerBound() external view returns (uint256) {
        return _lowerBound[msg.sender];
    }

    /**
     * @notice Updates the bounds for the exchange rate value
     * @param crvLp The Curve LP token address
     * @param lowerBound The new lower bound (the upper bound is computed dynamically)
     *                   from the lower bound
     */
    function setLimiter(address crvLp, uint256 lowerBound) external onlyOwner {
        _setLimiter(crvLp, lowerBound);
    }

    /// @notice Internal implementation for setting the limiter
    function _setLimiter(address crvLp, uint256 lowerBound) internal {
        if (lowerBound == 0 || !_checkCurrentValueInBounds(crvLp, lowerBound, _upperBound(lowerBound))) {
            revert Errors.INCORRECT_LIMITS();
        }

        _lowerBound[crvLp] = lowerBound;
        emit NewLimiterParams(lowerBound, _upperBound(lowerBound));
    }

    /// @notice Checks if the current value is within the specified bounds
    function _checkCurrentValueInBounds(
        address crvLp,
        uint256 lowerBound,
        uint256 upperBound
    ) internal view returns (bool) {
        (, , uint256 virtualPrice) = _getPoolInfo(crvLp);
        if (virtualPrice < lowerBound || virtualPrice > upperBound) {
            return false;
        }
        return true;
    }

    /**
     * @notice Checks that value is within the range [lowerBound; upperBound],
     * @dev If the value is below the lowerBound, it reverts. Otherwise, it returns min(value, upperBound).
     * @param crvLp The curve LP token address
     * @param value Value to be checked and bounded
     */
    function _checkAndUpperBoundValue(address crvLp, uint256 value) internal view returns (uint256) {
        uint256 lb = _lowerBound[crvLp];
        if (value < lb) revert Errors.VALUE_OUT_OF_RANGE();

        uint256 uBound = _upperBound(lb);

        return (value > uBound) ? uBound : value;
    }

    /// @notice Computes the upper bound based on the provided lower bound
    function _upperBound(uint256 lb) internal pure returns (uint256) {
        return (lb * (_PERCENTAGE_FACTOR + _RANGE_WIDTH)) / _PERCENTAGE_FACTOR;
    }

    /// @inheritdoc CurveBaseOracle
    function _checkReentrant(address _pool, uint256) internal view override returns (bool) {
        ICurveReentrencyWrapper pool = ICurveReentrencyWrapper(_pool);

        uint256 gasStart = gasleft();

        //  solhint-disable no-empty-blocks
        try pool.claim_admin_fees{ gas: _MAX_GAS }() {} catch (bytes memory) {}

        uint256 gasSpent;
        unchecked {
            gasSpent = gasStart - gasleft();
        }

        // If the gas spent is greater than the maximum gas, then the call is not-vulnerable to
        // read-only reentrancy
        return gasSpent > _MAX_GAS ? false : true;
    }
}
