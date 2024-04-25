// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IApxEth is IERC4626 {
    function assetsPerShare() external view returns (uint256);
    function pirexEth() external view returns (address);
    function harvest() external;
}
