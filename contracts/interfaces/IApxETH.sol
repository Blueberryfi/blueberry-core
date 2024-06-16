// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IApxEth is IERC4626 {
    function harvest() external;

    function assetsPerShare() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);
}
