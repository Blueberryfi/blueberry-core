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
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { MockBToken } from "@contracts/mock/MockBToken.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";

abstract contract BaseTest is Test {
    BlueberryBank public bank;
    CoreOracle public oracle;
    ProtocolConfig public config;
    SoftVault public vault;
    ERC20PresetMinterPauser public underlying;
    MockBToken public bToken;
    address public owner;
    address public treasury;
    address alice;
    address bob;
    address steve;
    address clarice;

    function setUp() public virtual {
        _generateAndLabel();
        _deploy(address(this));
    }

    function _deploy(address _owner) internal {
        owner = _owner;
        treasury = _owner;
        underlying = new ERC20PresetMinterPauser("Token", "TOK");
        bToken = new MockBToken(address(underlying));
        config = ProtocolConfig(
            address(
                new ERC1967Proxy(
                    address(new ProtocolConfig()),
                    abi.encodeCall(ProtocolConfig.initialize, (treasury, owner))
                )
            )
        );
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
        assertEq(a, b);
        assertEq(a, c);
    }

    function _generateAndLabel() private {
        // Random addresses to avoid doing addr(01).. and so on.
        alice = 0x4242561C1E631Db687A204161c78aeDbbE7C9D0D;
        bob = 0x42421Eb930A5028707Faf55e90745d9bf2bfc611;
        steve = 0x424266bbF3f6F3a7336F91323197b0cEea239E95;
        clarice = 0x42428662256Cb74b24054514c693584F395DA1EE;
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(steve, "steve");
        vm.label(clarice, "clarice");
    }
}
