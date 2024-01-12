// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IAuraStashToken {
    function baseToken() external view returns (address);

    function rewardPool() external view returns (address);

    function stash() external view returns (address);
}
