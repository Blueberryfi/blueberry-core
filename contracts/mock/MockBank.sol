// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "../BlueBerryBank.sol";

contract MockBank is BlueBerryBank {
    function createFakePosition(Position memory fakePosition) external {
        uint256 positionId = nextPositionId++;
        positions[positionId] = fakePosition;
    }
}
