// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';

contract ERC1155NaiveReceiver is IERC1155Receiver {
    bytes32[64] __gap; // reserve space for upgrade

    function onERC1155Received(
        address, /* operator */
        address, /* from */
        uint256, /* id */
        uint256, /* value */
        bytes calldata /* data */
    ) external override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /* operator */
        address, /* from */
        uint256[] calldata, /* ids */
        uint256[] calldata, /* values */
        bytes calldata /* data */
    ) external override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
