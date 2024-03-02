// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */
/* solhint-disable no-console */

import "@contracts/utils/BlueberryConst.sol" as Constants;
import { SoftVaultBaseTest, State } from "@test/SoftVaultBaseTest.t.sol";
import { console2 as console } from "forge-std/console2.sol";

/// @title SoftVaultTest
/// @notice Test common vault properties
/// @dev See https://github.com/crytic/properties/tree/125fa4135c8ad5e7599d1bf2dd2aa055d35a1ab6/contracts/ERC4626
contract SoftVaultTest is SoftVaultBaseTest {
    function testFork_SoftVault_getters() public {
        assertEq(vault.decimals(), underlying.decimals(), bTokenUSDC.decimals());
        assertEq(address(vault.getBToken()), address(bTokenUSDC));
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

    /// @notice Accounting system must not be vulnerable to share price inflation attacks
    function testForkFuzz_SoftVault_share_price_inflation_attack(uint256 inflateAmount, uint256 delta) public {
        // this has to be changed if there's deposit/withdraw fees
        uint256 lossThreshold = 0.999e18;

        // vault is fresh
        assertEq(underlying.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);

        // these minimums are to prevent 1-wei rounding errors from triggering the property
        inflateAmount = bound(inflateAmount, 10_000, type(uint128).max);
        delta = bound(delta, 0, type(uint128).max);

        uint256 victimDeposit = inflateAmount + delta;
        address attacker = bob;
        // fund account
        underlying.mint(attacker, inflateAmount);

        vm.prank(attacker);
        underlying.approve(address(vault), 1);
        vm.prank(attacker);
        uint256 shares = vault.deposit(1);
        console.log(shares);

        // attack only works when pps=1:1 + new vault
        assertEq(underlying.balanceOf(address(bTokenUSDC)), 1);
        if (shares != 1) return;

        // inflate pps
        vm.prank(attacker);
        underlying.transfer(address(vault), inflateAmount - 1);

        // fund victim
        underlying.mint(alice, victimDeposit);
        vm.prank(alice);
        underlying.approve(address(vault), victimDeposit);

        console.log("Amount of alice's deposit:", victimDeposit);
        vm.prank(alice);
        underlying.approve(address(vault), victimDeposit);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(victimDeposit);
        console.log("Alice Shares:", aliceShares);
        vm.prank(alice);
        uint256 aliceWithdrawnFunds = vault.withdraw(aliceShares);
        console.log("Amount of tokens alice withdrew:", aliceWithdrawnFunds);

        uint256 victimLoss = victimDeposit - aliceWithdrawnFunds;
        console.log("Alice Loss:", victimLoss);

        uint256 minRedeemedAmountNorm = (victimDeposit * lossThreshold) / 1e18;

        console.log("lossThreshold", lossThreshold);
        console.log("minRedeemedAmountNorm", minRedeemedAmountNorm);
        assertGt(
            aliceWithdrawnFunds,
            minRedeemedAmountNorm,
            "Share inflation attack possible, victim lost an amount over lossThreshold%"
        );
    }

    function testForkFuzz_SoftVault_deposit_full_withdraw_3_users(uint256[3] memory amounts) public {
        address[3] memory users = [alice, bob, carol];
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 totalAssetsBefore = underlying.balanceOf(address(bTokenUSDC));
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = bound(amounts[i], 1, type(uint128).max);
            underlying.mint(users[i], amounts[i]);

            totalAssets += amounts[i];

            vm.prank(users[i]);
            underlying.approve(address(vault), amounts[i]);
            vm.prank(users[i]);
            vault.deposit(amounts[i]);

            totalSupply += vault.balanceOf(users[i]);
        }
        uint256 totalAssetsAfter = underlying.balanceOf(address(bTokenUSDC));

        assertEq(
            totalAssetsAfter - totalAssetsBefore,
            totalAssets,
            "Total assets must be equal to the sum of users' deposits"
        );
        assertEq(vault.totalSupply(), totalSupply, "Total supply must be equal to the sum of users' balances");

        for (uint256 i = 0; i < 3; i++) {
            uint256 shareAmount = vault.balanceOf(users[i]);
            vm.prank(users[i]);
            vault.withdraw(shareAmount);
        }
        uint256 totalassetsFinal = underlying.balanceOf(address(bTokenUSDC));

        assertEq(totalassetsFinal, totalAssetsBefore, "Total assets must be equal to the initial amount");
        assertEq(vault.totalSupply(), 0, "Total supply must be equal to 0");
    }
}
