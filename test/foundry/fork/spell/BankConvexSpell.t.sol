// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank, console2, ERC20PresetMinterPauser } from "@test/BaseTest.t.sol";
import { SpellBaseTest, IBank } from "@test/fork/spell/SpellBaseTest.t.sol";
import { IOwnable } from "@test/interfaces/IOwnable.sol";
import { ConvexSpell } from "@contracts/spell/ConvexSpell.sol";
import { BasicSpell } from "@contracts/spell/BasicSpell.sol";
import { IBasicSpell } from "@contracts/interfaces/spell/IBasicSpell.sol";
import { IConvexSpell } from "@contracts/interfaces/spell/IConvexSpell.sol";
import { IWConvexBooster } from "@contracts/interfaces/IWConvexBooster.sol";
import { ICurveOracle } from "@contracts/interfaces/ICurveOracle.sol";
import { ICoreOracle } from "@contracts/interfaces/ICoreOracle.sol";
import { IRewarder } from "@contracts/interfaces/convex/IRewarder.sol";
import { IConvex } from "@contracts/interfaces/convex/IConvex.sol";
import { MockOracle } from "@contracts/mock/MockOracle.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import { DENOMINATOR } from "@contracts/utils/BlueberryConst.sol";
import { PRICE_PRECISION } from "@contracts/utils/BlueberryConst.sol";
import { EXCEED_MAX_LTV } from "@contracts/utils/BlueberryErrors.sol";
import { EXCEED_MAX_POS_SIZE } from "@contracts/utils/BlueberryErrors.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { MockParaswap } from "@contracts/mock/MockParaswap.sol";
import { MockParaswapTransferProxy } from "@contracts/mock/MockParaswapTransferProxy.sol";

import { ICurvePool } from "@test/interfaces/ICurvePool.sol";
import { ICvxBooster } from "@test/interfaces/ICvxBooster.sol";
import { ILiquidityGauge } from "@test/interfaces/ILiquidityGauge.sol";
import { IExtCoreOracle } from "@test/interfaces/IExtCoreOracle.sol";

import { WConvexBoosterMock } from "@test/fork/spell/mocks/WConvexBoosterMock.sol";

import { ParaSwapSnapshot } from "@test/fork/ParaSwapSnapshot.t.sol";

import { Quoter } from "@test/Quoter.t.sol";

