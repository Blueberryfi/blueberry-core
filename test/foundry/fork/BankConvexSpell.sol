// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank, console2 } from "@test/BaseTest.t.sol";
import { IOwnable } from "@test/interfaces/IOwnable.sol";
import { IWETH } from "@contracts/interfaces/IWETH.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { ConvexSpell } from "@contracts/spell/ConvexSpell.sol";
import { IBasicSpell } from "@contracts/interfaces/spell/IBasicSpell.sol";
import { IWConvexBooster } from "@contracts/interfaces//IWConvexBooster.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BankConvexSpell is BaseTest {
    IERC20 public USDC;
    IWETH public WETH;
    IERC20 public CRV;

    IBErc20 public bTokenUSDC;
    IBErc20 public bTokenWETH;

    SoftVault public softVaultUSDC;
    SoftVault public softVaultWETH;

    ConvexSpell public convexSpell;

    IWConvexBooster public wConvexBooster;

    address public spellOwner;

    function setUp() public override {
        super.setUp();
        // Forking Ethereum Mainnet at Feb-29-2024 01:47:47 AM +UTC
        // TODO modularize this to select various networks
        vm.createSelectFork({ blockNumber: 19_330_000, urlOrAlias: "mainnet" });
        _assignDeployedContracts();
        alice = vm.addr(11);
        spellOwner = IOwnable(address(convexSpell)).owner();
    }

    function testFork_BankConvexSpell_openPositionFarm() external {
        IBasicSpell.OpenPosParam memory param = IBasicSpell.OpenPosParam({
            strategyId: 0,
            collToken: address(USDC),
            collAmount: 1e18,
            borrowToken: address(WETH),
            borrowAmount: 1e6,
            farmingPoolId: 9
        });
        IBasicSpell.Strategy memory strat = convexSpell.getStrategy(0);

        bytes memory data = abi.encodeCall(ConvexSpell.openPositionFarm, (param, 1e6));
        bank.execute(0, address(convexSpell), data);
    }

    // TODO maybe take these values from the deployments repo?
    function _assignDeployedContracts() private {
        bank = BlueberryBank(0x9b06eA9Fbc912845DF1302FE1641BEF9639009F7); // Latest Bank Proxy address Mainnet

        USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC Mainnet
        WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH Mainnet
        CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV Mainnet

        softVaultUSDC = SoftVault(0x20E83eF1f627629DAf745A205Dcd0D88eff5b402); // Soft Vault USDC Mainnet
        softVaultWETH = SoftVault(0xcCd438a78376955A3b174be619E50Aa3DdD65469); // Soft Vault WETH Mainnet

        bTokenUSDC = IBErc20(0x649127D0800a8c68290129F091564aD2F1D62De1); // USDC bToken Mainnet
        bTokenWETH = IBErc20(0x643d448CEa0D3616F0b32E3718F563b164e7eDd2); // WETH bToken Mainnet

        convexSpell = ConvexSpell(payable(0x936F8e31717c4998804f85889DE758C4780702A4)); // Convex Stable Proxy address Mainnet
        wConvexBooster = IWConvexBooster(address(convexSpell.getWConvexBooster())); // Convex Booster Mainnet

        vm.label(address(bank), "bank");
        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
        vm.label(address(CRV), "CRV");
        vm.label(address(softVaultUSDC), "softVaultUSDC");
        vm.label(address(softVaultWETH), "softVaultWETH");
        vm.label(address(bTokenUSDC), "bTokenUSDC");
        vm.label(address(bTokenWETH), "bTokenWETH");
        vm.label(address(convexSpell), "convexSpell");
        vm.label(address(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40), "bankImpl");
        vm.label(address(0xa89Cc6C319D80744Fe6000A603ccDA2fd637E7B4), "convexSpellImpl");
        vm.label(address(wConvexBooster), "wConvexBooster");
    }
}
