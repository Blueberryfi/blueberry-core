// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/**
 * @title IERC20Wrapper
 * @author BlueberryProtocol
 * @notice Interface for the ERC20Wrapper contract which allows the wrapping
 *         of ERC-20 tokens with associated ERC-1155 token IDs.
 */
interface IERC20Wrapper {
    /**
     * @notice Fetches the underlying ERC-20 token address associated with the provided ERC-1155 token ID.
     * @param tokenId The ERC-1155 token ID for which the underlying ERC-20 token address is to be fetched.
     * @return The address of the underlying ERC-20 token.
     */
    function getUnderlyingToken(uint256 tokenId) external view returns (address);

    /**
     * @notice Fetches pending rewards for a particular ERC-1155 token ID and given amount.
     * @param id The ERC-1155 token ID for which the pending rewards are to be fetched.
     * @param amount The amount for which pending rewards are to be calculated.
     * @return tokens A list of addresses representing reward tokens.
     * @return amounts A list of amounts corresponding to each reward token in the `tokens` list.
     */
    function pendingRewards(uint256 id, uint256 amount) external view returns (address[] memory, uint256[] memory);
}
