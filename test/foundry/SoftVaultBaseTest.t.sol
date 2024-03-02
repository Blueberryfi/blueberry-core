// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, ERC20PresetMinterPauser, SoftVault, ERC1967Proxy, IBErc20 } from "@test/BaseTest.t.sol";

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
    ERC20PresetMinterPauser public underlying;
    SoftVault public vault;

    function setUp() public override {
        super.setUp();
        underlying = ERC20PresetMinterPauser(USDC);
        vault = SoftVault(
            address(
                new ERC1967Proxy(
                    address(new SoftVault()),
                    abi.encodeCall(
                        SoftVault.initialize,
                        (
                            config,
                            IBErc20(address(bTokenUSDC)),
                            string.concat("SoftVault ", underlying.name()),
                            string.concat("s", underlying.symbol()),
                            owner
                        )
                    )
                )
            )
        );
    }

    function _state() internal view returns (State memory state) {
        state.vaultBalanceOf.alice = vault.balanceOf(alice);
        state.underlyingBalanceOf.alice = underlying.balanceOf(alice);
        state.underlyingBalanceOf.treasury = underlying.balanceOf(treasury);
    }
}
