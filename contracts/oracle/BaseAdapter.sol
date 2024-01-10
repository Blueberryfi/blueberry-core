// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/BlueberryErrors.sol" as Errors;
import "../utils/BlueberryConst.sol" as Constants;

/// @title BaseAdapter
/// @author BlueberryProtocol
/// @notice This contract provides a base for adapters that interface with external oracle services.
/// It allows the owner to set time gaps for price feed data of different tokens.
abstract contract BaseAdapter is Ownable {
    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice A mapping that associates each token address with its respective time gap.
    /// Time gap represents the acceptable age of the data before it is considered outdated.
    mapping(address => uint256) public timeGaps;

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a time gap for a specific token is set or updated.
    /// @param token The token address for which the time gap was set.
    /// @param gap The new time gap value (in seconds).
    event SetTimeGap(address token, uint256 gap);

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Allows the owner to set time gaps for a list of tokens.
    /// The time gap is used to determine the acceptable age of the oracle data.
    /// @param tokens List of token addresses for which time gaps will be set.
    /// @param gaps Corresponding list of time gaps to set for each token.
    function setTimeGap(address[] calldata tokens, uint256[] calldata gaps) external onlyOwner {
        if (tokens.length != gaps.length) revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (gaps[i] > Constants.MAX_TIME_GAP) revert Errors.TOO_LONG_DELAY(gaps[i]);
            if (gaps[i] < Constants.MIN_TIME_GAP) revert Errors.TOO_LOW_MEAN(gaps[i]);
            if (tokens[i] == address(0)) revert Errors.ZERO_ADDRESS();
            timeGaps[tokens[i]] = gaps[i];
            emit SetTimeGap(tokens[i], gaps[i]);
        }
    }
}
