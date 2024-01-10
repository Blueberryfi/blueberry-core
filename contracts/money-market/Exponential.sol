pragma solidity 0.5.16;

import "./CarefulMath.sol";

/**
 * @title Exponential module for storing fixed-precision decimals
 * @author Compound
 * @notice Exp is a struct which stores decimals with a fixed precision of 18 decimal places.
 *         Thus, if we wanted to store the 5.1, mantissa would store 5.1e18. That is:
 *         `Exp({mantissa: 5100000000000000000})`.
 */
contract Exponential is CarefulMath {
    uint256 internal constant _EXP_SCALE = 1e18;
    uint256 internal constant _DOUBLE_SCALE = 1e36;
    uint256 internal constant _HALF_EXP_SCALE = _EXP_SCALE / 2;
    uint256 internal constant _MANTISSA_ONE = _EXP_SCALE;

    struct Exp {
        uint256 mantissa;
    }

    struct Double {
        uint256 mantissa;
    }

    /**
     * @dev Creates an exponential from numerator and denominator values.
     *      Note: Returns an error if (`num` * 10e18) > MAX_INT,
     *            or if `denom` is zero.
     */
    function _getExp(uint256 num, uint256 denom) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint256 scaledNumerator) = _mulUInt(num, _EXP_SCALE);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({ mantissa: 0 }));
        }

        (MathError err1, uint256 rational) = _divUInt(scaledNumerator, denom);
        if (err1 != MathError.NO_ERROR) {
            return (err1, Exp({ mantissa: 0 }));
        }

        return (MathError.NO_ERROR, Exp({ mantissa: rational }));
    }

    /**
     * @dev Adds two exponentials, returning a new exponential.
     */
    function _addExp(Exp memory a, Exp memory b) internal pure returns (MathError, Exp memory) {
        (MathError error, uint256 result) = _addUInt(a.mantissa, b.mantissa);

        return (error, Exp({ mantissa: result }));
    }

    /**
     * @dev Subtracts two exponentials, returning a new exponential.
     */
    function _subExp(Exp memory a, Exp memory b) internal pure returns (MathError, Exp memory) {
        (MathError error, uint256 result) = _subUInt(a.mantissa, b.mantissa);

        return (error, Exp({ mantissa: result }));
    }

    /**
     * @dev Multiply an Exp by a scalar, returning a new Exp.
     */
    function _mulScalar(Exp memory a, uint256 scalar) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint256 scaledMantissa) = _mulUInt(a.mantissa, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({ mantissa: 0 }));
        }

        return (MathError.NO_ERROR, Exp({ mantissa: scaledMantissa }));
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function _mulScalarTruncate2(Exp memory a, uint256 scalar) internal pure returns (MathError, uint256) {
        (MathError err, Exp memory product) = _mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return (MathError.NO_ERROR, _truncate(product));
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function _mulScalarTruncateAddUInt2(
        Exp memory a,
        uint256 scalar,
        uint256 addend
    ) internal pure returns (MathError, uint256) {
        (MathError err, Exp memory product) = _mulScalar(a, scalar);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return _addUInt(_truncate(product), addend);
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function _mulScalarTruncate(Exp memory a, uint256 scalar) internal pure returns (uint256) {
        Exp memory product = _mul(a, scalar);
        return _truncate(product);
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function _mulScalarTruncateAddUInt(Exp memory a, uint256 scalar, uint256 addend) internal pure returns (uint256) {
        Exp memory product = _mul(a, scalar);
        return _add(_truncate(product), addend);
    }

    /**
     * @dev Divide an Exp by a scalar, returning a new Exp.
     */
    function _divScalar(Exp memory a, uint256 scalar) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint256 descaledMantissa) = _divUInt(a.mantissa, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({ mantissa: 0 }));
        }

        return (MathError.NO_ERROR, Exp({ mantissa: descaledMantissa }));
    }

    /**
     * @dev Divide a scalar by an Exp, returning a new Exp.
     */
    function _divScalarByExp2(uint256 scalar, Exp memory divisor) internal pure returns (MathError, Exp memory) {
        /*
          We are doing this as:
          _getExp(_mulUInt(_EXP_SCALE, scalar), divisor.mantissa)

          How it works:
          Exp = a / b;
          Scalar = s;
          `s / (a / b)` = `b * s / a` and since for an Exp `a = mantissa, b = _EXP_SCALE`
        */
        (MathError err0, uint256 numerator) = _mulUInt(_EXP_SCALE, scalar);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({ mantissa: 0 }));
        }
        return _getExp(numerator, divisor.mantissa);
    }

    /**
     * @dev Divide a scalar by an Exp, then truncate to return an unsigned integer.
     */
    function _divScalarByExpTruncate2(uint256 scalar, Exp memory divisor) internal pure returns (MathError, uint256) {
        (MathError err, Exp memory fraction) = _divScalarByExp2(scalar, divisor);
        if (err != MathError.NO_ERROR) {
            return (err, 0);
        }

        return (MathError.NO_ERROR, _truncate(fraction));
    }

    /**
     * @dev Divide a scalar by an Exp, returning a new Exp.
     */
    function _divScalarByExp(uint256 scalar, Exp memory divisor) internal pure returns (Exp memory) {
        /*
          We are doing this as:
          _getExp(_mulUInt(_EXP_SCALE, scalar), divisor.mantissa)

          How it works:
          Exp = a / b;
          Scalar = s;
          `s / (a / b)` = `b * s / a` and since for an Exp `a = mantissa, b = _EXP_SCALE`
        */
        uint256 numerator = _mul(_EXP_SCALE, scalar);
        return Exp({ mantissa: _div(numerator, divisor) });
    }

    /**
     * @dev Divide a scalar by an Exp, then truncate to return an unsigned integer.
     */
    function _divScalarByExpTruncate(uint256 scalar, Exp memory divisor) internal pure returns (uint256) {
        (, Exp memory fraction) = _divScalarByExp2(scalar, divisor);
        return _truncate(fraction);
    }

    /**
     * @dev Multiplies two exponentials, returning a new exponential.
     */
    function _mulExp(Exp memory a, Exp memory b) internal pure returns (MathError, Exp memory) {
        (MathError err0, uint256 doubledScaledProduct) = _mulUInt(a.mantissa, b.mantissa);
        if (err0 != MathError.NO_ERROR) {
            return (err0, Exp({ mantissa: 0 }));
        }

        // We add half the scale before dividing so that we get rounding instead of truncation.
        //  See "Listing 6" and text above it at https://accu.org/index.php/journals/1717
        // Without this change, a result like 6.6...e-19 will be truncated to 0 instead of being rounded to 1e-18.
        (MathError err1, uint256 doubledScaledProductWithHalfScale) = _addUInt(_HALF_EXP_SCALE, doubledScaledProduct);
        if (err1 != MathError.NO_ERROR) {
            return (err1, Exp({ mantissa: 0 }));
        }

        (MathError err2, uint256 product) = _divUInt(doubledScaledProductWithHalfScale, _EXP_SCALE);
        // The only error `div` can return is MathError.DIVISION_BY_ZERO but we control `EXP_SCALE` and it is not zero.
        assert(err2 == MathError.NO_ERROR);

        return (MathError.NO_ERROR, Exp({ mantissa: product }));
    }

    /**
     * @dev Multiplies two exponentials given their mantissas, returning a new exponential.
     */
    function _mulExp(uint256 a, uint256 b) internal pure returns (MathError, Exp memory) {
        return _mulExp(Exp({ mantissa: a }), Exp({ mantissa: b }));
    }

    /**
     * @dev Multiplies three exponentials, returning a new exponential.
     */
    function _mulExp3(Exp memory a, Exp memory b, Exp memory c) internal pure returns (MathError, Exp memory) {
        (MathError err, Exp memory ab) = _mulExp(a, b);
        if (err != MathError.NO_ERROR) {
            return (err, ab);
        }
        return _mulExp(ab, c);
    }

    /**
     * @dev Divides two exponentials, returning a new exponential.
     *     (a/scale) / (b/scale) = (a/scale) * (scale/b) = a/b,
     *  which we can scale as an Exp by calling _getExp(a.mantissa, b.mantissa)
     */
    function _divExp(Exp memory a, Exp memory b) internal pure returns (MathError, Exp memory) {
        return _getExp(a.mantissa, b.mantissa);
    }

    /**
     * @dev Truncates the given exp to a whole number value.
     *      For example, truncate(Exp{mantissa: 15 * EXP_SCALE}) = 15
     */
    function _truncate(Exp memory exp) internal pure returns (uint256) {
        // Note: We are not using careful math here as we're performing a division that cannot fail
        return exp.mantissa / _EXP_SCALE;
    }

    /**
     * @dev Checks if first Exp is less than second Exp.
     */
    function _lessThanExp(Exp memory left, Exp memory right) internal pure returns (bool) {
        return left.mantissa < right.mantissa;
    }

    /**
     * @dev Checks if left Exp <= right Exp.
     */
    function _lessThanOrEqualExp(Exp memory left, Exp memory right) internal pure returns (bool) {
        return left.mantissa <= right.mantissa;
    }

    /**
     * @dev returns true if Exp is exactly zero
     */
    function _isZeroExp(Exp memory value) internal pure returns (bool) {
        return value.mantissa == 0;
    }

    function _safe224(uint256 n, string memory errorMessage) internal pure returns (uint224) {
        require(n < 2 ** 224, errorMessage);
        return uint224(n);
    }

    function _safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function _add(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return Exp({ mantissa: _add(a.mantissa, b.mantissa) });
    }

    function _add(Double memory a, Double memory b) internal pure returns (Double memory) {
        return Double({ mantissa: _add(a.mantissa, b.mantissa) });
    }

    function _add(uint256 a, uint256 b) internal pure returns (uint256) {
        return _add(a, b, "addition overflow");
    }

    function _add(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function _sub(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return Exp({ mantissa: _sub(a.mantissa, b.mantissa) });
    }

    function _sub(Double memory a, Double memory b) internal pure returns (Double memory) {
        return Double({ mantissa: _sub(a.mantissa, b.mantissa) });
    }

    function _sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return _sub(a, b, "subtraction underflow");
    }

    function _sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function _mul(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return Exp({ mantissa: _mul(a.mantissa, b.mantissa) / _EXP_SCALE });
    }

    function _mul(Exp memory a, uint256 b) internal pure returns (Exp memory) {
        return Exp({ mantissa: _mul(a.mantissa, b) });
    }

    function _mul(uint256 a, Exp memory b) internal pure returns (uint256) {
        return _mul(a, b.mantissa) / _EXP_SCALE;
    }

    function _mul(Double memory a, Double memory b) internal pure returns (Double memory) {
        return Double({ mantissa: _mul(a.mantissa, b.mantissa) / _DOUBLE_SCALE });
    }

    function _mul(Double memory a, uint256 b) internal pure returns (Double memory) {
        return Double({ mantissa: _mul(a.mantissa, b) });
    }

    function _mul(uint256 a, Double memory b) internal pure returns (uint256) {
        return _mul(a, b.mantissa) / _DOUBLE_SCALE;
    }

    function _mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return _mul(a, b, "multiplication overflow");
    }

    function _mul(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, errorMessage);
        return c;
    }

    function _div(Exp memory a, Exp memory b) internal pure returns (Exp memory) {
        return Exp({ mantissa: _div(_mul(a.mantissa, _EXP_SCALE), b.mantissa) });
    }

    function _div(Exp memory a, uint256 b) internal pure returns (Exp memory) {
        return Exp({ mantissa: _div(a.mantissa, b) });
    }

    function _div(uint256 a, Exp memory b) internal pure returns (uint256) {
        return _div(_mul(a, _EXP_SCALE), b.mantissa);
    }

    function _div(Double memory a, Double memory b) internal pure returns (Double memory) {
        return Double({ mantissa: _div(_mul(a.mantissa, _DOUBLE_SCALE), b.mantissa) });
    }

    function _div(Double memory a, uint256 b) internal pure returns (Double memory) {
        return Double({ mantissa: _div(a.mantissa, b) });
    }

    function _div(uint256 a, Double memory b) internal pure returns (uint256) {
        return _div(_mul(a, _DOUBLE_SCALE), b.mantissa);
    }

    function _div(uint256 a, uint256 b) internal pure returns (uint256) {
        return _div(a, b, "divide by zero");
    }

    function _div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    function _fraction(uint256 a, uint256 b) internal pure returns (Double memory) {
        return Double({ mantissa: _div(_mul(a, _DOUBLE_SCALE), b) });
    }

    // implementation from https://github.com/Uniswap/uniswap-lib/commit/99f3f28770640ba1bb1ff460ac7c5292fb8291a0
    // original implementation:
    //     https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 xx = x;
        uint256 r = 1;

        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }

        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}
