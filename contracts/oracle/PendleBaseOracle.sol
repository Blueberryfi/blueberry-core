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
import { IPPtLpOracle } from "@pendle/core-v2/contracts/interfaces/IPPtLpOracle.sol";
import { IPMarket } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import { IStandardizedYield } from "@pendle/core-v2/contracts/interfaces/IStandardizedYield.sol";
import { IPPrincipalToken } from "@pendle/core-v2/contracts/interfaces/IPPrincipalToken.sol";
/* solhint-enable max-line-length */

import "../utils/BlueberryErrors.sol" as Errors;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";
import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @title PendleLPOracle
 * @notice A pricing oracle used to get the price of Pendle LP Tokens.
 */
abstract contract PendleBaseOracle is IBaseOracle, UsingBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Struct to store information about a market
     * @param market The address of the Pendle market
     * @param unitOfPrice The address of the asset that the market is priced on
     * @param duration The duration of the twap for the market oracle
     * @param initializedTimestamp The timestamp at which the oracle was initialized
     * @param isSyTradeable True if the markets sy token is tradeable, false otherwise
     */
    struct MarketInfo {
        address market;
        address unitOfPrice;
        uint32 duration;
        uint32 initializedTimestamp;
        address sy;
        bool isSyTradeable;
    }

    /// @notice Mapping of markets to their respective information
    mapping(address => MarketInfo) internal _markets;

    /// @notice The address of the Pendle oracle
    IPPtLpOracle internal _pendleOracle;

    /// @notice The duration of the fast twap for market oracles (15 minutes)
    uint32 private constant _FAST_TWAP_DURATION = 900;

    /// @notice The duration of the slow twap for market oracles (30 minutes)
    uint32 private constant _SLOW_TWAP_DURATION = 1800;

    /**
     *
     * @param market The address of the Pendle market
     * @param unitOfPrice The address of the asset that the market is priced on
     * @param twapDuration The duration of the twap for the market oracle
     * @param isPt True if we a registering a market for a PT, false if we are registering a market for an LP
     * @param isSyTradeable True if the markets SY token is tradeable, false otherwise
     */
    function registerMarket(
        address market,
        address unitOfPrice,
        uint32 twapDuration,
        bool isPt,
        bool isSyTradeable
    ) external onlyOwner {
        uint256 initializedTimestamp = _initializeOracle(market, twapDuration);

        (IStandardizedYield sy, IPPrincipalToken pt, ) = IPMarket(market).readTokens();

        address token = isPt ? address(pt) : market;

        _markets[token] = MarketInfo({
            market: market,
            unitOfPrice: unitOfPrice,
            duration: twapDuration,
            initializedTimestamp: uint32(initializedTimestamp),
            sy: address(sy),
            isSyTradeable: isSyTradeable
        });
    }

    /**
     * @notice By default Pendle's market oracles are not initialized, therefore it is necessary to
     *         check the status of the oracle on registration and if it is not initialized yet then we must
     *         do it ourselves.
     * @param market The Market address who's oracle is being initialized
     * @param duration The twap duration for the markets oracle
     */
    function _initializeOracle(address market, uint32 duration) internal returns (uint32 initializedTimestamp) {
        if (duration != _FAST_TWAP_DURATION && duration != _SLOW_TWAP_DURATION) {
            revert Errors.INCORRECT_DURATION(duration);
        }

        (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied) = _pendleOracle
            .getOracleState(market, duration);

        // Here we initialize the oracle if it is not already initialized.
        // Data will be processed once the twap duration has passed.
        if (increaseCardinalityRequired) {
            IPMarket(market).increaseObservationsCardinalityNext(cardinalityRequired);
            return uint32(block.timestamp);
        }

        if (!oldestObservationSatisfied) {
            return uint32(block.timestamp);
        }
        // If the oracle is initialized we can return the block timestamp minus the duration
        // as the initialized timestamp since we will use that going forward to validate that
        // the oracle is initialized
        return uint32(block.timestamp - duration);
    }
}
