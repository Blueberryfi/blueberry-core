// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank, console2, ERC20PresetMinterPauser } from "@test/BaseTest.t.sol";
import { IBank } from "@contracts/interfaces/IBank.sol";

abstract contract SpellBaseTest is BaseTest {
    BlueberryBank internal _intBankImpl; // Needed for vm.etch => debug inside the contracts

    function setUp() public virtual override {
        super.setUp();

        _assignDeployedContracts();
    }

    function _calculateSlippage(uint256 amount, uint256 slippagePercentage) internal virtual returns (uint256);

    /**
     * @dev verifies if a position was correctly updated after execute
     * @param previousPosition Previous position size
     * @param positionId Position id
     * @param amount Mew amount that should be added
     */
    function _validateReceivedBorrowAndPosition(
        IBank.Position memory previousPosition,
        uint256 positionId,
        uint256 amount
    ) internal virtual;

    /**
     * @dev Validates if a position is in between boundaries defined by the strategy.minPositionSize and maxPositionSize
     * @param lpTokenAmount Token amount that should be added
     * @param maxPositionSize Max position size defined by strategy
     * @param lpToken The LP token created
     * @param positionId Current position id
     * @return If is valid
     * @return Current position used in validate received borrow and position
     */
    function _validatePositionSize(
        uint256 lpTokenAmount,
        address lpToken,
        uint256 maxPositionSize,
        uint256 positionId
    ) internal view virtual returns (bool, IBank.Position memory);

    function _assignDeployedContracts() internal virtual override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        _intBankImpl = new BlueberryBank();
        vm.etch(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40, address(_intBankImpl).code);

        vm.label(address(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40), "bankImpl");
    }

    /**
     * @dev Sets the mock oracle for various tokens
     */
    function _setMockOracle() internal virtual;
}
