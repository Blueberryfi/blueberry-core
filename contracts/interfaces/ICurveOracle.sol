// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IBaseOracle } from "./IBaseOracle.sol";
import { ICurveAddressProvider } from "../interfaces/curve/ICurveAddressProvider.sol";

/**
 * @title ICurveOracle
 * @notice Interface for the CurveOracle contract which provides price feed data for assets on Curve Finance.
 */
interface ICurveOracle is IBaseOracle {
    /**
     * @notice Fetches relevant information about a Curve liquidity pool.
     * @param crvLp The address of the Curve liquidity pool token (LP token).
     * @return pool Address of the pool contract.
     * @return coins A list of underlying tokens in the Curve liquidity pool.
     * @return virtualPrice The current virtual price of the LP token for the given Curve liquidity pool.
     */
    function getPoolInfo(address crvLp) external returns (address pool, address[] memory coins, uint256 virtualPrice);

    /// @notice Returns the Curve Address Provider.
    function getAddressProvider() external view returns (ICurveAddressProvider);
}
