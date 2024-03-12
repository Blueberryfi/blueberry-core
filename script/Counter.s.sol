// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Script } from "forge-std/Script.sol";

contract CounterScript is Script {
    // solhint-disable-next-line no-empty-blocks
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}
