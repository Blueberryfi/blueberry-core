// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IERC20Wrapper.sol";
import "./curve/ICurveRegistry.sol";
import "./curve/ILiquidityGauge.sol";

interface IWCurveGauge is IERC1155Upgradeable, IERC20Wrapper {
    function CRV() external view returns (IERC20Upgradeable);

    /// @dev Mint ERC1155 token for the given ERC20 token.
    function mint(uint pid, uint gid, uint amount) external returns (uint id);

    /// @dev Burn ERC1155 token to redeem ERC20 token back.
    function burn(uint id, uint amount) external returns (uint pid);

    function registry() external returns (ICurveRegistry);

    function encodeId(uint, uint, uint) external pure returns (uint);

    function decodeId(uint id) external pure returns (uint, uint, uint);

    function getUnderlyingTokenFromIds(
        uint pid,
        uint gid
    ) external view returns (address);
}
