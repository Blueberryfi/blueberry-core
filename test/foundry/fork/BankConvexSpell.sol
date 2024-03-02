// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank, console2, ERC20PresetMinterPauser } from "@test/BaseTest.t.sol";
import { IOwnable } from "@test/interfaces/IOwnable.sol";
import { ConvexSpell } from "@contracts/spell/ConvexSpell.sol";
import { IBasicSpell } from "@contracts/interfaces/spell/IBasicSpell.sol";
import { IWConvexBooster } from "@contracts/interfaces//IWConvexBooster.sol";

contract BankConvexSpell is BaseTest {
    ConvexSpell public convexSpell;

    IWConvexBooster public wConvexBooster;
    BlueberryBank internal _intBankImpl; // Needed for vm.etch => debug inside the contracts
    ConvexSpell internal _intConvexSpell; // Needed for vm.etch => debug inside the contracts

    address public spellOwner;

    function setUp() public override {
        super.setUp();

        _assignDeployedContracts();

        _enableBToken(bTokenWETH);

        spellOwner = IOwnable(address(convexSpell)).owner();
    }

    function testFork_BankConvexSpell_openPositionFarm() external {
        ERC20PresetMinterPauser(address(USDC)).mint(owner, 1e18);
        ERC20PresetMinterPauser(address(USDC)).approve(address(bank), 1e18);

        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: 1e18,
            borrowToken: address(WETH),
            borrowAmount: 1.5e18,
            farmingPoolId: 25
        });
        IBasicSpell.Strategy memory strat = convexSpell.getStrategy(0);
        console2.log("strat params ", strat.minPositionSize);

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 0)); // note slippage is set to 0
        bank.execute(0, address(convexSpell), data);
    }

    // TODO maybe take these values from the deployments repo?
    function _assignDeployedContracts() internal override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        _intBankImpl = new BlueberryBank();
        _intConvexSpell = new ConvexSpell();
        vm.etch(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40, address(_intBankImpl).code);

        convexSpell = ConvexSpell(payable(0x936F8e31717c4998804f85889DE758C4780702A4)); // Convex Stable Proxy address Mainnet
        vm.etch(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4, address(_intConvexSpell).code);

        vm.label(address(convexSpell), "convexSpell");
        vm.label(address(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40), "bankImpl");
        vm.label(address(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4), "convexSpellImpl");
    }
}
