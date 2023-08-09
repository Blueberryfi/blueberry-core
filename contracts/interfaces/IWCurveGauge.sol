// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IERC20Wrapper.sol";
import "./curve/ICurveRegistry.sol";
import "./curve/ILiquidityGauge.sol";
import "./curve/ICurveGaugeController.sol";

/// @title IWCurveGauge
/// @notice This interface defines the functionality for interacting
///         with Curve's Liquidity Gauges represented as ERC1155 tokens.
/// @dev Curve's Liquidity Gauges allow users to stake liquidity 
///      provider tokens in return for CRV rewards.
interface IWCurveGauge is IERC1155Upgradeable, IERC20Wrapper {

    /// @notice Fetch the CRV token address.
    /// @return An ERC20-compatible address of the CRV token.
    function CRV() external view returns (IERC20Upgradeable);

    /// @notice Mint an ERC1155 token corresponding to a staked amount in a specific Curve Liquidity Gauge.
    /// @param gid The gauge ID representing the specific Curve Liquidity Gauge.
    /// @param amount The amount of liquidity provider tokens to stake.
    /// @return id The ID of the newly minted ERC1155 token representing the staked position.
    function mint(uint gid, uint amount) external returns (uint id);

    /// @notice Burn an ERC1155 token to redeem staked liquidity provider tokens and any earned rewards.
    /// @param id The ID of the ERC1155 token representing the staked position.
    /// @param amount The amount of ERC1155 tokens to burn.
    /// @return pid The gauge ID from which the tokens were redeemed.
    function burn(uint id, uint amount) external returns (uint pid);

    /// @notice Fetch the Curve Registry address.
    /// @return The address of the Curve Registry.
    function registry() external view returns (ICurveRegistry);

    /// @notice Fetch the Curve Gauge Controller address.
    /// @return The address of the Curve Gauge Controller.
    function gaugeController() external view returns (ICurveGaugeController);

    /// @notice Encode two uint values into a single uint.
    function encodeId(uint, uint) external pure returns (uint);

    /// @notice Decode an encoded ID into two separate uint values.
    /// @param id The encoded uint ID to decode.
    /// @return The two individual uint values decoded from the provided ID.
    function decodeId(uint id) external pure returns (uint, uint);

    /// @notice Fetch the liquidity provider (LP) token address associated with a specific gauge ID.
    /// @param gid The gauge ID.
    /// @return The address of the liquidity provider token associated with the provided gauge ID.
    function getLpFromGaugeId(uint256 gid) external view returns (address);
}
