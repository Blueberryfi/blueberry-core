// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */
/* solhint-disable no-console */

import { BaseTest } from "@test/BaseTest.t.sol";

/// @title BCollateralCapErc20
/// @notice Test BCollateralCapErc20 properties
contract BCollateralCapErc20Test is BaseTest {
    function testForkFuzz_BCollateralCapErc20_mint_balanceOf_getAccountSnapshot(uint256 amount) public {
        amount = bound(amount, type(uint128).max / 2, type(uint128).max);
        underlying.mint(alice, amount);

        uint256 underlyingBefore = underlying.balanceOf(alice);
        uint256 bTokenBefore = bToken.balanceOf(alice);
        (, uint256 bTokenBalanceSnapshotBefore, , ) = bToken.getAccountSnapshot(alice);
        assertEq(bTokenBefore, bTokenBalanceSnapshotBefore, "bToken balance must equal to account snapshot before");

        address[] memory markets = new address[](1);
        markets[0] = address(bToken);
        vm.prank(alice);
        comptroller.enterMarkets(markets);

        vm.prank(alice);
        underlying.approve(address(bToken), amount);
        vm.prank(alice);
        bToken.mint(amount);

        uint256 underlyingAfter = underlying.balanceOf(alice);
        uint256 bTokenAfter = bToken.balanceOf(alice);
        (, uint256 bTokenBalanceSnapshotAfter, , ) = bToken.getAccountSnapshot(alice);
        uint256 exchangeRate = bToken.exchangeRateCurrent();

        assertLt(underlyingAfter, underlyingBefore, "Mint must deduct underlying from the sender");
        assertGt(bTokenAfter, bTokenBefore, "Mint must credit bToken to the sender");
        assertEq(
            bTokenAfter,
            (1e18 / exchangeRate) * underlyingBefore,
            "Mint must credit bToken to the sender equal to underlying scaled by exchange rate"
        );
        assertGt(
            bTokenBalanceSnapshotAfter,
            bTokenBalanceSnapshotBefore,
            "Mint must credit bToken balance snapshot to the sender"
        );
        assertEq(bTokenAfter, bTokenBalanceSnapshotAfter, "bToken balance must equal to bToken balance snapshot after");
    }

    function testForkFuzz_BCollateralCapErc20_borrow(uint256 amount, uint256 borrowAmount) public {
        vm.rollFork(19073030);
        _setupFork();
        amount = bound(amount, type(uint128).max / 2, type(uint128).max);
        underlying.mint(alice, amount);

        address[] memory markets = new address[](1);
        markets[0] = address(bToken);
        vm.prank(alice);
        comptroller.enterMarkets(markets);

        vm.prank(alice);
        underlying.approve(address(bToken), amount);
        vm.prank(alice);
        bToken.mint(amount);

        uint256 underlyingBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        try bToken.borrow(borrowAmount) {
            uint256 underlyingAfter = underlying.balanceOf(alice);
            assertEq(underlyingAfter, underlyingBefore + borrowAmount, "Borrow must credit underlying to the sender");
            assertLt(borrowAmount, amount, "Borrow must never be more than the amount minted");
        } catch {}
    }
}