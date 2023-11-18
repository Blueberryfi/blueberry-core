// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IERC20Wrapper.sol";
import "./convex/ICvxPools.sol";
import "./convex/IConvex.sol";

/// @title IWConvexPools
/// @notice Interface for interacting with Convex pools represented as ERC1155 tokens.
/// @dev Convex pools allow users to stake liquidity pool tokens in return for CVX and other rewards.
interface IWConvexPools is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Fetch the CVX token contract interface.
    /// @return The IConvex interface of the CVX token.
    function CVX() external view returns (IConvex);

    /// @notice Mint an ERC1155 token corresponding to a staked amount in a specific Convex pool.
    /// @param gid The pool ID representing the specific Convex pool.
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

    /// @notice Fetch the Convex Pool contract interface.
    /// @return The ICvxPools interface of the Convex Pool.
    function cvxPools() external view returns (ICvxPools);


    /// @notice Encode two uint values into a single uint.
    function encodeId(uint, uint) external pure returns (uint);

    /// @notice Decode an encoded ID into two separate uint values.
    /// @param id The encoded uint ID to decode.
    /// @return The two individual uint values decoded from the provided ID.
    function decodeId(uint id) external pure returns (uint, uint);

    /// @notice Fetch detailed information for a specific Convex pool using its pool ID.
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
}
