// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

contract MockEthSender {
    receive() external payable {}

    function destruct(address to) external {
        selfdestruct(payable(to));
    }
}
