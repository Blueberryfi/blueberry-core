// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CoreOracle } from "@contracts/oracle/CoreOracle.sol";
import { BlueberryBank } from "@contracts/BlueberryBank.sol";
import {ProtocolConfig} from "@contracts/ProtocolConfig.sol";
import {SoftVault} from "@contracts/vault/SoftVault.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {MockBToken} from "@contracts/mock/MockBToken.sol";
import {IBErc20} from "@contracts/interfaces/money-market/IBErc20.sol";

abstract contract BaseTest is Test {
    BlueberryBank public bank;
    CoreOracle public oracle;
    ProtocolConfig public config;
    SoftVault public vault;
    ERC20PresetMinterPauser public underlying;
    MockBToken public bToken;
    address public owner;
    address public treasury;

    function setUp() public {
        deploy(address(this));
    }

    function deploy(address _owner) internal {
        owner = _owner;
        treasury = _owner;
        underlying = new ERC20PresetMinterPauser("Token", "TOK");
        bToken = new MockBToken(address(underlying));
        config = ProtocolConfig(address(new ERC1967Proxy(address(new ProtocolConfig()), abi.encodeCall(ProtocolConfig.initialize, (treasury, owner)))));
        oracle = CoreOracle(address(new ERC1967Proxy(address(new CoreOracle()), abi.encodeCall(CoreOracle.initialize, (owner)))));
        bank = BlueberryBank(address(new ERC1967Proxy(address(new BlueberryBank()), abi.encodeCall(BlueberryBank.initialize, (oracle, config, owner)))));
        vault = SoftVault(address(new ERC1967Proxy(address(new SoftVault()), abi.encodeCall(SoftVault.initialize, (config, IBErc20(address(bToken)), string.concat("SoftVault ", underlying.name()), string.concat("s", underlying.symbol()), owner)))));
    }

    function assertEq(uint256 a, uint256 b, uint256 c) internal {
        assertEq(a, b);
        assertEq(a, c);
    }
}
