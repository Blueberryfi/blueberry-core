// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Test } from "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CoreOracle } from "@contracts/oracle/CoreOracle.sol";
import { BlueberryBank } from "@contracts/BlueberryBank.sol";
import { ProtocolConfig } from "@contracts/ProtocolConfig.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { FeeManager } from "@contracts/FeeManager.sol";
import { IComptroller } from "@contracts/interfaces/money-market/IComptroller.sol";
import { IUSDC } from "@contracts/interfaces/IUSDC.sol";

abstract contract BaseTest is Test {
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant BUSDC = 0x649127D0800a8c68290129F091564aD2F1D62De1;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant BDAI = 0x23388Cca2BdFC994D75999667E09cc0F5fF1cc88;

    IComptroller public comptroller = IComptroller(0xfFadB0bbA4379dFAbFB20CA6823F6EC439429ec2);

    BlueberryBank public bank;
    CoreOracle public oracle;
    ProtocolConfig public config;
    FeeManager public feeManager;
    SoftVault public vault;
    ERC20PresetMinterPauser public underlying;
    IBErc20 public bToken;
    address public owner;

    address public alice = address(0x10000);
    address public bob = address(0x20000);
    address public carol = address(0x30000);
    address public treasury = address(0x40000);

    function setUp() public {
        vm.createSelectFork("mainnet");
        vm.rollFork(19068161);

        _setupFork();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(treasury, "treasury");
    }

    function _setupFork() internal {
        owner = address(this);

        underlying = ERC20PresetMinterPauser(USDC);
        bToken = IBErc20(BUSDC);

        vm.prank(IUSDC(address(underlying)).masterMinter());
        IUSDC(address(underlying)).configureMinter(address(this), type(uint256).max);

        vm.prank(comptroller.admin());
        comptroller._setBorrowPaused(BUSDC, false);
        vm.prank(comptroller.admin());
        comptroller._setBorrowPaused(BDAI, false);
        address[] memory markets = new address[](2);
        markets[0] = BUSDC;
        markets[1] = BDAI;
        uint256[] memory newBorrowCaps = new uint256[](2);
        newBorrowCaps[0] = type(uint256).max;
        newBorrowCaps[1] = type(uint256).max;
        vm.prank(comptroller.admin());
        comptroller._setMarketBorrowCaps(markets, newBorrowCaps);

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

        vault = SoftVault(
            address(
                new ERC1967Proxy(
                    address(new SoftVault()),
                    abi.encodeCall(
                        SoftVault.initialize,
                        (
                            config,
                            IBErc20(address(bToken)),
                            string.concat("SoftVault ", underlying.name()),
                            string.concat("s", underlying.symbol()),
                            owner
                        )
                    )
                )
            )
        );
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
}
