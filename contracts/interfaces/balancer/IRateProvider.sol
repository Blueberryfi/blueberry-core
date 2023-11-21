// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IRateProvider {
    function getRate() external view returns (uint256);
}
