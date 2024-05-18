// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/* solhint-enable max-line-length */

import { IERC20Wrapper } from "./IERC20Wrapper.sol";

interface IWMasterPenPie is IERC1155Upgradeable, IERC20Wrapper {
    function encodeId(address market, uint256 pnpPerShare) external returns (uint256 id);

    function decodeId(uint256 id) external returns (address market, uint256 pnpPerShare);

    function mint(address market, uint256 amount) external returns (uint256 id);

    function burn(
        uint256 id,
        uint256 amount
    ) external returns (address[] memory rewardTokens, uint256[] memory rewards);

    function getPenPie() external view returns (address);
}
