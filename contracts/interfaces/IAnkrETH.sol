// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IAnkrETH {
    function sharesToBonds(uint256) external view returns (uint256);
}
