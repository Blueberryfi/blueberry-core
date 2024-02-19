// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.5.16;

import "./InterestRateModel.sol";
import "./SafeMath.sol";

/**
 * @title Blueberry's TripleSlopeRateModelV2 Contract
 * @author Compound (Modified by Blueberry)
 */
contract TripleSlopeRateModelV2 is InterestRateModel {
    using SafeMath for uint256;

    event NewInterestParams(
        uint256 baseRatePerSecond,
        uint256 multiplierPerSecond,
        uint256 jumpMultiplierPerSecond1,
        uint256 jumpMultiplierPerSecond2,
        uint256 kink1,
        uint256 kink2,
        uint256 roof
    );

    /**
     * @notice The address of the owner, i.e. the Timelock contract, which can update parameters directly
     */
    address public owner;

    /**
     * @notice The approximate number of seconds per year that is assumed by the interest rate model
     */
    uint256 public constant secondsPerYear = 31536000;

    /**
     * @notice The minimum roof value used for calculating borrow rate.
     */
    uint256 internal constant minRoofValue = 1e18;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint256 public multiplierPerSecond;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint256 public baseRatePerSecond;

    /**
     * @notice The multiplierPerSecond after hitting the first specified utilization point
     */
    uint256 public jumpMultiplierPerSecond1;

    /**
     * @notice The multiplierPerSecond after hitting the second specified utilization point
     */
     uint256 public jumpMultiplierPerSecond2;

    /**
     * @notice The utilization point at which the interest rate is fixed
     */
    uint256 public kink1;

    /**
     * @notice The utilization point at which the jump multiplier is applied
     */
    uint256 public kink2;

    /**
     * @notice The utilization point at which the rate is fixed
     */
    uint256 public roof;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear1 The multiplierPerSecond after hitting the first specified utilization point
     * @param jumpMultiplierPerYear2 The multiplierPerSecond after hitting the second specified utilization point
     * @param kink1_ The utilization point at which the interest rate is fixed
     * @param kink2_ The utilization point at which the jump multiplier is applied
     * @param roof_ The utilization point at which the borrow rate is fixed
     * @param owner_ The address of the owner, i.e. the Timelock contract (which has the ability to update parameters directly)
     */
    constructor(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear1,
        uint256 jumpMultiplierPerYear2,
        uint256 kink1_,
        uint256 kink2_,
        uint256 roof_,
        address owner_
    ) public {
        owner = owner_;

        updateTripleRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear1,
        jumpMultiplierPerYear2, kink1_, kink2_, roof_);
    }

    /**
     * @notice Update the parameters of the interest rate model (only callable by owner, i.e. Timelock)
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear1 The multiplierPerSecond after hitting the first specified utilization point
     * @param jumpMultiplierPerYear2 The multiplierPerSecond after hitting the second specified utilization point
     * @param kink1_ The utilization point at which the interest rate is fixed
     * @param kink2_ The utilization point at which the jump multiplier is applied
     * @param roof_ The utilization point at which the borrow rate is fixed
     */
    function updateTripleRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear1,
        uint256 jumpMultiplierPerYear2,
        uint256 kink1_,
        uint256 kink2_,
        uint256 roof_
    ) external {
        require(msg.sender == owner, "only the owner may call this function.");

        updateTripleRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear1,
        jumpMultiplierPerYear2, kink1_, kink2_, roof_);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        uint256 util = borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
        // If the utilization is above the roof, cap it.
        if (util > roof) {
            util = roof;
        }
        return util;
    }

    /**
     * @notice Calculates the current borrow rate per second, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per second as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);

        if (util <= kink1) {
            return util.mul(multiplierPerSecond).div(1e18).add(baseRatePerSecond);
        } else if (util <= kink2) {
            return util.mul(jumpMultiplierPerSecond1).div(1e18).add(baseRatePerSecond);
        } else {
            uint256 normalRate = kink2.mul(multiplierPerSecond).div(1e18).add(baseRatePerSecond);
            uint256 excessUtil = util.sub(kink2);
            return excessUtil.mul(jumpMultiplierPerSecond2).div(1e18).add(normalRate);
        }
    }

    /**
     * @notice Calculates the current supply rate per second
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per second as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view returns (uint256) {
        uint256 oneMinusReserveFactor = uint256(1e18).sub(reserveFactorMantissa);
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }

    /**
     * @notice Internal function to update the parameters of the interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear1 The multiplierPerSecond after hitting a specified utilization point
     * @param jumpMultiplierPerYear2 The multiplierPerSecond after hitting a specified utilization point
     * @param kink1_ The utilization point at which the interest rate is fixed
     * @param kink2_ The utilization point at which the jump multiplier is applied
     * @param roof_ The utilization point at which the borrow rate is fixed
     */
    function updateTripleRateModelInternal(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear1,
        uint256 jumpMultiplierPerYear2,
        uint256 kink1_,
        uint256 kink2_,
        uint256 roof_
    ) internal {
        require(kink1_ <= kink2_, "kink1 must less than or equal to kink2");
        require(roof_ >= minRoofValue, "invalid roof value");

        baseRatePerSecond = baseRatePerYear.div(secondsPerYear);
        multiplierPerSecond = multiplierPerYear.div(secondsPerYear);
        jumpMultiplierPerSecond1 = jumpMultiplierPerYear1.div(secondsPerYear);
        jumpMultiplierPerSecond2 = jumpMultiplierPerYear2.div(secondsPerYear);
        kink1 = kink1_;
        kink2 = kink2_;
        roof = roof_;

        emit NewInterestParams(baseRatePerSecond, multiplierPerSecond, jumpMultiplierPerSecond1,
        jumpMultiplierPerSecond2, kink1, kink2, roof);
    }
}
