// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {console2 as console} from "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { CoreOracle } from "@contracts/oracle/CoreOracle.sol";
import { BlueberryBank } from "@contracts/BlueberryBank.sol";
import { ProtocolConfig } from "@contracts/ProtocolConfig.sol";
import { SoftVault } from "@contracts/vault/SoftVault.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IBErc20 } from "@contracts/interfaces/money-market/IBErc20.sol";
import { IComptroller } from "@contracts/interfaces/money-market/IComptroller.sol";
import { IInterestRateModel } from "@contracts/interfaces/money-market/IInterestRateModel.sol";

abstract contract BaseTest is Test {
    BlueberryBank public bank;
    CoreOracle public oracle;
    ProtocolConfig public config;
    SoftVault public vault;
    ERC20PresetMinterPauser public underlying;
    IComptroller public comptroller;
    IInterestRateModel public interestRateModel;
    IBErc20 public bToken;
    address public owner;
    address public treasury;

    address alice = address(0x10000);
    address bob = address(0x20000);
    address carol = address(0x30000);

    function setUp() public {
        _deploy(address(this));

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
    }

    function _deploy(address _owner) internal {
        vm.createSelectFork("mainnet");

        owner = _owner;
        treasury = _owner;

        underlying = new ERC20PresetMinterPauser("Token", "TOK");

        // address comptrollerAddress = makeAddr("Comptroller");
        // vm.etch(comptrollerAddress, vm.getCode("./artifacts/contracts/money-market/Comptroller.sol/Comptroller.json"));
        // comptroller = IComptroller(comptrollerAddress);

        // address interestRateModelAddress = makeAddr("JumpRateModelV2");
        // vm.etch(
        //     interestRateModelAddress,
        //     vm.getCode("./artifacts/contracts/money-market/JumpRateModelV2.sol/JumpRateModelV2.json")
        // );
        // interestRateModel = IInterestRateModel(interestRateModelAddress);

        // console.log(interestRateModel.isInterestRateModel());

        // address bTokenAddress = makeAddr("BToken");
        // vm.etch(bTokenAddress, vm.getCode("./artifacts/contracts/money-market/BErc20.sol/BErc20.json"));
        // bToken = IBErc20(
        //     address(
        //         new ERC1967Proxy(
        //             bTokenAddress,
        //             abi.encodeWithSignature(
        //                 "initialize(address,address,address,uint256,string,string,uint8)",
        //                 underlying,
        //                 comptroller,
        //                 interestRateModel,
        //                 10 ** underlying.decimals(),
        //                 string.concat("b", underlying.name()),
        //                 string.concat("b", underlying.symbol()),
        //                 underlying.decimals()
        //             )
        //         )
        //     )
        // );

        bToken = IBErc20(0xdfd54ac444eEffc121E3937b4EAfc3C27d39Ae64);

        console.log(bToken.underlying());

        config = ProtocolConfig(
            address(
                new ERC1967Proxy(
                    address(new ProtocolConfig()),
                    abi.encodeCall(ProtocolConfig.initialize, (owner, treasury))
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
}
