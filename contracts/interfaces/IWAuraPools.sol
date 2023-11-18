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

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IERC20Wrapper.sol";
import "./balancer/IBalancerPool.sol";
import "./balancer/IBalancerVault.sol";
import "./aura/IAuraPools.sol";
import "./aura/IAura.sol";

/// @title IWAuraPools
/// @notice Interface for interacting with Aura pools wrapped as ERC1155 tokens.
/// @dev This allows users to interact with Balancer-based Aura pools, 
///      staking liquidity pool tokens for rewards.
interface IWAuraPools is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Get the AURA token's contract address.
    /// @return An IAura interface of the AURA token.
    function AURA() external view returns (IAura);

    /// @notice Get the stash AURA token's contract address.
    /// @return Address of the STASH AURA token.
    function STASH_AURA() external view returns (address);

    /// @notice Encode two uint values into a single uint.
    function encodeId(uint, uint) external pure returns (uint);

    /// @notice Decode an encoded ID into two separate uint values.
    /// @param id The encoded uint ID to decode.
    /// @return The two individual uint values decoded from the provided ID.
    function decodeId(uint id) external pure returns (uint, uint);

    /// @notice Fetch the pool tokens, balances and last changed block for a given Balancer Pool Token.
    /// @param bpt The address of the Balancer Pool Token.
    /// @return tokens An array of tokens inside the Balancer Pool.
    /// @return balances An array of token balances inside the Balancer Pool.
    /// @return lastChangedBlock The block number when the pool was last changed.
    function getPoolTokens(
        address bpt
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangedBlock
        );

    /// @notice Get the pool ID for a given Balancer Pool Token.
    /// @param bpt Address of the Balancer Pool Token.
    /// @return The bytes32 pool ID associated with the BPT.
    function getBPTPoolId(address bpt) external view returns (bytes32);

    /// @notice Fetch the Balancer Vault associated with a given Balancer Pool Token.
    /// @param bpt The address of the Balancer Pool Token.
    /// @return An IBalancerVault interface of the associated vault.
    function getVault(address bpt) external view returns (IBalancerVault);

    /// @notice Fetch the Aura Pools contract interface.
    /// @return The IAuraPools interface of the Aura Pools.
    function auraPools() external view returns (IAuraPools);

    /// @notice Fetch detailed information for a specific Aura pool using its pool ID.
    /// @param pid The pool ID.
    /// @return lptoken The liquidity provider token's address for the specific pool.
    /// @return token The reward token's address for the specific pool.
    /// @return gauge The gauge contract's address for the specific pool.
    /// @return crvRewards The Curve rewards contract's address associated with the specific pool.
    /// @return stash The stash contract's address associated with the specific pool.
    /// @return shutdown A boolean indicating if the pool is in shutdown mode.
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        external
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        );

    /// @notice Mint an ERC1155 token corresponding to a staked amount in a specific Aura pool.
    /// @param gid The pool ID representing the specific Aura pool.
    /// @param amount The amount of liquidity provider tokens to stake.
    /// @return id The ID of the newly minted ERC1155 token representing the staked position.
    function mint(uint gid, uint amount) external returns (uint id);

    /// @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
    /// @param id The ID of the ERC1155 token representing the staked position.
    /// @param amount The amount of ERC1155 tokens to burn.
    /// @return rewardTokens An array of reward token addresses.
    /// @return rewards An array of reward amounts corresponding to the reward token addresses.
    function burn(
        uint id,
        uint amount
    )
        external
        returns (address[] memory rewardTokens, uint256[] memory rewards);
}
