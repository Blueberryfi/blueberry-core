// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */

import "@contracts/utils/BlueberryConst.sol" as Constants;
import { SoftVaultBaseTest, State } from "@test/SoftVaultBaseTest.t.sol";

/// @title SoftVaultTest
/// @notice Test common vault properties
/// @dev Inspired by https://github.com/crytic/properties/tree/125fa4135c8ad5e7599d1bf2dd2aa055d35a1ab6/contracts/ERC4626
contract SoftVaultTest is SoftVaultBaseTest {
    function testFork_SoftVault_getters() public {
        assertEq(vault.decimals(), underlying.decimals(), bToken.decimals());
        assertEq(address(vault.getBToken()), address(bToken));
        assertEq(address(vault.getUnderlyingToken()), address(underlying));
        assertEq(address(vault.getConfig()), address(config));
    }

    function testForkFuzz_SoftVault_deposit(uint256 amount) public {
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, 1, type(uint128).max);
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

    function testForkFuzz_SoftVault_deposit_withdraw(uint256 amount, uint256 shareAmountAlice) public {
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, 1, type(uint128).max);
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

        assertGe(
            underlyingAfter,
            underlyingBefore,
            "Withdraw must credit underlying to the sender if enough shares are burned"
        );
        assertLt(sharesAfter, sharesBefore, "Withdraw must deduct shares from the sender");
        assertEq(vault.totalSupply(), sharesAfter, "Total supply must be deducted by the sender's balance");
    }

    function testForkFuzz_SoftVault_deposit_withdraw_with_fees(
        uint256 amount,
        uint256 shareAmountAlice,
        uint256 withdrawFeeRate,
        uint256 interval
    ) public {
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, 1, type(uint128).max);
        underlying.mint(alice, amount);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        withdrawFeeRate = bound(withdrawFeeRate, 0, Constants.MAX_FEE_RATE);
        config.setWithdrawFee(withdrawFeeRate);
        config.startVaultWithdrawFee();

        interval = bound(interval, 0, 2 * Constants.MAX_WITHDRAW_VAULT_FEE_WINDOW);
        vm.warp(block.timestamp + interval);

        shareAmountAlice = bound(shareAmountAlice, 1, vault.balanceOf(alice));

        State memory _before = _state();

        vm.prank(alice);
        vault.withdraw(shareAmountAlice);

        State memory _after = _state();

        assertGe(
            _after.underlyingBalanceOf.alice,
            _before.underlyingBalanceOf.alice,
            "Withdraw must credit underlying to the sender if enough shares are burned"
        );
        assertGe(
            _after.underlyingBalanceOf.treasury,
            _before.underlyingBalanceOf.treasury,
            "Withdraw must credit underlying to the treasury if enough fees are extracted"
        );
        assertLt(
            _after.vaultBalanceOf.alice,
            _before.vaultBalanceOf.alice,
            "Withdraw must deduct shares from the sender"
        );
        assertEq(
            vault.totalSupply(),
            _after.vaultBalanceOf.alice,
            "Total supply must be deducted by the sender's balance"
        );
    }

    function testForkFuzz_SoftVault_RevertWith_withdraw_must_revert_if_not_enough_shares(uint256 amount) public {
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, 1, type(uint128).max);
        underlying.mint(alice, amount);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        uint256 sharesAmount = vault.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodePacked("ERC20: burn amount exceeds balance"));
        vault.withdraw(sharesAmount + 1);
    }

    function testForkFuzz_SoftVault_deposit_withdraw_3_users(
        uint256[3] memory amounts,
        uint256[3] memory shareAmounts
    ) private {}
}
