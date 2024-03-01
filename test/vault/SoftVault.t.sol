// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */

import { BaseTest } from "@test/BaseTest.t.sol";

/// @title SoftVaultTest
/// @notice Test common vault properties
/// @dev Inspired by https://github.com/crytic/properties/tree/125fa4135c8ad5e7599d1bf2dd2aa055d35a1ab6/contracts/ERC4626
contract SoftVaultTest is BaseTest {
    function test_SoftVault_getters() public {
        assertEq(vault.decimals(), underlying.decimals(), bToken.decimals());
        assertEq(address(vault.getBToken()), address(bToken));
        assertEq(address(vault.getUnderlyingToken()), address(underlying));
        assertEq(address(vault.getConfig()), address(config));
    }

    function test_SoftVault_deposit(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);
        underlying.mint(alice, amount);

        uint256 underlyingBefore = underlying.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        uint256 underlyingAfter = underlying.balanceOf(alice);
        uint256 sharesAfter = vault.balanceOf(alice);

        assertLt(underlyingAfter, underlyingBefore, "Deposit must deduct underlying from the sender");
        assertGt(sharesAfter, sharesBefore, "Deposit must credit shares to the sender");
        assertEq(vault.totalSupply(), vault.balanceOf(alice), "Total supply must be equal to the sender's balance");
    }

    function test_SoftVault_withdraw(uint256 amount, uint256 shareAmountAlice) public {
        amount = bound(amount, 1, type(uint256).max);
        underlying.mint(alice, amount);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        shareAmountAlice = bound(shareAmountAlice, 1, vault.balanceOf(alice));

        uint256 underlyingBefore = underlying.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(shareAmountAlice);

        uint256 underlyingAfter = underlying.balanceOf(alice);
        uint256 sharesAfter = vault.balanceOf(alice);

        assertGt(underlyingAfter, underlyingBefore, "Withdraw must credit underlying to the sender");
        assertLt(sharesAfter, sharesBefore, "Withdraw must deduct shares from the sender");
        assertEq(
            vault.totalSupply(),
            sharesBefore - sharesAfter,
            "Total supply must be deducted by the sender's balance"
        );
    }

    function test_SoftVault_withdraw_must_revert_if_not_enough_shares(uint256 amount, uint256 shareAmount) private {}

    function test_SoftVault_deposit_withdraw_3_users(
        uint256[3] memory amounts,
        uint256[3] memory shareAmounts
    ) private {}
}
