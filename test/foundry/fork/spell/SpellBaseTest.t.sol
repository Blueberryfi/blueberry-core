// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { BaseTest, BlueberryBank } from "@test/BaseTest.t.sol";

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
        uint256 previousPosition,
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
     * @return Current position size, used to verify the afterwards position size update
     */
    function _validatePositionSize(
        uint256 lpTokenAmount,
        address lpToken,
        uint256 maxPositionSize,
        uint256 positionId
    ) internal view virtual returns (bool, uint256);

    function _assignDeployedContracts() internal virtual override {
        super._assignDeployedContracts();

        // etching the bank impl with the current code to do logging
        _intBankImpl = new BlueberryBank();
        vm.etch(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40, address(_intBankImpl).code);

        vm.label(address(0x737df47A4BdDB0D71b5b22c72B369d0B29329b40), "bankImpl");
    }
}