contract BankConvexSpell is SpellBaseTest, ParaSwapSnapshot, Quoter {
    ConvexSpell public convexSpell;

    IWConvexBooster public wConvexBooster;
    ICurveOracle public curveOracle;
    ICoreOracle public coreOracle;
    ConvexSpell internal _intConvexSpell; // Needed for vm.etch => debug inside the contracts
    WConvexBoosterMock internal _wConvexBoosterMock;
    MockOracle public mockOracle;
    SoftVault internal _intSoftVault;
    MockParaswap public mockParaswap;
    MockParaswapTransferProxy public mockParaswapTransferProxy;

    address public CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address public spellOwner;
    uint256 public CURVE_FEE = 505800; // 0.005058 % approximation
    uint256 public CURVE_FEE_DENOMINATOR = 10_000_000_000; // 100%

    struct CachedValues {
        uint256 poolId;
        uint256 positionId;
        address lpToken;
        uint256 initialRewardPerShare;
        address pool;
        uint256 timestamp;
        uint256 initialDebtValue;
        uint256 initialCollateral;
        uint256 maxSharesRedeemed;
    }

    struct CachedBalances {
        uint256[] balanceOfUserRewardsBefore;
        uint256[] balanceOfTreasuryRewardsBefore;
        uint256[] balanceOfUserRewardsAfter;
        uint256[] balanceOfTreasuryRewardsAfter;
    }

    function setUp() public override {
        super.setUp();

        _assignDeployedContracts();

        _enableBToken(bTokenWETH);

        spellOwner = IOwnable(address(convexSpell)).owner();

        wConvexBooster = convexSpell.getWConvexBooster();
        _wConvexBoosterMock = new WConvexBoosterMock();
        vm.etch(address(wConvexBooster), address(_wConvexBoosterMock).code);
        curveOracle = convexSpell.getCrvOracle();
    }

    function testFork_BankConvexSpell_openPositionFarmSuccess() external {
        uint256 collateralAmount = 10e18;
        uint256 borrowAmount = 2e18;
        uint256 poolId = 25;

        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(poolId);
        vm.label(lpToken, "lpToken");
        (address pool, , ) = curveOracle.getPoolInfo(lpToken);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);

        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: poolId
        });

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount, true);

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 0));
        // Used to make sure the right amount of LP landed at destination
        uint256 balanceBefore = _getLpBalance(poolId, lpToken);

        bank.execute(0, address(convexSpell), data);

        uint256 balanceAfter = _getLpBalance(poolId, lpToken);
        IBank.Position memory position;
        _validateReceivedBorrowAndPosition(position, 1, slippage);
        // Check if the right amount of LP landed at destination
        assertApproxEqRel(balanceAfter - balanceBefore, slippage, 0.000001e18);
    }

    function testForkFuzz_BankConvexSpell_openNewPositionGeneratesRightLPToken(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 slippagePercent
    ) public {
        (address lpt, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address p, , ) = curveOracle.getPoolInfo(lpt);
        collateralAmount = bound(collateralAmount, 1, type(uint128).max - 1);
        borrowAmount = bound(borrowAmount, 1, ICurvePool(p).balances(0));
        // limiting to curve pool's balance, NOTE should try test with increasing the POOL
        slippagePercent = bound(slippagePercent, 10 /* 0.1% */, 500 /* 5% */);

        // avoid stack-too-deep
        {
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), borrowAmount);
            uint256 icollValue = coreOracle.getTokenValue(USDC, collateralAmount);
            uint256 maxLTV = convexSpell.getMaxLTV(0, USDC);
            // if borrow value is greater than MAX ltv return as it will revert anyway.
            if (borrowValue < 1 || borrowValue > (icollValue * maxLTV) / DENOMINATOR) return;
        }

        uint256 poolId = 25;
        uint256 positionId = 0;
        address lpToken = lpt;
        address pool = p;

        IBasicSpell.Strategy memory strategy = convexSpell.getStrategy(0);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);
        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: poolId
        });

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount, true);
        // calculate the lp token received by curve
        slippage = _calculateSlippage(slippage, slippagePercent); // add the slippage
        (bool valid, IBank.Position memory previousPosition) = _validatePositionSize(
            slippage,
            lpToken,
            strategy.maxPositionSize,
            positionId
        );
        if (!valid) return; // making sure it validates the position min/max size

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, slippage));
        // Used to make sure the right amount of LP landed at destination
        uint256 balanceBeforeLP = _getLpBalance(poolId, lpToken);

        try bank.execute(positionId, address(convexSpell), data) {} catch (bytes memory reason) {
            bytes4 maxTVLSelector = bytes4(keccak256(bytes("EXCEED_MAX_LTV()")));
            bytes4 minPositionSelector = bytes4(keccak256(bytes("EXCEED_MIN_POS_SIZE(uint256)")));
            bytes4 maxPositionSelector = bytes4(keccak256(bytes("EXCEED_MAX_POS_SIZE(uint256)")));
            bytes4 receivedSelector = bytes4(reason);
            if (
                maxTVLSelector != receivedSelector &&
                minPositionSelector != receivedSelector &&
                maxPositionSelector != receivedSelector
            ) revert("");

            return;
        }
        // Validate that the position was updated correctly
        _validateReceivedBorrowAndPosition(previousPosition, positionId, slippage);

        // Validate that the collateral ID is encoded as expected.
        // The collateral ID is keeping the cvx share used in rewards
        _checkTokenIdEncoding(poolId, positionId);

        uint256 balanceAfterLP = _getLpBalance(poolId, lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertGe(balanceAfterLP - balanceBeforeLP, slippage, "LP landed in reward contract mismatch");
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0, "Remaining USDC in the initiator");
    }

    /// Fuzz open position that generates the right LP Tokens.
    /// We use an internal function to call some edge-cases that should revert
    function testForkFuzz_BankConvexSpell_openExistingPositionGeneratesRightLPToken(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 slippagePercent
    ) public {
        (address lpt, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address p, , ) = curveOracle.getPoolInfo(lpt);
        collateralAmount = bound(collateralAmount, 1, type(uint128).max - 1);
        // limiting to curve pool's balance, NOTE should try test with increasing the POOL
        borrowAmount = bound(borrowAmount, 1, ICurvePool(p).balances(0) - 1);
        slippagePercent = bound(slippagePercent, 10 /* 0.1% */, 500 /* 5% */);

        uint256 slippage = _calculateSlippageCurve(p, borrowAmount, true); // calculate the lp token received by curve
        IBasicSpell.Strategy memory strategy = convexSpell.getStrategy(0);

        (bool valid, ) = _validatePositionSize(slippage, lpt, strategy.maxPositionSize, 0);
        if (!valid) return; // making sure it validates the position min/max size
        openExistingPositionGeneratesRightLPToken(collateralAmount, borrowAmount, slippagePercent);
    }

    function test_testFork_BankConvexSpell_openExistingPositionGeneratesRightLPToken_Revert_WithMaxPos() public {
        uint256 collateralAmount = 182210610927678553752966593788471477096;
        uint256 borrowAmount = 187087916770269888819;
        uint256 slippagePercent = 449;
        (address lpt, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address p, , ) = curveOracle.getPoolInfo(lpt);
        // avoid stack-too-deep
        {
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), borrowAmount);
            uint256 icollValue = coreOracle.getTokenValue(USDC, collateralAmount);
            uint256 maxLTV = convexSpell.getMaxLTV(0, USDC);

            // if borrow value is greater than MAX ltv return as it will revert anyway.
            if (borrowValue < 1 || borrowValue > (icollValue * maxLTV) / DENOMINATOR) return;
        }

        uint256 poolId = 25;
        uint256 positionId = 1;
        address lpToken = lpt;
        address pool = p;
        // Opening initial position
        _openInitialPosition(poolId, 1e18, 1.5e18);

        IBasicSpell.Strategy memory strategy = convexSpell.getStrategy(0);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);
        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: poolId
        });

        // calculate the lp token received by curve
        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount, true);
        slippage = _calculateSlippage(slippage, slippagePercent); // add the slippage
        (bool valid, ) = _validatePositionSize(slippage, lpToken, strategy.maxPositionSize, positionId);
        if (!valid) return; // making sure it validates the position min/max size

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, slippage));

        vm.expectRevert(abi.encodeWithSelector(EXCEED_MAX_POS_SIZE.selector, 0));
        bank.execute(positionId, address(convexSpell), data);
    }

    function openExistingPositionGeneratesRightLPToken(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 slippagePercent
    ) public {
        (address lpt, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address p, , ) = curveOracle.getPoolInfo(lpt);
        // avoid stack-too-deep
        {
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), borrowAmount);
            uint256 icollValue = coreOracle.getTokenValue(USDC, collateralAmount);
            uint256 maxLTV = convexSpell.getMaxLTV(0, USDC);

            // if borrow value is greater than MAX ltv return as it will revert anyway.
            if (borrowValue < 1 || borrowValue > (icollValue * maxLTV) / DENOMINATOR) return;
        }

        uint256 poolId = 25;
        uint256 positionId = 1;
        address lpToken = lpt;
        address pool = p;
        // Opening initial position
        _openInitialPosition(poolId, 1e18, 1.5e18);

        IBasicSpell.Strategy memory strategy = convexSpell.getStrategy(0);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);
        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: poolId
        });

        // calculate the lp token received by curve
        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount, true);
        slippage = _calculateSlippage(slippage, slippagePercent); // add the slippage
        (bool valid, IBank.Position memory previousPosition) = _validatePositionSize(
            slippage,
            lpToken,
            strategy.maxPositionSize,
            positionId
        );
        if (!valid) return; // making sure it validates the position min/max size

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, slippage));
        // Used to make sure the right amount of LP landed at destination
        uint256 balanceBeforeLP = _getLpBalance(poolId, lpToken);

        bank.execute(positionId, address(convexSpell), data);

        // Validate that the position was updated correctly
        _validateReceivedBorrowAndPosition(previousPosition, positionId, slippage);

        // Validate that the collateral ID is encoded as expected.
        // The collateral ID is keeping the cvx share used in rewards
        _checkTokenIdEncoding(poolId, positionId);

        uint256 balanceAfterLP = _getLpBalance(poolId, lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertGe(balanceAfterLP - balanceBeforeLP, slippage, "LP landed in reward contract mismatch");
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0, "Remaining USDC in the initiator");
    }

    function testConcrete() external {
        testForkFuzz_BankConvexSpell_closeNewPositionNoSwapOnRewardsWithCollateralInMoneyMarket(
            79228162513264337619055631824,
            25511681489,
            991956208122718828,
            1
        );
    }

    function testForkFuzz_BankConvexSpell_openExistingPositionGeneratesRightRewards(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 slippagePercent,
        uint256 timestamp
    ) public {
        _setMockOracle();
        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address pool, , ) = curveOracle.getPoolInfo(lpToken);
        collateralAmount = bound(collateralAmount, 1, type(uint128).max - 1);
        // limiting to curve pool's balance, NOTE should try test with increasing the POOL
        borrowAmount = bound(borrowAmount, 1, ICurvePool(pool).balances(0));
        slippagePercent = bound(slippagePercent, 10 /* 0.1% */, 500 /* 5% */);
        timestamp = bound(timestamp, 12, 365 days);

        // avoid stack-too-deep
        {
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), borrowAmount);
            uint256 icollValue = coreOracle.getTokenValue(USDC, collateralAmount);
            uint256 maxLTV = convexSpell.getMaxLTV(0, USDC);

            // if borrow value is greater than MAX ltv return as it will revert anyway.
            if (borrowValue < 1 || borrowValue > (icollValue * maxLTV) / DENOMINATOR) return;
        }

        CachedValues memory cachedValues = CachedValues({
            poolId: 25,
            positionId: 1,
            lpToken: lpToken,
            initialRewardPerShare: 0,
            pool: pool,
            timestamp: timestamp,
            initialDebtValue: 0,
            initialCollateral: collateralAmount,
            maxSharesRedeemed: 0
        });
        // Opening initial position
        _openInitialPosition(cachedValues.poolId, 1e18, 1.5e18);

        IBasicSpell.Strategy memory strategy = convexSpell.getStrategy(0);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);
        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: cachedValues.poolId
        });

        // calculate the lp token received by curve
        uint256 slippage = _calculateSlippageCurve(cachedValues.pool, borrowAmount, true);
        slippage = _calculateSlippage(slippage, slippagePercent); // add the slippage
        (bool valid, IBank.Position memory previousPosition) = _validatePositionSize(
            slippage,
            cachedValues.lpToken,
            strategy.maxPositionSize,
            cachedValues.positionId
        );
        if (!valid) return; // making sure it validates the position min/max size

        // bytes memory data = ;
        // Used to make sure the right amount of LP landed at destination
        uint256 balanceBeforeLP = _getLpBalance(cachedValues.poolId, cachedValues.lpToken);

        {
            CachedBalances memory cachedBalances;
            // getting the rewards before the time passes
            (uint256[] memory rewardsBefore, address[] memory rewardTokensBefore) = _getRewards(cachedValues);
            cachedBalances.balanceOfUserRewardsBefore = new uint256[](rewardsBefore.length);
            cachedBalances.balanceOfTreasuryRewardsBefore = new uint256[](rewardsBefore.length);
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfUserRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i]).balanceOf(
                    owner
                );
            }

            address feeTreasury = bank.getFeeManager().getConfig().getTreasury();
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            // we move the timestamp
            vm.warp(block.timestamp + cachedValues.timestamp);

            // rewards should have been accrued
            (uint256[] memory rewards, address[] memory rewardTokens) = _getRewards(cachedValues);

            // execute the spell, should yield the rewards in the owner's wallet
            bank.execute(
                cachedValues.positionId,
                address(convexSpell),
                abi.encodeCall(ConvexSpell.openPositionFarm, (param, slippage))
            );

            // checking that the balances in the wallet are rewards - fees
            cachedBalances.balanceOfUserRewardsAfter = new uint256[](rewardTokens.length);
            cachedBalances.balanceOfTreasuryRewardsAfter = new uint256[](rewardTokens.length);
            for (uint256 i; i < rewardTokens.length; ++i) {
                cachedBalances.balanceOfUserRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokens[i]).balanceOf(owner);
            }

            // checking that the treasury balance was updated accordingly
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            assertEq(rewardsBefore.length, rewards.length, "Rewards length mismatch");
            for (uint i; i < rewardsBefore.length; ++i) {
                uint256 toRefund = rewards[i] - rewardsBefore[i];
                uint256 feeRate = bank.getFeeManager().getConfig().getRewardFee();
                uint256 cutFee = (toRefund * feeRate) / DENOMINATOR;
                assertApproxEqAbs(
                    toRefund - cutFee,
                    cachedBalances.balanceOfUserRewardsAfter[i] - cachedBalances.balanceOfUserRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the user"
                );

                assertApproxEqAbs(
                    cutFee,
                    cachedBalances.balanceOfTreasuryRewardsAfter[i] - cachedBalances.balanceOfTreasuryRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the treasury"
                );
            }
        }

        // Validate that the position was updated correctly
        _validateReceivedBorrowAndPosition(previousPosition, cachedValues.positionId, slippage);

        // Validate that the collateral ID is encoded as expected.
        //The collateral ID is keeping the cvx share used in rewards
        _checkTokenIdEncoding(cachedValues.poolId, cachedValues.positionId);

        uint256 balanceAfterLP = _getLpBalance(cachedValues.poolId, cachedValues.lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertGe(balanceAfterLP - balanceBeforeLP, slippage, "LP landed in reward contract mismatch");
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0, "Remaining USDC in the initiator");
    }

    function testForkFuzz_BankConvexSpell_closeNewPositionNoSwapOnRewardsNoCollateralInMoneyMarket(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 timestamp
    ) public {
        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address pool, , ) = curveOracle.getPoolInfo(lpToken);
        collateralAmount = bound(collateralAmount, 1, type(uint96).max - 1);
        borrowAmount = bound(borrowAmount, 1, ICurvePool(pool).balances(0));
        timestamp = bound(timestamp, 1, 1 days);

        _setMockOracle();
        CachedValues memory cachedValues = CachedValues({
            poolId: 25,
            positionId: 1,
            lpToken: lpToken,
            initialRewardPerShare: 0,
            pool: pool,
            timestamp: timestamp,
            initialDebtValue: 0,
            initialCollateral: collateralAmount,
            maxSharesRedeemed: 0
        });

        // Opening initial position with random values, skip when it fails as we don't test the open initial position
        if (!_openInitialPositionNoRevert(cachedValues.poolId, collateralAmount, borrowAmount)) return;

        // avoid stack-too-deep, calculating initial reward per token for crv rewards
        {
            ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

            (, , , address crvRewarder, , ) = cvxBooster.poolInfo(cachedValues.poolId);

            cachedValues.initialRewardPerShare = IRewarder(crvRewarder).rewardPerToken();
        }

        IBank.Position memory currentPosition = bank.getPositionInfo(cachedValues.positionId);
        cachedValues.initialDebtValue = _calculateDebtValue(
            cachedValues.pool,
            currentPosition.collateralSize,
            cachedValues.positionId
        );
        bytes memory swapDataDebt = _getParaswapData(
            address(USDC),
            address(WETH),
            cachedValues.initialDebtValue,
            address(convexSpell),
            100
        );
        IBasicSpell.ClosePosParam memory closePosParam = IBasicSpell.ClosePosParam({
            strategyId: 0,
            collToken: address(USDC),
            borrowToken: address(WETH),
            amountRepay: type(uint256).max,
            amountPosRemove: currentPosition.collateralSize,
            // This will be updated after warp to account for exchange rate change on money market
            // advances in timestamp yield interest for the lender in money market,
            //user receives yield for his collateral
            amountShareWithdraw: 0,
            amountOutMin: 0,
            amountToSwap: 0.1 ether,
            swapData: swapDataDebt
        });

        {
            CachedBalances memory cachedBalances;
            // getting the rewards before the time passes
            (uint256[] memory rewardsBefore, address[] memory rewardTokensBefore) = _getRewards(cachedValues);
            cachedBalances.balanceOfUserRewardsBefore = new uint256[](rewardsBefore.length);
            cachedBalances.balanceOfTreasuryRewardsBefore = new uint256[](rewardsBefore.length);
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfUserRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i]).balanceOf(
                    owner
                );
            }

            address feeTreasury = bank.getFeeManager().getConfig().getTreasury();
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            // we move the timestamp
            vm.warp(block.timestamp + cachedValues.timestamp);
            cachedValues.maxSharesRedeemed = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();
            if (cachedValues.maxSharesRedeemed > currentPosition.underlyingVaultShare)
                cachedValues.maxSharesRedeemed = currentPosition.underlyingVaultShare;

            closePosParam.amountShareWithdraw = cachedValues.maxSharesRedeemed;

            {
                uint256 debtAfter = _calculateDebtValue(
                    cachedValues.pool,
                    currentPosition.collateralSize,
                    cachedValues.positionId
                );

                // debt value is in borrow token so we need to normalize in collateral token
                uint256 debtValue = coreOracle.getTokenValue(address(WETH), debtAfter);
                uint256 collTokenPrice = coreOracle.getPrice(address(USDC));

                // Calculate how much we need to swap to cover the debt accrued by the borrowed funds
                closePosParam.amountToSwap = (debtValue * 1e18) / collTokenPrice;

                // If we need to swap more than initial collateral that was supplied, we need to increase the position.
                if (closePosParam.amountToSwap > cachedValues.initialCollateral) {
                    uint256 amountToIncrease = closePosParam.amountToSwap - cachedValues.initialCollateral;
                    amountToIncrease = amountToIncrease * 1.1e18; // we increase with 10% to cover the fees
                    _increasePosition(amountToIncrease, cachedValues.positionId);

                    currentPosition = bank.getPositionInfo(cachedValues.positionId);
                    cachedValues.maxSharesRedeemed = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();
                    cachedValues.initialCollateral += amountToIncrease;
                    if (cachedValues.maxSharesRedeemed > currentPosition.underlyingVaultShare)
                        cachedValues.maxSharesRedeemed = currentPosition.underlyingVaultShare;

                    closePosParam.amountShareWithdraw = cachedValues.maxSharesRedeemed;
                }
                bytes memory swapDataDebt = _getParaswapData(
                    address(USDC),
                    address(WETH),
                    closePosParam.amountToSwap,
                    address(convexSpell),
                    100
                );
                closePosParam.swapData = swapDataDebt;
            }
            // rewards should have been accrued
            (uint256[] memory rewards, address[] memory rewardTokens) = _getRewards(cachedValues);

            bytes[] memory swapDatas = new bytes[](rewards.length);
            IConvexSpell.ClosePositionFarmParam memory closePositionFarmParams = IConvexSpell.ClosePositionFarmParam({
                param: closePosParam,
                amounts: rewards,
                swapDatas: swapDatas
            });

            bytes memory data = abi.encodeCall(ConvexSpell.closePositionFarm, (closePositionFarmParams));

            // execute the spell, should yield the rewards in the owner's wallet
            bank.execute(cachedValues.positionId, address(convexSpell), data);

            // checking that the balances in the wallet are rewards - fees
            cachedBalances.balanceOfUserRewardsAfter = new uint256[](rewardTokens.length);
            cachedBalances.balanceOfTreasuryRewardsAfter = new uint256[](rewardTokens.length);
            for (uint256 i; i < rewardTokens.length; ++i) {
                cachedBalances.balanceOfUserRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokens[i]).balanceOf(owner);
            }

            // checking that the treasury balance was updated accordingly
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            assertEq(rewardsBefore.length, rewards.length, "Rewards length mismatch");
            for (uint i; i < rewardsBefore.length; ++i) {
                uint256 toRefund = rewards[i] - rewardsBefore[i];
                uint256 feeRate = bank.getFeeManager().getConfig().getRewardFee();
                uint256 cutFee = (toRefund * feeRate) / DENOMINATOR;
                assertApproxEqAbs(
                    toRefund - cutFee,
                    cachedBalances.balanceOfUserRewardsAfter[i] - cachedBalances.balanceOfUserRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the user"
                );

                assertApproxEqAbs(
                    cutFee,
                    cachedBalances.balanceOfTreasuryRewardsAfter[i] - cachedBalances.balanceOfTreasuryRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the treasury"
                );
            }
        }
        {
            // checking that the position closed and that the user is not in loss,
            // should accrue interest from the money market
            IBank.Position memory afterPosition = bank.getPositionInfo(cachedValues.positionId);

            assertEq(afterPosition.collateralSize, 0, "After position collateral size not cleared");
            assertEq(afterPosition.debtShare, 0, "After position debt share not cleared");
            // assertEq(afterPosition.underlyingVaultShare, 0, "After position underlying vault share not cleared");
            // NOTE this fails as vault shares might still exists

            uint256 balanceOfCollateralAfter = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);
            uint256 balanceOfBorrowAfter = ERC20PresetMinterPauser(address(WETH)).balanceOf(owner);

            uint256 collateral = cachedValues.initialCollateral;

            collateral = _calculateFeesOnCollateral(collateral, false);

            uint256 debtValue = coreOracle.getTokenValue(address(USDC), closePosParam.amountToSwap);
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), balanceOfBorrowAfter);
            uint256 collValue = coreOracle.getTokenValue(address(USDC), balanceOfCollateralAfter);
            uint256 initialColValue = coreOracle.getTokenValue(address(USDC), collateral);

            assertGe(borrowValue + collValue, initialColValue - debtValue, "User in loss");
        }
    }

    function testForkFuzz_BankConvexSpell_closeNewPositionNoSwapOnRewardsWithCollateralInMoneyMarket(
        uint256 existingCollateral,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 timestamp
    ) public {
        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address pool, , ) = curveOracle.getPoolInfo(lpToken);
        existingCollateral = bound(collateralAmount, 1e18, type(uint96).max - 1);

        collateralAmount = bound(collateralAmount, 1, type(uint96).max - 1);
        borrowAmount = bound(borrowAmount, 1, ICurvePool(pool).balances(0));
        timestamp = bound(timestamp, 1, 1 days);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, existingCollateral);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bTokenUSDC), existingCollateral);
        bTokenUSDC.mint(existingCollateral);

        _setMockOracle();
        CachedValues memory cachedValues = CachedValues({
            poolId: 25,
            positionId: 1,
            lpToken: lpToken,
            initialRewardPerShare: 0,
            pool: pool,
            timestamp: timestamp,
            initialDebtValue: 0,
            initialCollateral: collateralAmount,
            maxSharesRedeemed: 0
        });

        // Opening initial position with random values, skip when it fails as we don't test the open initial position
        if (!_openInitialPositionNoRevert(cachedValues.poolId, collateralAmount, borrowAmount)) return;

        // avoid stack-too-deep, calculating initial reward per token for crv rewards
        {
            ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

            (, , , address crvRewarder, , ) = cvxBooster.poolInfo(cachedValues.poolId);

            cachedValues.initialRewardPerShare = IRewarder(crvRewarder).rewardPerToken();
        }

        IBank.Position memory currentPosition = bank.getPositionInfo(cachedValues.positionId);

        IBasicSpell.ClosePosParam memory closePosParam = IBasicSpell.ClosePosParam({
            strategyId: 0,
            collToken: address(USDC),
            borrowToken: address(WETH),
            amountRepay: type(uint256).max,
            amountPosRemove: currentPosition.collateralSize,
            amountShareWithdraw: type(uint256).max, // use full shares
            amountOutMin: 0,
            amountToSwap: 0, // This computed after interest accrued during warp
            swapData: ""
        });

        {
            CachedBalances memory cachedBalances;
            // getting the rewards before the time passes
            (uint256[] memory rewardsBefore, address[] memory rewardTokensBefore) = _getRewards(cachedValues);
            cachedBalances.balanceOfUserRewardsBefore = new uint256[](rewardsBefore.length);
            cachedBalances.balanceOfTreasuryRewardsBefore = new uint256[](rewardsBefore.length);
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfUserRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i]).balanceOf(
                    owner
                );
            }

            address feeTreasury = bank.getFeeManager().getConfig().getTreasury();
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            // we move the timestamp
            vm.warp(block.timestamp + cachedValues.timestamp);

            // // Calculating max shares that can be redeemed from the money market
            cachedValues.maxSharesRedeemed = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();

            {
                uint256 debtAfter = _calculateDebtValue(
                    cachedValues.pool,
                    currentPosition.collateralSize,
                    cachedValues.positionId
                );

                // debt value is in borrow token so we need to normalize in collateral token
                uint256 debtValue = coreOracle.getTokenValue(address(WETH), debtAfter);
                uint256 collTokenPrice = coreOracle.getPrice(address(USDC));

                // Calculate how much we need to swap to cover the debt accrued by the borrowed funds
                closePosParam.amountToSwap = (debtValue * 1e18) / collTokenPrice;
                // If we need to swap more than initial collateral that was supplied, we need to increase the position.
                if (closePosParam.amountToSwap > cachedValues.initialCollateral) {
                    uint256 amountToIncrease = closePosParam.amountToSwap - cachedValues.initialCollateral;
                    amountToIncrease = amountToIncrease * 1.1e18; // we increase with 10% to cover the fees
                    _increasePosition(amountToIncrease, cachedValues.positionId);

                    currentPosition = bank.getPositionInfo(cachedValues.positionId);
                    cachedValues.initialCollateral += amountToIncrease;
                }
                bytes memory swapDataDebt = _getParaswapData(
                    address(USDC),
                    address(WETH),
                    closePosParam.amountToSwap,
                    address(convexSpell),
                    100
                );
                closePosParam.swapData = swapDataDebt;
            }
            // rewards should have been accrued
            (uint256[] memory rewards, address[] memory rewardTokens) = _getRewards(cachedValues);

            bytes[] memory swapDatas = new bytes[](rewards.length);
            IConvexSpell.ClosePositionFarmParam memory closePositionFarmParams = IConvexSpell.ClosePositionFarmParam({
                param: closePosParam,
                amounts: rewards,
                swapDatas: swapDatas
            });

            bytes memory data = abi.encodeCall(ConvexSpell.closePositionFarm, (closePositionFarmParams));

            // execute the spell, should yield the rewards in the owner's wallet
            bank.execute(cachedValues.positionId, address(convexSpell), data);

            // checking that the balances in the wallet are rewards - fees
            cachedBalances.balanceOfUserRewardsAfter = new uint256[](rewardTokens.length);
            cachedBalances.balanceOfTreasuryRewardsAfter = new uint256[](rewardTokens.length);
            for (uint256 i; i < rewardTokens.length; ++i) {
                cachedBalances.balanceOfUserRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokens[i]).balanceOf(owner);
            }

            // checking that the treasury balance was updated accordingly
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            assertEq(rewardsBefore.length, rewards.length, "Rewards length mismatch");
            for (uint i; i < rewardsBefore.length; ++i) {
                uint256 toRefund = rewards[i] - rewardsBefore[i];
                uint256 feeRate = bank.getFeeManager().getConfig().getRewardFee();
                uint256 cutFee = (toRefund * feeRate) / DENOMINATOR;
                assertApproxEqAbs(
                    toRefund - cutFee,
                    cachedBalances.balanceOfUserRewardsAfter[i] - cachedBalances.balanceOfUserRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the user"
                );

                assertApproxEqAbs(
                    cutFee,
                    cachedBalances.balanceOfTreasuryRewardsAfter[i] - cachedBalances.balanceOfTreasuryRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the treasury"
                );
            }
        }
        {
            // checking that the position closed and that the user is not in loss,
            // should accrue interest from the money market
            IBank.Position memory afterPosition = bank.getPositionInfo(cachedValues.positionId);

            assertEq(afterPosition.collateralSize, 0, "After position collateral size not cleared");
            assertEq(afterPosition.debtShare, 0, "After position debt share not cleared");
            // NOTE this fails as vault shares might still exists
            assertEq(afterPosition.underlyingVaultShare, 0, "After position underlying vault share not cleared");

            uint256 remainedSharesInMoneyMarket = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();
            assertEq(
                cachedValues.maxSharesRedeemed - currentPosition.underlyingVaultShare,
                remainedSharesInMoneyMarket
            );

            uint256 balanceOfCollateralAfter = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);
            uint256 balanceOfBorrowAfter = ERC20PresetMinterPauser(address(WETH)).balanceOf(owner);

            uint256 collateral = cachedValues.initialCollateral;

            collateral = _calculateFeesOnCollateral(collateral, false);

            uint256 debtValue = coreOracle.getTokenValue(address(USDC), closePosParam.amountToSwap);
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), balanceOfBorrowAfter);
            uint256 collValue = coreOracle.getTokenValue(address(USDC), balanceOfCollateralAfter);
            uint256 initialColValue = coreOracle.getTokenValue(address(USDC), collateral);

            assertGe(borrowValue + collValue, initialColValue - debtValue, "User in loss");
        }
    }

    function testForkFuzz_BankConvexSpell_closeRandomPositionSizeNoSwapOnRewardsWithCollateralInMoneyMarket(
        uint256 existingCollateral,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 closeShares,
        uint256 timestamp
    ) public {
        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address pool, , ) = curveOracle.getPoolInfo(lpToken);
        existingCollateral = bound(collateralAmount, 1e18, type(uint96).max - 1);

        collateralAmount = bound(collateralAmount, 1, type(uint96).max - 1);
        borrowAmount = bound(borrowAmount, 1, ICurvePool(pool).balances(0));
        timestamp = bound(timestamp, 1, 1 days);

        // adding underlying to the money market
        ERC20PresetMinterPauser(address(USDC)).mint(owner, existingCollateral);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bTokenUSDC), existingCollateral);
        bTokenUSDC.mint(existingCollateral);

        _setMockOracle();
        CachedValues memory cachedValues = CachedValues({
            poolId: 25,
            positionId: 1,
            lpToken: lpToken,
            initialRewardPerShare: 0,
            pool: pool,
            timestamp: timestamp,
            initialDebtValue: 0,
            initialCollateral: collateralAmount,
            maxSharesRedeemed: 0
        });

        // Opening initial position with random values, skip when it fails as we don't test the open initial position
        if (!_openInitialPositionNoRevert(cachedValues.poolId, collateralAmount, borrowAmount)) return;

        // avoid stack-too-deep, calculating initial reward per token for crv rewards
        {
            ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

            (, , , address crvRewarder, , ) = cvxBooster.poolInfo(cachedValues.poolId);

            cachedValues.initialRewardPerShare = IRewarder(crvRewarder).rewardPerToken();
        }

        IBank.Position memory currentPosition = bank.getPositionInfo(cachedValues.positionId);

        // we bound the shares to 10% of the position and 100%
        bound(
            closeShares,
            (currentPosition.underlyingVaultShare * 0.1e18) / 1e18,
            currentPosition.underlyingVaultShare
        );

        IBasicSpell.ClosePosParam memory closePosParam = IBasicSpell.ClosePosParam({
            strategyId: 0,
            collToken: address(USDC),
            borrowToken: address(WETH),
            amountRepay: type(uint256).max,
            amountPosRemove: currentPosition.collateralSize,
            amountShareWithdraw: closeShares, // use fuzzed value
            amountOutMin: 0,
            amountToSwap: 0, // This computed after interest accrued during warp
            swapData: ""
        });

        {
            CachedBalances memory cachedBalances;
            // getting the rewards before the time passes
            (uint256[] memory rewardsBefore, address[] memory rewardTokensBefore) = _getRewards(cachedValues);
            cachedBalances.balanceOfUserRewardsBefore = new uint256[](rewardsBefore.length);
            cachedBalances.balanceOfTreasuryRewardsBefore = new uint256[](rewardsBefore.length);
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfUserRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i]).balanceOf(
                    owner
                );
            }

            address feeTreasury = bank.getFeeManager().getConfig().getTreasury();
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsBefore[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            // we move the timestamp
            vm.warp(block.timestamp + cachedValues.timestamp);

            // Storing the initial shares in the money market to compare at the final
            cachedValues.maxSharesRedeemed = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();

            {
                uint256 debtAfter = _calculateDebtValue(
                    cachedValues.pool,
                    currentPosition.collateralSize,
                    cachedValues.positionId
                );

                // debt value is in borrow token so we need to normalize in collateral token
                uint256 debtValue = coreOracle.getTokenValue(address(WETH), debtAfter);
                uint256 collTokenPrice = coreOracle.getPrice(address(USDC));

                // Calculate how much we need to swap to cover the debt accrued by the borrowed funds
                closePosParam.amountToSwap = (debtValue * 1e18) / collTokenPrice;
                // closePosParam.amountToSwap = 0;

                // If we need to swap more than initial collateral that was supplied, we need to increase the position.
                if (closePosParam.amountToSwap > cachedValues.initialCollateral) {
                    uint256 amountToIncrease = closePosParam.amountToSwap - cachedValues.initialCollateral;
                    amountToIncrease = amountToIncrease * 1.1e18; // we increase with 10% to cover the fees
                    _increasePosition(amountToIncrease, cachedValues.positionId);

                    currentPosition = bank.getPositionInfo(cachedValues.positionId);
                    cachedValues.maxSharesRedeemed = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();

                    cachedValues.initialCollateral += amountToIncrease;
                }
                bytes memory swapDataDebt = _getParaswapData(
                    address(USDC),
                    address(WETH),
                    closePosParam.amountToSwap,
                    address(convexSpell),
                    100
                );
                closePosParam.swapData = swapDataDebt;
            }
            // rewards should have been accrued
            (uint256[] memory rewards, address[] memory rewardTokens) = _getRewards(cachedValues);

            bytes[] memory swapDatas = new bytes[](rewards.length);
            IConvexSpell.ClosePositionFarmParam memory closePositionFarmParams = IConvexSpell.ClosePositionFarmParam({
                param: closePosParam,
                amounts: rewards,
                swapDatas: swapDatas
            });

            bytes memory data = abi.encodeCall(ConvexSpell.closePositionFarm, (closePositionFarmParams));

            // execute the spell, should yield the rewards in the owner's wallet
            bank.execute(cachedValues.positionId, address(convexSpell), data);

            // checking that the balances in the wallet are rewards - fees
            cachedBalances.balanceOfUserRewardsAfter = new uint256[](rewardTokens.length);
            cachedBalances.balanceOfTreasuryRewardsAfter = new uint256[](rewardTokens.length);
            for (uint256 i; i < rewardTokens.length; ++i) {
                cachedBalances.balanceOfUserRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokens[i]).balanceOf(owner);
            }

            // checking that the treasury balance was updated accordingly
            for (uint256 i; i < rewardsBefore.length; ++i) {
                cachedBalances.balanceOfTreasuryRewardsAfter[i] = ERC20PresetMinterPauser(rewardTokensBefore[i])
                    .balanceOf(feeTreasury);
            }

            assertEq(rewardsBefore.length, rewards.length, "Rewards length mismatch");
            for (uint i; i < rewardsBefore.length; ++i) {
                uint256 toRefund = rewards[i] - rewardsBefore[i];
                uint256 feeRate = bank.getFeeManager().getConfig().getRewardFee();
                uint256 cutFee = (toRefund * feeRate) / DENOMINATOR;
                assertApproxEqAbs(
                    toRefund - cutFee,
                    cachedBalances.balanceOfUserRewardsAfter[i] - cachedBalances.balanceOfUserRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the user"
                );

                assertApproxEqAbs(
                    cutFee,
                    cachedBalances.balanceOfTreasuryRewardsAfter[i] - cachedBalances.balanceOfTreasuryRewardsBefore[i],
                    1,
                    "Rewards balance mismatch for the treasury"
                );
            }
        }
        {
            // checking that the position closed and that the user is not in loss,
            // should accrue interest from the money market
            IBank.Position memory afterPosition = bank.getPositionInfo(cachedValues.positionId);
            currentPosition.underlyingVaultShare;
            assertEq(afterPosition.collateralSize, 0, "After position collateral size not cleared");
            assertEq(afterPosition.debtShare, 0, "After position debt share not cleared");

            // making sure the remaining shares in the position matches the initial value - removed
            assertEq(
                afterPosition.underlyingVaultShare,
                currentPosition.underlyingVaultShare - closeShares,
                "After position underlying vault share mismatch"
            );

            uint256 remainedSharesInMoneyMarket = (bTokenUSDC.getCash() * 1e18) / bTokenUSDC.exchangeRateCurrent();

            // we need to make sure the shares are removed correctly from the market, we let 1000 for rounding issues.
            // Might need to be extra reviewed.
            assertApproxEqAbs(
                cachedValues.maxSharesRedeemed - remainedSharesInMoneyMarket,
                closeShares,
                1000,
                "Shares removed from the Money Market mismatch"
            );
        }
    }

    function _validatePositionSize(
        uint256 lpTokenAmount,
        address lpToken,
        uint256 maxPositionSize,
        uint256 positionId
    ) internal view override returns (bool, IBank.Position memory) {
        uint256 lpBalance = lpTokenAmount;
        uint256 lpPrice = coreOracle.getPrice(lpToken);
        uint256 addedPosSize = (lpPrice * lpBalance) / 10 ** IERC20Metadata(lpToken).decimals();
        IBank.Position memory currentPosition = bank.getPositionInfo(positionId);

        uint256 currentPositionColValue;
        // positionId == 0 might mean new position
        if (positionId != 0)
            currentPositionColValue = coreOracle.getWrappedTokenValue(
                currentPosition.collToken,
                currentPosition.collId,
                currentPosition.collateralSize
            );

        return (currentPositionColValue + addedPosSize <= maxPositionSize, currentPosition);
    }

    function _validateReceivedBorrowAndPosition(
        IBank.Position memory previousPosition,
        uint256 positionId,
        uint256 amount
    ) internal override {
        if (positionId == 0) positionId++; // NOTE position == 0 means new position
        IBank.Position memory currentPosition = bank.getPositionInfo(positionId);
        assertApproxEqRel(
            currentPosition.collateralSize,
            previousPosition.collateralSize + amount,
            0.1e18, // NOTE investigate this mismatch
            "Position collateral size mismatch"
        );
        assertEq(
            IERC1155(address(wConvexBooster)).balanceOf(address(bank), currentPosition.collId),
            currentPosition.collateralSize,
            "Borrowed Amount not received"
        );
    }

    function _openInitialPosition(uint256 poolId, uint256 collateralAmount, uint256 borrowAmount) internal {
        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(poolId);
        vm.label(lpToken, "lpToken");
        (address pool, , ) = curveOracle.getPoolInfo(lpToken);

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);

        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: poolId
        });

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount, true);

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 0));
        // Used to make sure the right amount of LP landed at destination
        uint256 balanceBeforeLP = _getLpBalance(poolId, lpToken);
        bank.execute(0, address(convexSpell), data);
        uint256 balanceAfterLP = _getLpBalance(poolId, lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertApproxEqRel(balanceAfterLP - balanceBeforeLP, slippage, 0.000001e18);
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0);
    }

    function _openInitialPositionNoRevert(
        uint256 poolId,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) internal returns (bool) {
        (address lpToken, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(poolId);
        vm.label(lpToken, "lpToken");

        ERC20PresetMinterPauser(address(USDC)).mint(owner, collateralAmount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), collateralAmount);

        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: collateralAmount,
            borrowToken: address(WETH),
            borrowAmount: borrowAmount,
            farmingPoolId: poolId
        });

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 0));
        try bank.execute(0, address(convexSpell), data) {} catch (bytes memory) {
            return false;
        }

        return true;
    }

    function _calculateSlippageCurve(address pool, uint256 amount, bool deposit) internal view returns (uint256) {
        uint256[2] memory suppliedAmts;
        suppliedAmts[0] = amount;
        uint256 slippage = ICurvePool(pool).calc_token_amount(suppliedAmts, deposit);
        slippage -= (slippage * CURVE_FEE) / CURVE_FEE_DENOMINATOR;
        return slippage;
    }

    function _calculateSlippage(uint256 amount, uint256 slippagePercentage) internal pure override returns (uint256) {
        return (amount * (DENOMINATOR - slippagePercentage)) / DENOMINATOR;
    }

    function _calcWithdrawAmountFromCurve(address pool, uint256 amount) internal view returns (uint256) {
        uint256 slippage = ICurvePool(pool).calc_withdraw_one_coin(amount, 0);
        return slippage;
    }

    // The lp token lands in the reward_contract of the gauge for that poolId of the cvxBooster
    function _getLpBalance(uint256 poolId, address lpToken) internal returns (uint256) {
        ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

        (address targetLpToken, , address gauge, , , ) = cvxBooster.poolInfo(poolId);
        assertEq(targetLpToken, lpToken); // Check if the right LP Token booster was chosen
        return ERC20PresetMinterPauser(lpToken).balanceOf(ILiquidityGauge(gauge).reward_contract());
    }

    function _getRewards(CachedValues memory cachedValues) internal returns (uint256[] memory, address[] memory) {
        CachedValues memory _cachedValues = cachedValues; // avoiding stack too deep
        ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

        (, , , address crvRewarder, , ) = cvxBooster.poolInfo(_cachedValues.poolId);
        uint256 extraRewardsLength = wConvexBooster.extraRewardsLength(_cachedValues.poolId);

        address[] memory tokens = new address[](extraRewardsLength + 2);
        uint256[] memory rewards = new uint256[](extraRewardsLength + 2);

        tokens[0] = IRewarder(crvRewarder).rewardToken();
        tokens[1] = CVX;

        uint256 currentRewardPerShare = IRewarder(crvRewarder).rewardPerToken();
        IBank.Position memory currentPosition = bank.getPositionInfo(1);

        // Calculate CRV Reward
        rewards[0] = _getPendingReward(
            currentRewardPerShare,
            _cachedValues.initialRewardPerShare,
            currentPosition.collateralSize,
            ERC20PresetMinterPauser(_cachedValues.lpToken).decimals()
        );

        // Calculate CVX Reward
        rewards[1] = _calcAllocatedCVX(_cachedValues, crvRewarder, currentPosition.collateralSize);

        // Setting the rewards per each
        for (uint256 i; i < extraRewardsLength; ++i) {
            address rewarder = wConvexBooster.getExtraRewarder(_cachedValues.poolId, i);
            uint256 stRewardPerShare = wConvexBooster.getInitialTokenPerShare(currentPosition.collId, rewarder);
            tokens[i + 2] = IRewarder(rewarder).rewardToken();

            if (stRewardPerShare == 0) {
                rewards[i + 2] = 0;
            } else {
                rewards[i + 2] = _getPendingReward(
                    IRewarder(rewarder).rewardPerToken(),
                    stRewardPerShare == type(uint256).max ? 0 : stRewardPerShare,
                    currentPosition.collateralSize,
                    ERC20PresetMinterPauser(_cachedValues.lpToken).decimals()
                );
            }
        }
        return (rewards, tokens);
    }

    function _calcAllocatedCVX(
        CachedValues memory cachedValues,
        address crvRewarder,
        uint256 collateralSize
    ) internal returns (uint256) {
        address escrow = wConvexBooster.getEscrow(cachedValues.poolId);

        uint256 currentDeposits = IRewarder(crvRewarder).balanceOf(address(escrow));
        if (currentDeposits == 0) {
            return 0;
        }

        // As the wConvexBooster does not have all the private variables exposed
        // we had to create a mock that exposes some functions
        WConvexBoosterMock mockBooster = WConvexBoosterMock(address(wConvexBooster));

        // We had to simulate a state change on the staking reward on CRV to get the CVX rewards
        (uint256 cvxPerShareByPid, uint256 lastCrvPerToken) = _getUpdatedCvxReward(cachedValues);
        uint256 cvxPerShare = cvxPerShareByPid -
            mockBooster.cvxPerShareDebt(
                wConvexBooster.encodeId(cachedValues.poolId, cachedValues.initialRewardPerShare)
            );

        uint256 lpDecimals = ERC20PresetMinterPauser(cachedValues.lpToken).decimals();

        // Calculating pending CVX rewards
        uint256 earned = _getPendingReward(lastCrvPerToken, lastCrvPerToken, currentDeposits, lpDecimals);

        if (earned != 0) {
            uint256 cvxReward = mockBooster.getCvxPendingReward(earned);
            cvxPerShare += (cvxReward * PRICE_PRECISION) / currentDeposits;
        }

        return (cvxPerShare * collateralSize) / PRICE_PRECISION;
    }

    function _getUpdatedCvxReward(CachedValues memory cachedValues) internal returns (uint256, uint256) {
        IConvex cvxToken = IConvex(CVX);
        address escrow = wConvexBooster.getEscrow(cachedValues.poolId);

        (, , , address crvRewarder, , ) = wConvexBooster.getPoolInfoFromPoolId(cachedValues.poolId);
        uint256 currentDeposits = IRewarder(crvRewarder).balanceOf(escrow);

        if (currentDeposits == 0) return (0, 0);

        uint256 cvxBalBefore = cvxToken.balanceOf(escrow);

        // CVX is cliffed so we apply the cliff algorithm of Curve
        uint256 earnedReward = WConvexBoosterMock(address(wConvexBooster)).getCvxPendingReward(
            IRewarder(crvRewarder).earned(escrow)
        );
        return (
            ((earnedReward - cvxBalBefore) * PRICE_PRECISION) / currentDeposits,
            IRewarder(crvRewarder).rewardPerToken()
        );
    }

    function _getPendingReward(
        uint256 enRewardPerShare,
        uint256 stRewardPerShare,
        uint256 amount,
        uint256 lpDecimals
    ) internal pure returns (uint256 rewards) {
        uint256 share = enRewardPerShare > stRewardPerShare ? enRewardPerShare - stRewardPerShare : 0;
        rewards = (share * amount) / (10 ** lpDecimals);
    }

    // Checking that the token id contains the initial crvRewardPerToken encoded correctly
    function _checkTokenIdEncoding(uint256 poolId, uint256 positionId) internal {
        if (positionId == 0) positionId++;
        ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

        (, , , address cvxRewarder, , ) = cvxBooster.poolInfo(poolId);
        uint256 crvRewardPerToken = IRewarder(cvxRewarder).rewardPerToken();
        uint256 id = wConvexBooster.encodeId(poolId, crvRewardPerToken);
        IBank.Position memory currentPosition = bank.getPositionInfo(positionId);
        assertEq(id, currentPosition.collId, "Collateral ID isn't the same");

        IRewarder(cvxRewarder).rewardPerToken();
    }

    function _applyFeesOnRewards(uint256[] memory rewards) internal view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory rewardFees = new uint256[](rewards.length);
        for (uint256 i; i < rewards.length; i++) {
            uint256 toRefund = rewards[i];
            uint256 feeRate = bank.getFeeManager().getConfig().getRewardFee();
            uint256 cutFee = (toRefund * feeRate) / DENOMINATOR;
            rewardFees[i] = cutFee;
            rewards[i] = toRefund - cutFee;
        }

        return (rewards, rewardFees);
    }

    function _calculateDebtValue(address pool, uint256 collSize, uint256 positionId) internal returns (uint256) {
        uint256 positionDebt = bank.currentPositionDebt(positionId);
        uint256 removedFromCurve = _calcWithdrawAmountFromCurve(pool, collSize);

        uint256 underlyingValue = coreOracle.getPrice(address(USDC));

        // If the debt is lower than what we had in curve then something is wrong
        assertGe(positionDebt, removedFromCurve, "Position did not accumulate debt");
        // 1e12 cause diff between the tokens decimals is 1e12
        uint256 diff = ((positionDebt - removedFromCurve) * 1e12) / underlyingValue;

        return diff;
    }

    function _increasePosition(uint256 amount, uint256 positionId) internal {
        ERC20PresetMinterPauser(address(USDC)).mint(owner, amount);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), amount);
        bytes memory data = abi.encodeCall(BasicSpell.increasePosition, (address(USDC), amount));

        bank.execute(positionId, address(convexSpell), data);
    }

    function _calculateFeesOnCollateral(uint256 collateral, bool add) internal view returns (uint256) {
        uint256 feeRateDeposit = bank.getFeeManager().getConfig().getDepositFee();
        uint256 feeRateWithdraw = bank.getFeeManager().getConfig().getWithdrawFee();
        uint256 feeRateVaultWithdraw;

        if (
            block.timestamp <
            bank.getFeeManager().getConfig().getWithdrawVaultFeeWindowStartTime() +
                bank.getFeeManager().getConfig().getWithdrawVaultFeeWindow()
        ) {
            feeRateVaultWithdraw = bank.getFeeManager().getConfig().getWithdrawVaultFee();
        }
        if (!add) {
            uint256 cutFeeDeposit = (collateral * feeRateDeposit) / DENOMINATOR;
            collateral -= cutFeeDeposit;

            uint256 cutFeeVaultWithdraw = (collateral * feeRateVaultWithdraw) / DENOMINATOR;
            collateral -= cutFeeVaultWithdraw;

            uint256 cutFeeWithdraw = (collateral * feeRateWithdraw) / DENOMINATOR;
            collateral -= cutFeeWithdraw;
        } else {
            collateral += collateral - (collateral * (DENOMINATOR - feeRateWithdraw)) / DENOMINATOR;
            if (feeRateVaultWithdraw != 0) {
                collateral += collateral - (collateral * (DENOMINATOR - feeRateVaultWithdraw)) / DENOMINATOR;
            }
            collateral += collateral - (collateral * (DENOMINATOR - feeRateDeposit)) / DENOMINATOR;
        }
        return collateral;
    }

    // TODO maybe take these values from the deployments repo?
    function _assignDeployedContracts() internal override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        _intConvexSpell = new ConvexSpell();
        // Convex Stable Proxy address Mainnet
        convexSpell = ConvexSpell(payable(0x936F8e31717c4998804f85889DE758C4780702A4));
        vm.etch(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4, address(_intConvexSpell).code);

        vm.label(address(convexSpell), "convexSpell");
        vm.label(address(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4), "convexSpellImpl");
        vm.label(address(wConvexBooster), "wConvexBooster");
        vm.label(CVX, "CVX");

        coreOracle = bank.getOracle();
        vm.label(address(coreOracle), "coreOracle");

        _intSoftVault = new SoftVault();
        vm.etch(address(softVaultUSDC), address(_intSoftVault).code);
        vm.etch(address(softVaultWETH), address(_intSoftVault).code);
    }

    function _setMockOracle() internal override {
        mockOracle = new MockOracle();
        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(WETH);
        tokens[2] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        tokens[3] = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // ETH
        uint256[] memory prices = new uint256[](4);
        prices[0] = 999789970000000000;
        prices[1] = 4031670000000000000000;
        prices[2] = 4033364706470000000000;
        prices[3] = 4031670000000000000000;
        mockOracle.setPrice(tokens, prices);
        vm.startPrank(IOwnable(address(coreOracle)).owner());
        address[] memory oracles = new address[](4);
        oracles[0] = address(mockOracle);
        oracles[1] = address(mockOracle);
        oracles[2] = address(mockOracle);
        oracles[3] = address(mockOracle);
        IExtCoreOracle(address(coreOracle)).setRoutes(tokens, oracles);
        vm.stopPrank();
    }
}
