// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

library BBMath {
    /// @dev Computes round-up division.
    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }
}
