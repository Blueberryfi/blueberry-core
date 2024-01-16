// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/* solhint-enable max-line-length */

import { IERC20Wrapper } from "./IERC20Wrapper.sol";
import { ICurveRegistry } from "./curve/ICurveRegistry.sol";
import { ICurveGaugeController } from "./curve/ICurveGaugeController.sol";

/**
 * @title IWCurveGauge
 * @notice Interface for interacting with Cruve gauges wrapped as ERC1155 tokens.
 * @dev This allows users to interact with Curve pools,
 *     staking liquidity pool tokens for rewards.
 */
interface IWCurveGauge is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Emitted when a user stakes liquidity provider tokens and a new ERC1155 token is minted.
    event Minted(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /// @notice Emitted when a user burns an ERC1155 token to claim rewards and close their position.
    event Burned(uint256 indexed id, uint256 indexed pid, uint256 amount);

    /**
     * @notice Encodes pool id and Crv per share into an ERC1155 token id
     * @param pid The pool id (The first 16-bits)
     * @param crvPerShare Amount of Crv per share, multiplied by 1e18 (The last 240-bits)
     * @return id The resulting ERC1155 token id
     */
    function encodeId(uint256 pid, uint256 crvPerShare) external pure returns (uint256);

    /**
     * @notice Decode an encoded ID into two separate uint values.
     * @param id The encoded uint ID to decode.
     * @return gid The gauge ID (The first 16-bits)
     * @return crvPerShare Amount of Crv per share, multiplied by 1e18 (The last 240-bits)
     */
    function decodeId(uint256 id) external pure returns (uint256 gid, uint256 crvPerShare);

    /**
     * @notice Mint an ERC1155 token corresponding to a staked amount in a specific Curve Gauge.
     * @param gid The gauge ID representing the specific Curve Gauge.
     * @param amount The amount of liquidity provider tokens to stake.
     * @return id The ID of the newly minted ERC1155 token representing the staked position.
     */
    function mint(uint256 gid, uint256 amount) external returns (uint256 id);

    /**
     * @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
     * @param id The Id of the ERC1155 token representing the staked position.
     * @param amount The amount of ERC1155 tokens to burn.
     * @return rewards CRV rewards earned during the period the LP token was wrapped.
     */
    function burn(uint256 id, uint256 amount) external returns (uint256 rewards);

    /**
     * @notice Fetch the CRV token address.
     * @return An ERC20-compatible address of the CRV token.
     */
    function getCrvToken() external view returns (IERC20Upgradeable);

    /**
     * @notice Fetch the Curve Registry address.
     * @return The address of the Curve Registry.
     */
    function getCurveRegistry() external view returns (ICurveRegistry);

    /**
     * @notice Fetch the Curve Gauge Controller address.
     * @return The address of the Curve Gauge Controller.
     */
    function getGaugeController() external view returns (ICurveGaugeController);

    /**
     * @notice Fetch the accumulated Crv per share for a specific gauge ID.
     * @param gid The gauge ID.
     * @return The total amount of Crv received per share for the provided gauge ID.
     */
    function getAccumulatedCrvPerShare(uint256 gid) external view returns (uint256);

    /**
     * @notice Fetch the liquidity provider (LP) token address associated with a specific gauge ID.
     * @param gid The gauge ID.
     * @return The address of the liquidity provider token associated with the provided gauge ID.
     */
    function getLpFromGaugeId(uint256 gid) external view returns (address);
}
