// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IBalancerPool {
    function getRate() external view returns (uint256);

    function getVault() external view returns (address);

    function getPoolId() external view returns (bytes32);

    function totalSupply() external view returns (uint256);

    function getBptIndex() external view returns (uint256);

    function getActualSupply() external view returns (uint256);

    function getNormalizedWeights() external view returns (uint256[] memory);

    function getInvariant() external view returns (uint256);

    function getRateProviders() external view returns (address[] memory);
}
