// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */

import { BaseTest } from "@test/BaseTest.t.sol";

contract SoftVaultTest is BaseTest {
    function test_SoftVault_getters() public {
        assertEq(vault.decimals(), underlying.decimals(), bToken.decimals());
        assertEq(address(vault.getBToken()), address(bToken));
        assertEq(address(vault.getUnderlyingToken()), address(underlying));
        assertEq(address(vault.getConfig()), address(config));
    }
}
