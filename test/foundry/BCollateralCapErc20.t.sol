// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */
/* solhint-disable no-console */

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { BaseTest, IUSDC } from "@test/BaseTest.t.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";

/// @title BCollateralCapErc20
/// @notice Test BCollateralCapErc20 properties
contract BCollateralCapErc20Test is BaseTest {
    function setUp() public override {
        super.setUp();
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

    function testForkFuzz_BCollateralCapErc20_mint_balanceOf_getAccountSnapshot(uint256 amount) public {
        amount = bound(amount, type(uint128).max / 2, type(uint128).max);
        ERC20PresetMinterPauser(USDC).mint(alice, amount);

        uint256 usdcBefore = ERC20PresetMinterPauser(USDC).balanceOf(alice);
        uint256 bTokenUSDCBefore = bTokenUSDC.balanceOf(alice);
        (, uint256 bTokenUSDCBalanceSnapshotBefore, , ) = bTokenUSDC.getAccountSnapshot(alice);
        assertEq(
            bTokenUSDCBefore,
            bTokenUSDCBalanceSnapshotBefore,
            "bToken balance must equal to account snapshot before"
        );

        address[] memory markets = new address[](1);
        markets[0] = address(bTokenUSDC);
        vm.prank(alice);
        comptroller.enterMarkets(markets);

        vm.prank(alice);
        ERC20PresetMinterPauser(USDC).approve(address(bTokenUSDC), amount);
        vm.prank(alice);
        bTokenUSDC.mint(amount);

        uint256 usdcAfter = ERC20PresetMinterPauser(USDC).balanceOf(alice);
        uint256 bTokenUSDCAfter = bTokenUSDC.balanceOf(alice);
        (, uint256 bTokenUSDCBalanceSnapshotAfter, , ) = bTokenUSDC.getAccountSnapshot(alice);
        uint256 exchangeRate = bTokenUSDC.exchangeRateCurrent();

        assertLt(usdcAfter, usdcBefore, "Mint must deduct ERC20PresetMinterPauser(USDC) from the sender");
        assertGt(bTokenUSDCAfter, bTokenUSDCBefore, "Mint must credit bToken to the sender");
        assertEq(
            bTokenUSDCAfter,
            (1e18 / exchangeRate) * usdcBefore,
            "Mint must credit bTokenUSDC to the sender equal to ERC20PresetMinterPauser(USDC) scaled by exchange rate"
        );
        assertGt(
            bTokenUSDCBalanceSnapshotAfter,
            bTokenUSDCBalanceSnapshotBefore,
            "Mint must credit bTokenUSDC balance snapshot to the sender"
        );
        assertEq(
            bTokenUSDCAfter,
            bTokenUSDCBalanceSnapshotAfter,
            "bToken balance must equal to bToken balance snapshot after"
        );
    }

    function testForkFuzz_BCollateralCapErc20_borrow(uint256 amount, uint256 borrowAmount) public {
        vm.rollFork(19073030);
        vm.prank(IUSDC(USDC).masterMinter());
        IUSDC(USDC).configureMinter(owner, type(uint256).max);
        _deployContracts();
        _enableBToken(bTokenUSDC);
        amount = bound(amount, type(uint128).max / 2, type(uint128).max);
        ERC20PresetMinterPauser(USDC).mint(alice, amount);

        address[] memory markets = new address[](1);
        markets[0] = address(bTokenUSDC);
        vm.startPrank(alice);
        comptroller.enterMarkets(markets);

        ERC20PresetMinterPauser(USDC).approve(address(bTokenUSDC), amount);
        bTokenUSDC.mint(amount);

        uint256 usdcBefore = ERC20PresetMinterPauser(USDC).balanceOf(alice);

        try bTokenUSDC.borrow(borrowAmount) {
            uint256 usdcAfter = ERC20PresetMinterPauser(USDC).balanceOf(alice);
            assertEq(
                usdcAfter,
                usdcBefore + borrowAmount,
                "Borrow must credit ERC20PresetMinterPauser(USDC) to the sender"
            );
            assertLt(borrowAmount, amount, "Borrow must never be more than the amount minted");
        } catch {}
    }
}
