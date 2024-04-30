// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */
/* solhint-disable no-console */

import "@contracts/utils/BlueberryConst.sol" as Constants;
import { SoftVaultBaseTest, State } from "@test/fork/vault/SoftVaultBaseTest.t.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { IExtBErc20 } from "@test/interfaces/IExtBErc20.sol";

/// @title SoftVaultTest
/// @notice Test common vault properties
/// @dev See https://github.com/crytic/properties/tree/125fa4135c8ad5e7599d1bf2dd2aa055d35a1ab6/contracts/ERC4626
contract SoftVaultTest is SoftVaultBaseTest {
    function testFork_SoftVault_getters() public {
        assertEq(vault.decimals(), bToken.decimals(), "Decimals must be set");
        assertGe(vault.decimals(), underlying.decimals(), "Vault must have higher precision than underlying");
        assertEq(address(vault.getBToken()), address(bToken), "bToken must be set");
        assertEq(address(vault.getUnderlyingToken()), address(underlying), "Underlying token must be set");
        assertEq(address(vault.getConfig()), address(config), "Config must be set");
    }

    function testForkFuzz_SoftVault_deposit(uint256 amount) public {
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, 1, type(uint128).max);
        underlying.mint(alice, amount);

        uint256 underlyingBefore = underlying.balanceOf(alice);
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 bTokenBefore = bToken.balanceOf(address(vault));

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        uint256 underlyingAfter = underlying.balanceOf(alice);
        uint256 sharesAfter = vault.balanceOf(alice);
        uint256 bTokenAfter = bToken.balanceOf(address(vault));

        assertLt(underlyingAfter, underlyingBefore, "Deposit must deduct underlying from the sender");
        assertGt(sharesAfter, sharesBefore, "Deposit must credit shares to the sender");
        assertGt(bTokenAfter, bTokenBefore, "Deposit must credit bToken to the vault");
        assertEq(vault.totalSupply(), vault.balanceOf(alice), "Total supply must be equal to the sender's balance");
    }

    function testFork_SoftVault_deposit_withdraw_few_shares_receive_0_assets() public {
        uint256 amount = 1;
        underlying.mint(alice, amount);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        uint256 shares = vault.deposit(amount);

        assertEq(underlying.balanceOf(alice), 0, "Deposit must deduct underlying from the sender");
        assertEq(vault.totalSupply(), shares, "Total supply must be increased");

        assertEq(vault.balanceOf(alice), shares, "Alice has shares");
        vm.prank(alice);
        vault.withdraw(1);

        assertEq(underlying.balanceOf(alice), 0, "Withdraw 1 shares will not credit underlying to the sender");
        assertEq(vault.balanceOf(alice), shares - 1, "Withdraw must deduct shares from the sender");
        assertEq(vault.totalSupply(), shares - 1, "Total supply must be deducted");
    }

    function testFork_SoftVault_deposit_withdraw_few_shares_multiple_times_do_not_receive_all_assets() public {
        uint8[2] memory amounts = [1, 2];
        address[2] memory users = [alice, bob];
        uint256 underlyingBefore = underlying.balanceOf(address(bToken));
        for (uint256 i = 0; i < 2; i++) {
            uint256 amount = amounts[i];
            address user = users[i];
            underlying.mint(user, amount);

            vm.prank(user);
            underlying.approve(address(vault), amount);
            vm.prank(user);
            vault.deposit(amount);

            uint256 sharesBefore = vault.balanceOf(user);

            for (uint256 j = 0; j < sharesBefore; j++) {
                vm.prank(user);
                vault.withdraw(1);
            }

            // @audit-issue Withdraw 1 shares N times will NOT credit underlying to the sender
            assertEq(
                underlying.balanceOf(user),
                0,
                "Withdraw 1 shares N times will NOT credit underlying to the sender"
            );
            assertEq(vault.balanceOf(user), 0, "Withdraw must deduct shares from the sender");
            assertEq(vault.totalSupply(), 0, "Total supply must be deducted by the sender's balance");
        }
        uint256 underlyingAfter = underlying.balanceOf(address(bToken));
        assertEq(
            underlyingAfter,
            underlyingBefore + amounts[0] + amounts[1],
            "Total assets is equal to the sum of deposits even after withdrawals"
        );
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

    function testForkFuzz_SoftVault_deposit_withdraw_full_does_not_credit_underlying_to_the_sender(
        uint256 amount
    ) public {
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, 1, type(uint128).max);
        underlying.mint(alice, amount);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        uint256 shareAmountAlice = vault.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(shareAmountAlice);

        uint256 underlyingAfter = underlying.balanceOf(alice);
        uint256 sharesAfter = vault.balanceOf(alice);

        assertLe(
            underlyingAfter,
            amount,
            "Withdraw does not credit underlying to the sender equal to deposited amount"
        );
        assertEq(sharesAfter, 0, "Withdraw must clear shares from the sender");
        assertEq(vault.totalSupply(), sharesAfter, "Total supply must be deducted by the sender's balance");
    }

    function testForkFuzz_SoftVault_deposit_is_order_independent(uint256[2] memory amounts) public {
        address[2] memory users = [alice, bob];
        uint256[2] memory shares = [type(uint256).max, type(uint256).max];
        uint256 sum;
        for (uint256 i = 0; i < users.length; i++) {
            // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
            amounts[i] = bound(amounts[i], 1000, type(uint128).max);
            underlying.mint(users[i], amounts[i]);

            vm.prank(users[i]);
            underlying.approve(address(vault), amounts[i]);
            vm.prank(users[i]);
            shares[i] = vault.deposit(amounts[i]);

            sum += amounts[i];
        }

        users = [bob, alice];
        amounts = [amounts[1], amounts[0]];
        shares = [shares[1], shares[0]];

        for (uint256 i = 0; i < users.length; i++) {
            underlying.mint(users[i], amounts[i]);

            vm.prank(users[i]);
            underlying.approve(address(vault), amounts[i]);
            vm.prank(users[i]);
            uint256 s = vault.deposit(amounts[i]);

            assertEq(s, shares[i], "Deposit must be order independent");
        }
    }

    function testForkFuzz_SoftVault_deposit_is_order_independent_with_borrow(uint256[2] memory amounts) public {
        vm.rollFork(19073030);
        _deployContracts();
        _configureMinter();
        _deployVault();
        _enableBorrow();
        address[2] memory users = [alice, bob];
        uint256[2] memory shares = [type(uint256).max, type(uint256).max];
        uint256 sum;
        for (uint256 i = 0; i < users.length; i++) {
            // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
            amounts[i] = bound(amounts[i], type(uint128).max / 2, type(uint128).max);
            underlying.mint(users[i], amounts[i]);

            vm.prank(users[i]);
            underlying.approve(address(vault), amounts[i]);
            vm.prank(users[i]);
            shares[i] = vault.deposit(amounts[i]);

            sum += amounts[i];
        }

        uint256 amount = sum * 100;

        // borrow
        underlying.mint(carol, amount);
        address[] memory markets = new address[](1);
        markets[0] = address(bToken);
        vm.prank(carol);
        comptroller.enterMarkets(markets);

        vm.prank(carol);
        underlying.approve(address(bToken), amount);
        vm.prank(carol);
        bToken.mint(amount);

        uint256 borrowAmount = amount / 10;
        vm.prank(carol);
        bToken.borrow(borrowAmount);

        users = [bob, alice];
        amounts = [amounts[1], amounts[0]];
        shares = [shares[1], shares[0]];

        for (uint256 i = 0; i < users.length; i++) {
            underlying.mint(users[i], amounts[i]);

            vm.prank(users[i]);
            underlying.approve(address(vault), amounts[i]);
            vm.prank(users[i]);
            uint256 s = vault.deposit(amounts[i]);

            assertEq(s, shares[i], "Deposit must be order independent");
        }
    }

    function testForkFuzz_SoftVault_deposit_withdraw_with_fees(
        uint256 amount,
        uint256 shareAmountAlice,
        uint256 withdrawFeeRate,
        uint256 interval
    ) public {
        vm.rollFork(19073030);
        _deployContracts();
        _configureMinter();
        _deployVault();
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

    function testFork_SoftVault_share_price_inflation_attack_concrete() public {
        // @audit-issue Vault is vulnerable to share price inflation attack
        return testForkFuzz_SoftVault_share_price_inflation_attack(2987494030, 569);
    }

    function testForkFuzz_SoftVault_share_price_inflation_attack(uint256 inflateAmount, uint256 delta) public {
        vm.rollFork(19068161);
        _deployContracts();

        // this has to be changed if there's deposit/withdraw fees
        uint256 lossThreshold = 0.999e18;
        uint256 percent = 1e18;

        underlying = ERC20PresetMinterPauser(DAI);
        bToken = IBErc20(address(BDAI));
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
                            address(this)
                        )
                    )
                )
            )
        );

        // vault is fresh
        assertEq(underlying.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);

        // these minimums are to prevent 1-wei rounding errors from triggering the property
        inflateAmount = bound(inflateAmount, 10_000, type(uint128).max);
        delta = bound(delta, 0, type(uint128).max);

        uint256 victimDeposit = inflateAmount + delta;
        address attacker = bob;
        // fund account
        deal(DAI, attacker, inflateAmount);

        vm.prank(attacker);
        underlying.approve(address(vault), 1);
        vm.prank(attacker);
        uint256 shares = vault.deposit(1);
        console.log(shares);

        // attack only works when pps=1:1 + new vault
        if (shares > 1) {
            return;
        }

        // inflate pps
        vm.prank(attacker);
        underlying.transfer(address(bToken), inflateAmount - 1);

        // fund victim
        deal(DAI, alice, victimDeposit);
        vm.prank(alice);
        underlying.approve(address(vault), victimDeposit);

        console.log("Amount of alice's deposit:", victimDeposit);
        vm.prank(alice);
        underlying.approve(address(vault), victimDeposit);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(victimDeposit);
        console.log("Alice Shares:", aliceShares);

        if (aliceShares == 0) {
            return;
        }

        vm.prank(alice);
        uint256 aliceWithdrawnFunds = vault.withdraw(aliceShares);
        console.log("Amount of tokens alice withdrew:", aliceWithdrawnFunds);

        uint256 victimLoss = victimDeposit - aliceWithdrawnFunds;
        console.log("Alice Loss:", victimLoss);

        uint256 minRedeemedAmountNorm = (victimDeposit * lossThreshold) / percent;

        console.log("lossThreshold%", lossThreshold);
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
        uint256 totalAssetsBefore = underlying.balanceOf(address(bToken));
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
        uint256 totalAssetsAfter = underlying.balanceOf(address(bToken));

        assertEq(
            totalAssetsAfter - totalAssetsBefore,
            totalAssets,
            "Total assets must be equal to the sum of users' deposits"
        );
        assertEq(vault.totalSupply(), totalSupply, "Total supply must be equal to the sum of users' balances");

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 shareAmount = vault.balanceOf(users[i]);
            vm.prank(users[i]);
            vault.withdraw(shareAmount);
        }
        uint256 totalassetsFinal = underlying.balanceOf(address(bToken));

        string error1 = "Total assets must be greater than or  equal to the initial amount";
        string error2 = "(see testFork_SoftVault_deposit_withdraw_few_shares_multiple_times_do_not_receive_all_assets)";

        assertGe(totalassetsFinal, totalAssetsBefore, string(abi.encodepacked(error1, error2)));
        assertEq(vault.totalSupply(), 0, "Total supply must be equal to 0");
    }

    function testForkFuzz_SoftVault_deposit_pass_time_withdraw(uint256 amount) public {
        vm.rollFork(19073030);
        _deployContracts();
        _configureMinter();
        _deployVault();
        _enableBorrow();
        // not using `type(uint256).max` as the maximum value since it makes `vault.deposit` overflow
        amount = bound(amount, type(uint32).max / 2, type(uint32).max);
        underlying.mint(alice, amount);
        underlying.mint(bob, amount);

        vm.prank(alice);
        underlying.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        address[] memory markets = new address[](1);
        markets[0] = address(bToken);
        vm.prank(bob);
        comptroller.enterMarkets(markets);

        vm.prank(bob);
        underlying.approve(address(bToken), amount);
        vm.prank(bob);
        bToken.mint(amount);

        uint256 borrowAmount = amount / 10;
        vm.prank(bob);
        bToken.borrow(borrowAmount);

        vm.warp(block.timestamp + 30 days);

        uint256 shareAmountAlice = vault.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(shareAmountAlice);

        assertGt(underlying.balanceOf(alice), amount, "Vault must grow over time");
    }
}
