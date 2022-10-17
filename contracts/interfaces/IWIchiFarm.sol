// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import './IERC20Wrapper.sol';
import './ichi/IIchiV2.sol';
import './ichi/IIchiFarm.sol';

interface IWIchiFarm is IERC1155, IERC20Wrapper {
    function ICHI() external view returns (IIchiV2);

    function ichiFarm() external view returns (IIchiFarm);

    function decodeId(uint256 id) external pure returns (uint256, uint256);

    function mint(uint256 pid, uint256 amount) external returns (uint256);

    function burn(uint256 id, uint256 amount) external returns (uint256 pid);
}
