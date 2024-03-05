// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank, console2, ERC20PresetMinterPauser } from "@test/BaseTest.t.sol";

abstract contract SpellBaseTest is BaseTest {
    BlueberryBank internal _intBankImpl; // Needed for vm.etch => debug inside the contracts

    function setUp() public virtual override {
        super.setUp();

        _assignDeployedContracts();
    }

    function _calculateSlippage(address pool, uint256 amount) internal virtual returns (uint256);

    function _assignDeployedContracts() internal virtual override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        _intBankImpl = new BlueberryBank();
        vm.etch(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40, address(_intBankImpl).code);

        vm.label(address(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40), "bankImpl");
    }
}
