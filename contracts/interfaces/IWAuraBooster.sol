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

/* solhint-disable max-line-length */
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
/* solhint-enable max-line-length */

import { IAura } from "./aura/IAura.sol";
import { IAuraBooster } from "./aura/IAuraBooster.sol";
import { IBalancerVault } from "./balancer-v2/IBalancerVault.sol";
import { IERC20Wrapper } from "./IERC20Wrapper.sol";
import { IPoolEscrowFactory } from "../wrapper/escrow/interfaces/IPoolEscrowFactory.sol";

/**
 * @title IWAuraBooster
 * @notice Interface for interacting with the Aura booster wrapped as ERC1155 tokens.
 * @dev This allows users to interact with Balancer-based Aura pools,
 *     staking liquidity pool tokens for rewards.
 */
interface IWAuraBooster is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Emitted when a user stakes liquidity provider tokens and a new ERC1155 token is minted.
    event Minted(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a user burns an ERC1155 token to claim rewards and close their position.
    event Burned(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /**
     * @notice Struct for storing information regarding an Aura Pools StashAura Token.
     * @param stashToken The address of the stash token.
     * @param rewarder The address of the rewarder contract.
     * @param lastStashRewardPerToken The last reward per token value for the stash token.
     * @param stashAuraReceived The amount of AURA received by the stash token.
     */
    struct StashAuraInfo {
        address stashAuraToken;
        address rewarder;
        uint256 lastStashRewardPerToken;
        uint256 stashAuraAuraReceived;
    }

    /**
     * @notice Encodes pool id and BAL per share into an ERC1155 token id
     * @param pid The pool id (The first 16-bits)
     * @param balPerShare Amount of BAL per share, multiplied by 1e18 (The last 240-bits)
     * @return id The resulting ERC1155 token id
     */
    function encodeId(uint256 pid, uint256 balPerShare) external pure returns (uint256);

    /**
     * @notice Decode an encoded ID into two separate uint values.
     * @param id The encoded uint ID to decode.
     * @return The two individual uint values decoded from the provided ID.
     */
    function decodeId(uint256 id) external pure returns (uint256, uint256);

    /**
     * @notice Mint an ERC1155 token corresponding to a staked amount in a specific Aura pool.
     * @param pid The pool ID representing the specific Aura pool.
     * @param amount The amount of liquidity provider tokens to stake.
     * @return id The ID of the newly minted ERC1155 token representing the staked position.
     */
    function mint(uint256 pid, uint256 amount) external returns (uint256 id);

    /**
     * @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
     * @param id The Id of the ERC1155 token representing the staked position.
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

    /// @notice Get the AURA token's contract address.
    function getAuraToken() external view returns (IAura);

    /// @notice Get the AURA Booster contract address.
    function getAuraBooster() external view returns (IAuraBooster);

    /// @notice Get the Pool Escrow Factory contract address.
    function getEscrowFactory() external view returns (IPoolEscrowFactory);

    /**
     * @notice Fetch the pool tokens, balances and last changed block for a given Balancer Pool Token.
     * @param bpt The address of the Balancer Pool Token.
     * @return tokens An array of tokens inside the Balancer Pool.
     * @return balances An array of token balances inside the Balancer Pool.
     * @return lastChangedBlock The block number when the pool was last changed.
     */
    function getPoolTokens(
        address bpt
    ) external view returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangedBlock);

    /**
     * @notice Get the pool ID for a given Balancer Pool Token.
     * @param bpt The address of the Balancer Pool Token.
     * @return The bytes32 pool ID associated with the BPT.
     */
    function getBPTPoolId(address bpt) external view returns (bytes32);

    /**
     * @notice Fetch the Balancer Vault associated with a given Balancer Pool Token.
     * @return An IBalancerVault interface of the associated vault.
     */
    function getVault() external view returns (IBalancerVault);

    /**
     * @notice Receive the starting rewardPerToken value for a specific reward token for a given tokenId.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     * @param token The address of the reward token.
     * @return The reward amount per token share.
     */
    function getInitialTokenPerShare(uint256 tokenId, address token) external view returns (uint256);

    /**
     * @notice Fetch detailed information for a specific Aura pool using its pool ID.
     * @param pid The pool ID.
     * @return lptoken The liquidity provider token's address for the specific pool.
     * @return token The reward token's address for the specific pool.
     * @return gauge The gauge contract's address for the specific pool.
     * @return crvRewards The curve rewards contract's address associated with the specific pool.
     * @return stash The stashAura contract's address associated with the specific pool.
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
     * @param pid The pool ID representing the specific Aura pool.
     * @return The address of the escrow contract.
     */
    function getEscrow(uint256 pid) external view returns (address);

    /**
     * @notice Fetch the length of the extra rewarder array for a given pool ID.
     * @param pid The pool ID representing the specific Aura pool.
     * @return The length of the extra rewarder array.
     */
    function extraRewardsLength(uint256 pid) external view returns (uint256);

    /**
     * @notice Fetch the extra rewarder for a given pool ID and index.
     * @param pid The pool ID representing the specific Aura pool.
     * @param index The index to access in the extraRewarder array.
     * @return The address of the extra rewarder contract.
     */
    function getExtraRewarder(uint256 pid, uint256 index) external view returns (address);
}
