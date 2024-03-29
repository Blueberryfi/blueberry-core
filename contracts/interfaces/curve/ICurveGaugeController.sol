// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface ICurveGaugeController {
    function gauges(uint256) external view returns (address);
}
