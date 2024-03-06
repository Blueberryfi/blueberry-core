// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank, console2, ERC20PresetMinterPauser } from "@test/BaseTest.t.sol";
import { SpellBaseTest, IBank } from "@test/fork/spell/SpellBaseTest.t.sol";
import { IOwnable } from "@test/interfaces/IOwnable.sol";
import { ConvexSpell } from "@contracts/spell/ConvexSpell.sol";
import { IBasicSpell } from "@contracts/interfaces/spell/IBasicSpell.sol";
import { IWConvexBooster } from "@contracts/interfaces/IWConvexBooster.sol";
import { ICurveOracle } from "@contracts/interfaces/ICurveOracle.sol";
import { ICoreOracle } from "@contracts/interfaces/ICoreOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import { ICurvePool } from "@test/interfaces/ICurvePool.sol";
import { ICvxBooster } from "@test/interfaces/ICvxBooster.sol";
import { ILiquidityGauge } from "@test/interfaces/ILiquidityGauge.sol";
import { DENOMINATOR } from "@contracts/utils/BlueberryConst.sol";

contract BankConvexSpell is SpellBaseTest {
    ConvexSpell public convexSpell;

    IWConvexBooster public wConvexBooster;
    ICurveOracle public curveOracle;
    ICoreOracle public coreOracle;
    ConvexSpell internal _intConvexSpell; // Needed for vm.etch => debug inside the contracts

    address public spellOwner;
    uint256 public CURVE_FEE = 505800; // 0.005058 % approximation
    uint256 public CURVE_FEE_DENOMINATOR = 10_000_000_000; // 100%

    function setUp() public override {
        super.setUp();

        _assignDeployedContracts();

        _enableBToken(bTokenWETH);

        spellOwner = IOwnable(address(convexSpell)).owner();

        wConvexBooster = convexSpell.getWConvexBooster();
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
        IBasicSpell.Strategy memory strat = convexSpell.getStrategy(0);

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount);

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 0));
        uint256 balanceBefore = _getLpBalance(poolId, lpToken); // Used to make sure the right amount of LP landed at destination
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
        borrowAmount = bound(borrowAmount, 1, ICurvePool(p).balances(0)); // limiting to curve pool's balance, NOTE should try test with increasing the POOL
        slippagePercent = bound(slippagePercent, 10 /* 0.1% */, 500 /* 5% */);

        // avoid stack-too-deep
        {
            uint256 borrowValue = coreOracle.getTokenValue(address(WETH), borrowAmount);
            uint256 icollValue = coreOracle.getTokenValue(USDC, collateralAmount);
            uint256 maxLTV = convexSpell.getMaxLTV(0, USDC);
            console2.log("Br i m", borrowValue, icollValue, maxLTV);
            console2.log("col am", collateralAmount);
            console2.log("borrowAmount am", borrowAmount);
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

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount); // calculate the lp token received by curve
        slippage = _calculateSlippage(slippage, slippagePercent); // add the slippage
        (bool valid, IBank.Position memory previousPosition) = _validatePositionSize(
            slippage,
            lpToken,
            strategy.maxPositionSize,
            positionId
        );
        if (!valid) return; // making sure it validates the position min/max size

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, slippage));
        uint256 balanceBeforeLP = _getLpBalance(poolId, lpToken); // Used to make sure the right amount of LP landed at destination

        bank.execute(positionId, address(convexSpell), data);

        // Validate that the position was updated correctly
        // _validateReceivedBorrowAndPosition(previousPosition, positionId, slippage);

        uint256 balanceAfterLP = _getLpBalance(poolId, lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertGe(balanceAfterLP - balanceBeforeLP, slippage, "LP landed in reward contract mismatch");
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0, "Remaining USDC in the initiator");
    }

    function testForkFuzz_BankConvexSpell_openExistingPositionGeneratesRightLPToken(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 slippagePercent
    ) public {
        (address lpt, , , , , ) = wConvexBooster.getPoolInfoFromPoolId(25);
        (address p, , ) = curveOracle.getPoolInfo(lpt);
        collateralAmount = bound(collateralAmount, 1, type(uint128).max - 1);
        borrowAmount = bound(borrowAmount, 1, ICurvePool(p).balances(0)); // limiting to curve pool's balance, NOTE should try test with increasing the POOL
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

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount); // calculate the lp token received by curve
        slippage = _calculateSlippage(slippage, slippagePercent); // add the slippage
        (bool valid, IBank.Position memory previousPosition) = _validatePositionSize(
            slippage,
            lpToken,
            strategy.maxPositionSize,
            positionId
        );
        if (!valid) return; // making sure it validates the position min/max size

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, slippage));
        uint256 balanceBeforeLP = _getLpBalance(poolId, lpToken); // Used to make sure the right amount of LP landed at destination

        bank.execute(positionId, address(convexSpell), data);

        // Validate that the position was updated correctly
        _validateReceivedBorrowAndPosition(previousPosition, positionId, slippage);

        uint256 balanceAfterLP = _getLpBalance(poolId, lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertGe(balanceAfterLP - balanceBeforeLP, slippage, "LP landed in reward contract mismatch");
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0, "Remaining USDC in the initiator");
    }

    function testConcreteValue() external {
        testForkFuzz_BankConvexSpell_openNewPositionGeneratesRightLPToken(1, 1, 10);
    }

    function _validatePositionSize(
        uint256 lpTokenAmount,
        address lpToken,
        uint256 maxPositionSize,
        uint256 positionId
    ) internal view override returns (bool, IBank.Position memory) {
        IBank.Position memory currentPosition = bank.getPositionInfo(positionId);

        uint256 lpBalance = lpTokenAmount;
        uint256 lpPrice = coreOracle.getPrice(lpToken);
        uint256 addedPosSize = (lpPrice * lpBalance) / 10 ** IERC20Metadata(lpToken).decimals();

        uint256 currentPositionColValue;
        // positionId might mean new position
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

        uint256 slippage = _calculateSlippageCurve(pool, borrowAmount);

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 0));
        uint256 balanceBeforeLP = _getLpBalance(poolId, lpToken); // Used to make sure the right amount of LP landed at destination
        bank.execute(0, address(convexSpell), data);
        uint256 balanceAfterLP = _getLpBalance(poolId, lpToken);
        uint256 balanceAfterUSDC = ERC20PresetMinterPauser(address(USDC)).balanceOf(owner);

        // Check if the right amount of LP landed at destination
        assertApproxEqRel(balanceAfterLP - balanceBeforeLP, slippage, 0.000001e18);
        // Making sure USDC was taken
        assertEq(balanceAfterUSDC, 0);
    }

    function _calculateSlippageCurve(address pool, uint256 amount) internal view returns (uint256) {
        uint256[2] memory suppliedAmts;
        suppliedAmts[0] = amount;
        console2.log("pool ", pool);
        uint256 slippage = ICurvePool(pool).calc_token_amount(suppliedAmts, true);
        slippage -= (slippage * CURVE_FEE) / CURVE_FEE_DENOMINATOR;
        return slippage;
    }

    function _calculateSlippage(uint256 amount, uint256 slippagePercentage) internal pure override returns (uint256) {
        return (amount * (DENOMINATOR - slippagePercentage)) / DENOMINATOR;
    }

    // The lp token lands in the reward_contract of the gauge for that poolId of the cvxBooster
    function _getLpBalance(uint256 poolId, address lpToken) internal returns (uint256) {
        ICvxBooster cvxBooster = ICvxBooster(address(wConvexBooster.getCvxBooster())); // modified interface cast

        (address targetLpToken, , address gauge, , , ) = cvxBooster.poolInfo(poolId);

        assertEq(targetLpToken, lpToken); // Check if the right LP Token booster was chosen
        return ERC20PresetMinterPauser(lpToken).balanceOf(ILiquidityGauge(gauge).reward_contract());
    }

    // TODO maybe take these values from the deployments repo?
    function _assignDeployedContracts() internal override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        _intConvexSpell = new ConvexSpell();

        convexSpell = ConvexSpell(payable(0x936F8e31717c4998804f85889DE758C4780702A4)); // Convex Stable Proxy address Mainnet
        vm.etch(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4, address(_intConvexSpell).code);

        vm.label(address(convexSpell), "convexSpell");
        vm.label(address(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4), "convexSpellImpl");
        vm.label(address(wConvexBooster), "wConvexBooster");

        coreOracle = bank.getOracle();
        vm.label(address(coreOracle), "coreOracle");
    }
}
