// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";

// solhint-disable-next-line
import { console2 } from "forge-std/console2.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CoreOracle } from "@contracts/oracle/CoreOracle.sol";
import { BlueberryBank } from "@contracts/BlueberryBank.sol";
import { ProtocolConfig } from "@contracts/ProtocolConfig.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { FeeManager } from "@contracts/FeeManager.sol";
import { IWETH } from "@contracts/interfaces/IWETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IComptroller } from "@test/interfaces/IComptroller.sol";

interface IUSDC {
    function masterMinter() external view returns (address);

    function configureMinter(address minter, uint256 minterAllowedAmount) external;
}

abstract contract BaseTest is Test {
    address public constant USDC_OWNER = 0xFcb19e6a322b27c06842A71e8c725399f049AE3a;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant BUSDC = 0xdfd54ac444eEffc121E3937b4EAfc3C27d39Ae64;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant BDAI = 0x23388Cca2BdFC994D75999667E09cc0F5fF1cc88;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant BWSTETH = 0xB387fd973358d2DfdE4F3795Bc9d2CCeE6449A40;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant BWBTC = 0xE61ad5B0E40c856E6C193120Bd3fa28A432911B6;

    IWETH public WETH;
    IERC20 public CRV;

    BlueberryBank public bank;
    CoreOracle public oracle;
    ProtocolConfig public config;
    FeeManager public feeManager;

    IBErc20 public bTokenUSDC;
    IBErc20 public bTokenWETH;

    SoftVault public softVaultUSDC;
    SoftVault public softVaultWETH;

    IComptroller public comptroller;

    address public comptrollerAdmin;

    address public owner;
    address public treasury;

    address public alice;
    address public bob;
    address public steve;
    address public carol;

    function setUp() public virtual {
        // Forking Ethereum Mainnet at Feb-29-2024 01:47:47 AM +UTC
        // TODO modularize this to select various networks
        vm.createSelectFork({ blockNumber: 19_330_000, urlOrAlias: "mainnet" });
        _generateAndLabel();
        _assignDeployedContracts();
        owner = address(this);

        vm.prank(IUSDC(USDC).masterMinter());
        IUSDC(USDC).configureMinter(owner, type(uint256).max);

        config = ProtocolConfig(
            address(
                new ERC1967Proxy(
                    address(new ProtocolConfig()),
                    abi.encodeCall(ProtocolConfig.initialize, (treasury, owner))
                )
            )
        );

        feeManager = FeeManager(
            address(new ERC1967Proxy(address(new FeeManager()), abi.encodeCall(FeeManager.initialize, (config, owner))))
        );

        config.setFeeManager(address(feeManager));

        oracle = CoreOracle(
            address(new ERC1967Proxy(address(new CoreOracle()), abi.encodeCall(CoreOracle.initialize, (owner))))
        );

        bank = BlueberryBank(
            address(
                new ERC1967Proxy(
                    address(new BlueberryBank()),
                    abi.encodeCall(BlueberryBank.initialize, (oracle, config, owner))
                )
            )
        );

        comptrollerAdmin = comptroller.admin();
    }

    // solhint-disable-next-line private-vars-leading-underscore
    function assertEq(uint256 a, uint256 b, uint256 c) internal {
        assertEq(a, b);
        assertEq(a, c);
    }

    function _generateAndLabel() private {
        // Random addresses to avoid doing addr(01).. and so on.
        alice = 0x4242561C1E631Db687A204161c78aeDbbE7C9D0D;
        bob = 0x42421Eb930A5028707Faf55e90745d9bf2bfc611;
        steve = 0x424266bbF3f6F3a7336F91323197b0cEea239E95;
        carol = 0x42428662256Cb74b24054514c693584F395DA1EE;
        treasury = 0x4242776d817bbcbAb5b57856186AF2B027Cf9f89;
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(steve, "steve");
        vm.label(carol, "carol");
        vm.label(treasury, "treasury");
    }

    function _assignDeployedContracts() internal virtual {
        bank = BlueberryBank(0x9b06eA9Fbc912845DF1302FE1641BEF9639009F7); // Latest Bank Proxy address Mainnet

        WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH Mainnet
        CRV = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV Mainnet

        softVaultUSDC = SoftVault(0x20E83eF1f627629DAf745A205Dcd0D88eff5b402); // Soft Vault USDC Mainnet
        softVaultWETH = SoftVault(0xcCd438a78376955A3b174be619E50Aa3DdD65469); // Soft Vault WETH Mainnet

        bTokenUSDC = IBErc20(0x649127D0800a8c68290129F091564aD2F1D62De1); // USDC bToken Mainnet
        bTokenWETH = IBErc20(0x643d448CEa0D3616F0b32E3718F563b164e7eDd2); // WETH bToken Mainnet

        comptroller = IComptroller(payable(0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2)); // Comptroller address Mainnet

        vm.label(address(comptroller), "comptroller");
        vm.label(address(bank), "bank");
        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
        vm.label(address(CRV), "CRV");
        vm.label(address(softVaultUSDC), "softVaultUSDC");
        vm.label(address(softVaultWETH), "softVaultWETH");
        vm.label(address(bTokenUSDC), "bTokenUSDC");
        vm.label(address(bTokenWETH), "bTokenWETH");
    }

    /**
     * @dev The current market is paused at the forked block.
     *      We need to enable the market in Comptroller
     * @param token the market (BToken) we want to enable
     */
    function _enableBToken(IBErc20 token) internal {
        vm.startPrank(comptrollerAdmin);
        comptroller._setBorrowPaused(token, false);
        vm.stopPrank();
    }
}
