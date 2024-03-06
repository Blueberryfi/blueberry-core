// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { console2 as console } from "forge-std/console2.sol";
import { SpellBaseTest } from "@test/fork/spell/SpellBaseTest.t.sol";
import { IOwnable } from "@test/interfaces/IOwnable.sol";
import { ShortLongSpell } from "@contracts/spell/ShortLongSpell.sol";
import { ICoreOracle } from "@contracts/interfaces/ICoreOracle.sol";
import { IBasicSpell } from "@contracts/interfaces/spell/IBasicSpell.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { IBank } from "@contracts/interfaces/IBank.sol";
import "@contracts/utils/BlueberryConst.sol" as Constants;

contract BankShortLongTest is SpellBaseTest {
    ShortLongSpell public shortLongSpell;
    ICoreOracle public coreOracle;

    address public constant SHORT_LONG_SPELL_PROXY = 0x55d206c1A11F4b2f60459e88B5c601A4E1Cd41a5;
    address public constant SHORT_LONG_SPELL_IMPLEMENTATION = 0x6304029C11589f3754d0E9640536949fD41a1519;

    uint256 public constant WSTETH_STRATEGY_ID = 4;

    address public spellOwner;

    function setUp() public override {
        super.setUp();

        _assignDeployedContracts();

        _enableBToken(IBErc20(BDAI));

        spellOwner = IOwnable(address(shortLongSpell)).owner();
    }

    function testFork_BankShortLong_openPosition_success() external {
        uint256 strategyId = WSTETH_STRATEGY_ID;
        address collToken = WBTC;
        uint256 collAmount = 0.4e8;
        address borrowToken = DAI;
        uint256 borrowAmount = 5000e18;
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
        uint256 positionId = 0;
        uint256 id = bank.execute(positionId, address(shortLongSpell), data);

        assertGt(id, positionId, "New position created");
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

    function _calculateSlippageCurve(address pool, uint256 amount) internal view returns (uint256) {}

    function _calculateSlippage(uint256 amount, uint256 slippagePercentage) internal view override returns (uint256) {}

    function _validateReceivedBorrowAndPosition(
        uint256 previousPosition,
        uint256 positionId,
        uint256 amount
    ) internal override {}

    function _validatePositionSize(
        uint256 lpTokenAmount,
        address lpToken,
        uint256 maxPositionSize,
        uint256 positionId
    ) internal view override returns (bool, uint256) {}

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

    /// @notice Get paraswap data
    /// @dev Using paraswap.ts and `vm.ffi` to get paraswap data with the Node.js SDK
    function _getParaswapData(
        address fromToken,
        address toToken,
        uint256 amount,
        address userAddr,
        uint256 maxImpact
    ) internal returns (bytes memory) {
        string[] memory inputs = new string[](8);

        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./script/paraswap.ts";
        inputs[3] = Strings.toHexString(fromToken);
        inputs[4] = Strings.toHexString(toToken);
        inputs[5] = Strings.toString(amount);
        inputs[6] = Strings.toHexString(userAddr);
        inputs[7] = Strings.toString(maxImpact);

        bytes memory res = vm.ffi(inputs);
        return res;
    }
}
