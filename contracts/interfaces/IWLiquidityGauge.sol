// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './IERC20Wrapper.sol';
import './curve/ICurveRegistry.sol';
import './curve/ILiquidityGauge.sol';

interface IWLiquidityGauge is IERC1155, IERC20Wrapper {
    /// @dev Mint ERC1155 token for the given ERC20 token.
    function mint(
        uint256 pid,
        uint256 gid,
        uint256 amount
    ) external returns (uint256 id);

    /// @dev Burn ERC1155 token to redeem ERC20 token back.
    function burn(uint256 id, uint256 amount) external returns (uint256 pid);

    function crv() external returns (IERC20);

    function registry() external returns (ICurveRegistry);

    function encodeId(
        uint256,
        uint256,
        uint256
    ) external pure returns (uint256);

    function decodeId(uint256 id)
        external
        pure
        returns (
            uint256,
            uint256,
            uint256
        );

    function getUnderlyingTokenFromIds(uint256 pid, uint256 gid)
        external
        view
        returns (address);
}
