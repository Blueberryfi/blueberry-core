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
/**
 * @title BBMath
 * @author BlueberryProtocol
 * @dev The BBMath library provides functions for calculating common mathematical operations.
    */
library BBMath {
    /// @notice Rounds up the result of division between two numbers.
    /// @param a Numerator.
    /// @param b Denominator.
    /// @return The result of the division, rounded up.
    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    /// @notice Calculates the square root of a number using the Babylonian method.
    /// @dev This function uses bit manipulation to efficiently estimate square roots.
    ///      The function iteratively refines the approximation, and after seven iterations,
    ///      the result is very close to the actual square root.
    /// @param x The number to compute the square root of.
    /// @return The estimated square root of x.
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 xx = x;
        uint256 r = 1;

        /// Bitwise operations to determine the magnitude of the input
        /// and position our initial approximation (r) near the actual square root.
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

        /// Refinement using Babylonian method
        /// This iterative approach refines our approximation with every iteration.
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; /// Seven iterations should be enough

        /// Determine the closest approximation by comparing r and r1.
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}
