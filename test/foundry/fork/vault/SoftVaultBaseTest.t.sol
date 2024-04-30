// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { BaseTest, SoftVault, ERC1967Proxy, IBErc20 } from "@test/BaseTest.t.sol";

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
    IBErc20 public bToken;
    ERC20PresetMinterPauser public underlying;
    SoftVault public vault;

    function setUp() public override {
        super.setUp();
        _deployVault();
    }

    function _deployVault() internal {
        bToken = IBErc20(BUSDC);
        underlying = ERC20PresetMinterPauser(USDC);
        vault = SoftVault(
            address(
                new ERC1967Proxy(
                    address(new SoftVault()),
                    abi.encodeCall(
                        SoftVault.initialize,
                        (
                            config,
                            bToken,
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

    function _enableBorrow() internal {
        vm.prank(comptroller.admin());
        comptroller._setBorrowPaused(IBErc20(BUSDC), false);
        vm.prank(comptroller.admin());
        comptroller._setBorrowPaused(IBErc20(BDAI), false);
        address[] memory markets = new address[](2);
        markets[0] = BUSDC;
        markets[1] = BDAI;
        uint256[] memory newBorrowCaps = new uint256[](2);
        newBorrowCaps[0] = type(uint256).max;
        newBorrowCaps[1] = type(uint256).max;
        vm.prank(comptroller.admin());
        comptroller._setMarketBorrowCaps(markets, newBorrowCaps);
    }
}
