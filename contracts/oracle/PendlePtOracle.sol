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

import { IPPtLpOracle } from "@pendle/core-v2/contracts/interfaces/IPPtLpOracle.sol";
import { IPMarket } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import { PendlePtOracleLib } from "@pendle/core-v2/contracts/oracles/PendlePtOracleLib.sol";

import "../utils/BlueberryConst.sol" as Constants;

import { PendleBaseOracle } from "./PendleBaseOracle.sol";
import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @title PendlePtOracle
 * @notice A pricing oracle used to get the price of Pendle Principle Tokens.
 */
contract PendlePtOracle is PendleBaseOracle {
    using PendlePtOracleLib for IPMarket;

    /*//////////////////////////////////////////////////////////////////////////
                                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param pendleOracle The Pendle Oracle instance.
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IPPtLpOracle pendleOracle, IBaseOracle base, address owner) external initializer {
        __UsingBaseOracle_init(base, owner);
        _pendleOracle = pendleOracle;
    }

    /**
     * @notice Get the price of a PT token
     * @dev If the PTs SY is a tradeable asset then we price the PT in terms of its SY before pricing in USD.
     *      If the PTs SY is not tradeable we price the asset in terms of its asset before pricing in USD
     * @param token The address of the token to get the price of
     */
    function getPrice(address token) external view override returns (uint256) {
        MarketInfo memory marketInfo = _markets[token];

        if (marketInfo.isSyTradeable) {
            uint256 priceInSy = IPMarket(marketInfo.market).getPtToSyRate(marketInfo.duration);
            return (priceInSy * _base.getPrice(marketInfo.unitOfPrice)) / Constants.PRICE_PRECISION;
        } else {
            uint256 priceInAsset = IPMarket(marketInfo.market).getPtToAssetRate(marketInfo.duration);
            return (priceInAsset * _base.getPrice(marketInfo.unitOfPrice)) / Constants.PRICE_PRECISION;
        }
    }
}
