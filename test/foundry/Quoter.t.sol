// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable custom-errors */

/// @dev See https://github.com/Uniswap/v3-periphery/blob/main/contracts/lens/Quoter.sol
abstract contract Quoter {
    function _parseRevertReason(bytes memory reason) internal pure returns (uint256) {
        if (reason.length != 32) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256));
    }

    function callRevert(address target, bytes memory data) external {
        (bool success, bytes memory ans) = target.call(data);
        if (success) {
            uint256 value = abi.decode(ans, (uint256));
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, value)
                revert(ptr, 32)
            }
        } else {
            revert("");
        }
    }

    function quote(address target, bytes memory data) public returns (uint256 ans) {
        // solhint-disable-next-line no-empty-blocks
        try this.callRevert(target, data) {} catch (bytes memory reason) {
            return _parseRevertReason(reason);
        }
    }
}
