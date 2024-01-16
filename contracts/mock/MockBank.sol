// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "../BlueberryBank.sol";

contract MockBank is BlueberryBank {
    function createFakePosition(Position memory fakePosition) external {
        uint256 positionId = _nextPositionId++;
        _positions[positionId] = fakePosition;
    }
}
