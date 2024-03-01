// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest } from "@test/BaseTest.t.sol";

struct VaultBalanceOf {
    uint256 alice;
}

struct UnderlyingBalanceOf {
    uint256 alice;
    uint256 treasury;
}

struct State {
    VaultBalanceOf vaultBalanceOf;
    UnderlyingBalanceOf underlyingBalanceOf;
}

abstract contract SoftVaultBaseTest is BaseTest {
    function _state() internal view returns (State memory state) {
        state.vaultBalanceOf.alice = vault.balanceOf(alice);
        state.underlyingBalanceOf.alice = underlying.balanceOf(alice);
        state.underlyingBalanceOf.treasury = underlying.balanceOf(treasury);
    }
}
