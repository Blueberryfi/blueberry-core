// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */
/* solhint-disable no-console */

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { SpellBaseTest } from "@test/fork/spell/SpellBaseTest.t.sol";
import { IOwnable } from "@test/interfaces/IOwnable.sol";
import { ShortLongSpell } from "@contracts/spell/ShortLongSpell.sol";
import { ICoreOracle } from "@contracts/interfaces/ICoreOracle.sol";
import { IBasicSpell } from "@contracts/interfaces/spell/IBasicSpell.sol";
import { IExtBErc20 } from "@test/interfaces/IExtBErc20.sol";
import { IBank } from "@contracts/interfaces/IBank.sol";
import "@contracts/utils/BlueberryConst.sol" as Constants;
import { ShortLongStrategies, ShortLongStrategy } from "@test/fork/spell/ShortLongStrategies.t.sol";
import { ParaSwapSnapshot } from "@test/fork/ParaSwapSnapshot.t.sol";
import { Quoter } from "@test/Quoter.t.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { MockOracle } from "@contracts/mock/MockOracle.sol";
import { IExtCoreOracle } from "@test/interfaces/IExtCoreOracle.sol";

contract BankShortLongTest is SpellBaseTest, ShortLongStrategies, ParaSwapSnapshot, Quoter {
    ShortLongSpell public shortLongSpell;
    ICoreOracle public coreOracle;
    MockOracle public mockOracle;

    address public constant SHORT_LONG_SPELL_PROXY = 0x55d206c1A11F4b2f60459e88B5c601A4E1Cd41a5;
    address public constant SHORT_LONG_SPELL_IMPLEMENTATION = 0x6304029C11589f3754d0E9640536949fD41a1519;

    uint256 public constant WSTETH_STRATEGY_ID = 4;

    address public spellOwner;

    struct Vars {
        uint256 strategyId;
        address collToken;
        uint256 collAmount;
        address borrowToken;
        uint256 borrowAmount;
        uint256 farmingPoolId;
        address swapToken;
        uint256 maxImpact;
        uint256 balance;
    }

    function setUp() public override {
        super.setUp();

        _assignDeployedContracts();

        _enableBToken(IExtBErc20(BDAI));
        _enableBToken(IExtBErc20(BWBTC));

        spellOwner = IOwnable(address(shortLongSpell)).owner();
    }

    function testForkFuzz_BankShortLong_openPosition_closePosition(uint256 swapTokenMultiplier) external {
        swapTokenMultiplier = bound(swapTokenMultiplier, 0.2e18, 2e18);
        Vars memory vars = Vars({
            strategyId: WSTETH_STRATEGY_ID,
            collToken: WBTC,
            collAmount: 0.4e8,
            borrowToken: DAI,
            borrowAmount: 5000e18,
            farmingPoolId: 0,
            swapToken: WSTETH,
            maxImpact: 100,
            balance: 0
        });

        IBasicSpell.Strategy memory strategy = shortLongSpell.getStrategy(vars.strategyId);

        deal(vars.collToken, owner, vars.collAmount);
        ERC20PresetMinterPauser(vars.collToken).approve(address(bank), vars.collAmount);

        IBasicSpell.OpenPosParam memory openPositionParam = IBasicSpell.OpenPosParam({
            strategyId: vars.strategyId,
            collToken: vars.collToken,
            collAmount: vars.collAmount,
            borrowToken: vars.borrowToken,
            borrowAmount: vars.borrowAmount,
            farmingPoolId: vars.farmingPoolId
        });

        bytes memory swapData = _getParaswapData(
            vars.borrowToken,
            vars.swapToken,
            vars.borrowAmount,
            address(shortLongSpell),
            vars.maxImpact
        );

        bytes memory data = abi.encodeCall(ShortLongSpell.openPosition, (openPositionParam, swapData));
        uint256 positionId = 0;
        positionId = bank.execute(positionId, address(shortLongSpell), data);
        vars.balance = bank.getPositionValue(positionId);
        emit log_uint(vars.balance);

        assertGt(positionId, 0, "New position created");
        _validatePosSize(positionId, vars.strategyId);
        _validateLTV(positionId, vars.strategyId);

        IBank.Position memory position = bank.getPositionInfo(positionId);

        uint256 swapAmount = quote(
            address(shortLongSpell.getWrappedERC20()),
            strategy.vault,
            abi.encodeCall(SoftVault.withdraw, position.collateralSize)
        );

        swapData = _getParaswapData(
            vars.swapToken,
            vars.borrowToken,
            swapAmount,
            address(shortLongSpell),
            vars.maxImpact
        );

        uint256 colTokenSwapAmount = vars.collAmount / 2;
        bytes memory colTokenSwapData = _getParaswapData(
            vars.collToken,
            vars.borrowToken,
            colTokenSwapAmount,
            address(shortLongSpell),
            vars.maxImpact
        );

        IBasicSpell.ClosePosParam memory closePositionParam = IBasicSpell.ClosePosParam({
            strategyId: vars.strategyId,
            collToken: vars.collToken,
            borrowToken: vars.borrowToken,
            amountRepay: type(uint256).max,
            amountPosRemove: type(uint256).max,
            amountShareWithdraw: type(uint256).max,
            amountOutMin: 1,
            amountToSwap: colTokenSwapAmount,
            swapData: colTokenSwapData
        });

        data = abi.encodeCall(ShortLongSpell.closePosition, (closePositionParam, swapData));

        _setPriceMultiplier(vars.swapToken, swapTokenMultiplier);
        if (swapTokenMultiplier > 1.1e18) {
            assertGt(bank.getPositionValue(positionId), vars.balance, "Position increased in value");
        }
        if (swapTokenMultiplier <= 1e18) {
            assertLt(
                bank.getPositionValue(positionId),
                vars.balance,
                "Position decreased increased in value (fees or negative price change)"
            );
        }

        bank.execute(positionId, address(shortLongSpell), data);

        _validatePosIsClosed(positionId);
    }

    function testForkFuzz_BankShortLong_openPosition(uint256 collAmount, uint256 borrowAmount) external {
        uint256 strategyId = WSTETH_STRATEGY_ID;
        IBasicSpell.Strategy memory strategy = shortLongSpell.getStrategy(strategyId);

        address collToken = WBTC;
        collAmount = bound(collAmount, 0.1e8, 15e8);
        address borrowToken = DAI;
        borrowAmount = bound(borrowAmount, strategy.minPositionSize / 2, 2 * strategy.maxPositionSize);
        uint256 farmingPoolId = 0;
        address swapToken = WSTETH;
        uint256 maxImpact = 100;

        deal(collToken, owner, collAmount);
        ERC20PresetMinterPauser(collToken).approve(address(bank), collAmount);

        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: strategyId,
            collToken: collToken,
            collAmount: collAmount,
            borrowToken: borrowToken,
            borrowAmount: borrowAmount,
            farmingPoolId: farmingPoolId
        });

        bytes memory swapData = _getParaswapData(
            borrowToken,
            swapToken,
            borrowAmount,
            address(shortLongSpell),
            maxImpact
        );

        bytes memory data = abi.encodeCall(ShortLongSpell.openPosition, (param, swapData));
        try bank.execute(0, address(shortLongSpell), data) returns (uint256 positionId) {
            _validatePosSize(positionId, strategyId);
            _validateLTV(positionId, strategyId);
        } catch {}
    }

    function testForkFuzz_BankShortLong_openPosition_multiple_strategies(
        uint256 shortLongStrategyIndex,
        uint256 collTokenIndex,
        uint256 borrowTokenIndex,
        uint256 collAmount,
        uint256 borrowAmount
    ) external {
        shortLongStrategyIndex = bound(shortLongStrategyIndex, 0, strategies.length - 1);
        ShortLongStrategy memory shortLongStrategy = strategies[shortLongStrategyIndex];
        collTokenIndex = bound(collTokenIndex, 0, shortLongStrategy.collTokens.length - 1);
        borrowTokenIndex = bound(borrowTokenIndex, 0, shortLongStrategy.borrowAssets.length - 1);
        uint256 strategyId = shortLongStrategy.strategyId;
        IBasicSpell.Strategy memory strategy = shortLongSpell.getStrategy(strategyId);

        address collToken = shortLongStrategy.collTokens[collTokenIndex];
        uint8 collDecimals = ERC20PresetMinterPauser(collToken).decimals();
        collAmount = bound(collAmount, 10 ** collDecimals / 10, 10 * 10 ** collDecimals);
        address borrowToken = shortLongStrategy.borrowAssets[borrowTokenIndex];
        borrowAmount = bound(borrowAmount, strategy.minPositionSize / 2, 2 * strategy.maxPositionSize);
        uint256 farmingPoolId = 0;
        address swapToken = shortLongStrategy.softVaultUnderlying;
        uint256 maxImpact = 100;

        if (collToken == USDC) {
            _configureMinter();
            ERC20PresetMinterPauser(collToken).mint(owner, collAmount);
        } else {
            deal(collToken, owner, collAmount);
        }
        ERC20PresetMinterPauser(collToken).approve(address(bank), collAmount);

        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: strategyId,
            collToken: collToken,
            collAmount: collAmount,
            borrowToken: borrowToken,
            borrowAmount: borrowAmount,
            farmingPoolId: farmingPoolId
        });

        bytes memory swapData = _getParaswapData(
            borrowToken,
            swapToken,
            borrowAmount,
            address(shortLongSpell),
            maxImpact
        );

        bytes memory data = abi.encodeCall(ShortLongSpell.openPosition, (param, swapData));
        try bank.execute(0, address(shortLongSpell), data) returns (uint256 positionId) {
            _validatePosSize(positionId, strategyId);
            _validateLTV(positionId, strategyId);
        } catch {}
    }

    function _validatePosIsClosed(uint256 positionId) internal {
        IBank.Position memory pos = bank.getPositionInfo(positionId);
        uint256 posSize = bank.getOracle().getWrappedTokenValue(pos.collToken, pos.collId, pos.collateralSize);
        assertEq(posSize, 0);
    }

    function _validatePosSize(uint256 positionId, uint256 strategyId) internal {
        IBank.Position memory pos = bank.getPositionInfo(positionId);
        uint256 posSize = bank.getOracle().getWrappedTokenValue(pos.collToken, pos.collId, pos.collateralSize);
        IBasicSpell.Strategy memory strategy = shortLongSpell.getStrategy(strategyId);
        assertGe(posSize, strategy.minPositionSize);
        assertLe(posSize, strategy.maxPositionSize);
    }

    function _validateLTV(uint256 positionId, uint256 strategyId) internal {
        IBank.Position memory pos = bank.getPositionInfo(positionId);
        uint256 debtValue = bank.getDebtValue(positionId);
        uint256 uValue = bank.getIsolatedCollateralValue(positionId);
        assertLe(
            debtValue,
            (uValue * shortLongSpell.getMaxLTV(strategyId, pos.underlyingToken)) / Constants.DENOMINATOR
        );
    }

    function _calculateSlippage(uint256 amount, uint256 slippagePercentage) internal view override returns (uint256) {}

    function _validateReceivedBorrowAndPosition(
        IBank.Position memory previousPosition,
        uint256 positionId,
        uint256 amount
    ) internal override {}

    function _validatePositionSize(
        uint256 lpTokenAmount,
        address lpToken,
        uint256 maxPositionSize,
        uint256 positionId
    ) internal view override returns (bool, IBank.Position memory) {}

    function _assignDeployedContracts() internal override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        shortLongSpell = ShortLongSpell(payable(SHORT_LONG_SPELL_PROXY)); // ShortLongSpell proxy address on Mainnet
        vm.etch(SHORT_LONG_SPELL_IMPLEMENTATION, address(new ShortLongSpell()).code);

        vm.label(address(shortLongSpell), "ShortLongSpell");
        vm.label(address(SHORT_LONG_SPELL_IMPLEMENTATION), "ShortLongSpell-Implementation");
        vm.label(WSTETH, "wstETH");
        vm.label(BWSTETH, "bWSTETH");

        coreOracle = bank.getOracle();
    }

    function _getBalance(Vars memory vars) internal view returns (uint256) {
        return
            bank.getOracle().getTokenValue(vars.collToken, ERC20PresetMinterPauser(vars.collToken).balanceOf(owner)) +
            bank.getOracle().getTokenValue(
                vars.borrowToken,
                ERC20PresetMinterPauser(vars.borrowToken).balanceOf(owner)
            );
    }

    function _setMockOracle() internal override {}

    function _setPriceMultiplier(address token, uint256 multiplier) internal {
        mockOracle = new MockOracle();
        address[] memory tokens = new address[](4);
        tokens[0] = USDC;
        tokens[1] = WETH_ADDRESS;
        tokens[2] = WBTC;
        tokens[3] = WSTETH;
        uint256[] memory prices = new uint256[](4);
        address[] memory oracles = new address[](4);
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = (bank.getOracle().getPrice(tokens[i]) * (tokens[i] == token ? multiplier : 1e18)) / 1e18;
            oracles[i] = address(mockOracle);
        }
        mockOracle.setPrice(tokens, prices);
        vm.prank(IOwnable(address(coreOracle)).owner());
        IExtCoreOracle(address(coreOracle)).setRoutes(tokens, oracles);
    }
}
