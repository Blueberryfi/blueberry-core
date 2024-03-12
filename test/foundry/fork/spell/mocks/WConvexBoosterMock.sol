// SPDX-License-Identifier: MIT

import { WConvexBooster } from "@contracts/wrapper/WConvexBooster.sol";

pragma solidity 0.8.22;

contract WConvexBoosterMock is WConvexBooster {
    function cvxPerShareByPid(uint256 pid) public returns (uint256) {
        return _cvxPerShareByPid[pid];
    }

    function cvxPerShareDebt(uint256 pid) public returns (uint256) {
        return _cvxPerShareDebt[pid];
    }

    function lastCrvPerTokenByPid(uint256 pid) public returns (uint256) {
        return _lastCrvPerTokenByPid[pid];
    }

    function getCvxPendingReward(uint256 amount) public returns (uint256) {
        return _getCvxPendingReward(amount);
    }
}
