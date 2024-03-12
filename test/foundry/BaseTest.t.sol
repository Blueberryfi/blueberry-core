// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

// solhint-disable-next-line
import { console2 } from "forge-std/console2.sol";

import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CoreOracle } from "@contracts/oracle/CoreOracle.sol";
import { BlueberryBank } from "@contracts/BlueberryBank.sol";
import { ProtocolConfig } from "@contracts/ProtocolConfig.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { IExtBErc20 } from "@test/interfaces/IExtBErc20.sol";
import { FeeManager } from "@contracts/FeeManager.sol";
import { IWETH } from "@contracts/interfaces/IWETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUSDC } from "@contracts/interfaces/IUSDC.sol";
import { IComptroller } from "@test/interfaces/IComptroller.sol";
import { Addresses } from "@test/Addresses.t.sol";

abstract contract BaseTest is Test, Addresses {
    IWETH public WETH;
    IERC20 public CRV;

    BlueberryBank public bank;
    CoreOracle public oracle;
    ProtocolConfig public config;
    FeeManager public feeManager;

    IExtBErc20 public bTokenUSDC;
    IExtBErc20 public bTokenWETH;

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
        (string memory urlOrAlias, uint256 blockNumber) = _getFork();
        vm.createSelectFork({ urlOrAlias: urlOrAlias, blockNumber: blockNumber });
        _generateAndLabel();
        _assignDeployedContracts();
        _deployContracts();
        _configureMinter();
    }

    function _getFork() internal pure virtual returns (string memory, uint256) {
        return ("mainnet", 19_330_000);
    }

    // solhint-disable-next-line private-vars-leading-underscore
    function assertEq(uint256 a, uint256 b, uint256 c) internal {
        return assertEq(a, b, c, "");
    }

    // solhint-disable-next-line private-vars-leading-underscore
    function assertEq(uint256 a, uint256 b, uint256 c, string memory reason) internal {
        reason = string.concat(
            reason,
            bytes(reason).length > 0 ? " " : "",
            "Expected ",
            Strings.toString(a),
            " to be equal to ",
            Strings.toString(b),
            " and ",
            Strings.toString(c)
        );
        assertTrue(a == b && b == c, reason);
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

        WETH = IWETH(WETH_ADDRESS); // WETH Mainnet
        CRV = IERC20(CRV_ADDRESS); // CRV Mainnet

        softVaultUSDC = SoftVault(0x20E83eF1f627629DAf745A205Dcd0D88eff5b402); // Soft Vault USDC Mainnet
        softVaultWETH = SoftVault(0xcCd438a78376955A3b174be619E50Aa3DdD65469); // Soft Vault WETH Mainnet

        bTokenUSDC = IExtBErc20(0x649127D0800a8c68290129F091564aD2F1D62De1); // USDC bToken Mainnet
        bTokenWETH = IExtBErc20(0x643d448CEa0D3616F0b32E3718F563b164e7eDd2); // WETH bToken Mainnet

        comptroller = IComptroller(payable(0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2)); // Comptroller address Mainnet
        comptrollerAdmin = comptroller.admin();

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

    function _deployContracts() internal virtual {
        owner = address(this);
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
    }

    function _configureMinter() internal {
        vm.prank(IUSDC(USDC).masterMinter());
        IUSDC(USDC).configureMinter(owner, type(uint256).max);
    }

    /**
     * @dev The current market is paused at the forked block.
     *      We need to enable the market in Comptroller
     * @param token the market (BToken) we want to enable
     */
    function _enableBToken(IExtBErc20 token) internal {
        vm.startPrank(comptrollerAdmin);
        comptroller._setBorrowPaused(IBErc20(address(token)), false);
        vm.stopPrank();
    }
}
