// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/BlueBerryErrors.sol";

abstract contract BaseAdapter is Ownable {
    /// @dev Mapping from token address to max delay time
    mapping(address => uint256) public maxDelayTimes;

    event SetMaxDelayTime(address token, uint256 maxDelayTime);

    /// @dev Set max delay time for each token
    /// @param tokens List of remapped tokens to set max delay
    /// @param maxDelays List of max delay times to set to
    function setMaxDelayTimes(
        address[] calldata tokens,
        uint256[] calldata maxDelays
    ) external onlyOwner {
        if (tokens.length != maxDelays.length) revert INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (maxDelays[idx] > 2 days) revert TOO_LONG_DELAY(maxDelays[idx]);
            if (maxDelays[idx] < 10) revert TOO_LOW_MEAN(maxDelays[idx]);
            if (tokens[idx] == address(0)) revert ZERO_ADDRESS();
            maxDelayTimes[tokens[idx]] = maxDelays[idx];
            emit SetMaxDelayTime(tokens[idx], maxDelays[idx]);
        }
    }
}
