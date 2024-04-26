// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
/* solhint-enable max-line-length */

import { IConvex } from "./convex/IConvex.sol";
import { ICvxBooster } from "./convex/ICvxBooster.sol";
import { IERC20Wrapper } from "./IERC20Wrapper.sol";
import { ICvxBooster } from "./convex/ICvxBooster.sol";
import { IPoolEscrowFactory } from "../wrapper/escrow/interfaces/IPoolEscrowFactory.sol";

/**
 * @title IWConvexBooster
 * @author Interface for interacting with Convex pools represented as ERC1155 tokens.
 * @notice Convex Pools allow users to stake liquidity pool tokens in return for CVX and other rewards.
 */
interface IWConvexBooster is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Emitted when a user stakes liquidity provider tokens and a new ERC1155 token is minted.
    event Minted(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a user burns an ERC1155 token to claim rewards and close their position.
    event Burned(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /**
     * @notice Struct for storing information regarding an Cvx Pools Stash Token.
     * @param stashToken The address of the stash token.
     * @param rewarder The address of the rewarder contract.
     * @param lastStashRewardPerToken The last reward per token value for the stash token.
     * @param stashCvxReceived The amount of Cvx received by the stash token.
     */
    struct StashTokenInfo {
        address stashToken;
        address rewarder;
        uint256 lastStashRewardPerToken;
        uint256 stashCvxReceived;
    }

    /**
     * @notice Encodes pool id and BAL per share into an ERC1155 token id
     * @param pid The pool id (The first 16-bits)
     * @param cvxPerShare CVX amount per share, which should be multiplied by 1e18 and is the last 240 bits.
     * @return The resulting ERC1155 token id
     */
    function encodeId(uint256 pid, uint256 cvxPerShare) external pure returns (uint256);

    /**
     * @notice Decode an encoded ID into two separate uint values.
     * @param id The encoded uint ID to decode.
     * @return pid The pool ID representing the specific Convex pool.
     * @return cvxPerShare Original CVX amount per share, which should be multiplied by 1e18.
     */
    function decodeId(uint256 id) external pure returns (uint256 pid, uint256 cvxPerShare);

    /**
     *
     * @param pid The pool ID representing the specific Convex pool.
     * @param amount The amount of liquidity provider tokens to stake.
     * @return id The ID of the newly minted ERC1155 token representing the staked position.
     */
    function mint(uint256 pid, uint256 amount) external returns (uint256 id);

    /**
     * @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
     * @param id The ID of the ERC1155 token representing the staked position.
     * @param amount The amount of ERC1155 tokens to burn.
     * @return rewardTokens An array of reward token addresses.
     * @return rewards An array of reward amounts corresponding to the reward token addresses.
     */
    function burn(
        uint256 id,
        uint256 amount
    ) external returns (address[] memory rewardTokens, uint256[] memory rewards);

    /**
     * @notice Syncs extra rewards for a given tokenId
     * @dev Due to the way rewards can be added to an Aura pool, this function is necessary to
     *    sync the extra rewards for a given tokenId before users can access any newly added rewards.
     * @dev It is the responsibility of the user to call this function when new rewards are added.
     * @param pid The pool ID representing the specific Aura pool.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     */
    function syncExtraRewards(uint256 pid, uint256 tokenId) external;

    /// @notice Get the Convex token's contract address.
    function getCvxToken() external view returns (IConvex);

    /// @notice Get the Convex Booster contract address.
    function getCvxBooster() external view returns (ICvxBooster);

    /// @notice Get the Pool Escrow Factory contract address.
    function getEscrowFactory() external view returns (IPoolEscrowFactory);

    /**
     *
     * @param pid The pool ID representing the specific Convex pool.
     * @return lptoken The liquidity provider token's address for the specific pool.
     * @return token The reward token's address for the specific pool.
     * @return gauge The gauge contract's address for the specific pool.
     * @return crvRewards The Curve rewards contract's address associated with the specific pool.
     * @return stash The stash contract's address associated with the specific pool.
     * @return shutdown A boolean indicating if the pool is in shutdown mode.
     */
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        external
        view
        returns (address lptoken, address token, address gauge, address crvRewards, address stash, bool shutdown);

    /**
     * @notice Fetch the escrow for a given pool ID.
     * @param pid The pool ID representing the specific Convex pool.
     * @return The address of the escrow contract.
     */
    function getEscrow(uint256 pid) external view returns (address);

    /**
     * @notice Fetch the length of the extra rewarder array for a given pool ID.
     * @param pid The pool ID representing the specific Convex pool.
     * @return The length of the extra rewarder array.
     */
    function extraRewardsLength(uint256 pid) external view returns (uint256);

    /**
     * @notice Fetch the extra rewarder for a given pool ID and index.
     * @param pid The pool ID representing the specific Convex pool.
     * @param index The index to access in the extraRewarder array.
     * @return The address of the extra rewarder contract.
     */
    function getExtraRewarder(uint256 pid, uint256 index) external view returns (address);

    /**
     * @notice Receive the starting rewardPerToken value for a specific reward token for a given tokenId.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     * @param token The address of the reward token.
     * @return The reward amount per token share.
     */
    function getInitialTokenPerShare(uint256 tokenId, address token) external view returns (uint256);
}
