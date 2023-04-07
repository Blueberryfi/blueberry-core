// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/BlueBerryErrors.sol" as Errors;
import "../utils/BlueBerryConst.sol" as Constants;

/**
 * @author gmspacex
 * @title BaseAdapter
 * @notice Base Adapter Contract which interacts with external oracle services
 */
abstract contract BaseAdapter is Ownable {
    /// @dev Mapping from token address to max delay time
    mapping(address => uint256) public maxDelayTimes;

    event SetMaxDelayTime(address token, uint256 maxDelayTime);

    /// @notice Set max delay time for each token
    /// @param tokens List of remapped tokens to set max delay
    /// @param maxDelays List of max delay times to set to
    function setMaxDelayTimes(
        address[] calldata tokens,
        uint256[] calldata maxDelays
    ) external onlyOwner {
        if (tokens.length != maxDelays.length)
            revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (maxDelays[idx] > Constants.MAX_TWAP_PERIOD)
                revert Errors.TOO_LONG_DELAY(maxDelays[idx]);
            if (maxDelays[idx] < Constants.MIN_TWAP_PERIOD)
                revert Errors.TOO_LOW_MEAN(maxDelays[idx]);
            if (tokens[idx] == address(0)) revert Errors.ZERO_ADDRESS();
            maxDelayTimes[tokens[idx]] = maxDelays[idx];
            emit SetMaxDelayTime(tokens[idx], maxDelays[idx]);
        }
    }
}
