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

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "../utils/BlueberryErrors.sol" as Errors;
import "../utils/BlueberryConst.sol" as Constants;

/**
 * @title BaseAdapter
 * @author BlueberryProtocol
 * @notice This contract provides a base for adapters that interface with external oracle services.
 * @dev It allows the owner to set time gaps for price feed data of different tokens.
 */
abstract contract BaseAdapter is Ownable2StepUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice A mapping that associates each token address with its respective time gap.
     * @dev Time gap represents the acceptable age of the data before it is considered outdated.
     */
    mapping(address => uint256) internal _timeGaps;

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a time gap for a specific token is set or updated.
     * @param token The token address for which the time gap was set.
     * @param gap The new time gap value (in seconds).
     */
    event SetTimeGap(address token, uint256 gap);

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the owner to set time gaps for a list of tokens.
     * @dev The time gap is used to determine the acceptable age of the oracle data.
     * @param tokens List of token addresses for which time gaps will be set.
     * @param gaps Corresponding list of time gaps to set for each token.
     */
    function setTimeGap(address[] calldata tokens, uint256[] calldata gaps) external onlyOwner {
        uint256 tokensLength = tokens.length;
        if (tokensLength != gaps.length) revert Errors.INPUT_ARRAY_MISMATCH();

        for (uint256 i = 0; i < tokensLength; ++i) {
            if (gaps[i] > Constants.MAX_TIME_GAP) revert Errors.TOO_LONG_DELAY(gaps[i]);
            if (gaps[i] < Constants.MIN_TIME_GAP) revert Errors.TOO_LOW_MEAN(gaps[i]);
            if (tokens[i] == address(0)) revert Errors.ZERO_ADDRESS();

            _timeGaps[tokens[i]] = gaps[i];
            emit SetTimeGap(tokens[i], gaps[i]);
        }
    }

    /**
     * @notice Fetch the time gap for a specific token.
     * @param token The token address for which the time gap will be fetched.
     * @return The time gap value (in seconds).
     */
    function getTimeGap(address token) external view returns (uint256) {
        return _timeGaps[token];
    }
}
