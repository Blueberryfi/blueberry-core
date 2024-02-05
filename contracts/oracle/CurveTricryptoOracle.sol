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

import { CurveBaseOracle } from "./CurveBaseOracle.sol";

import "../utils/BlueberryErrors.sol" as Errors;
import "../utils/BlueberryConst.sol" as Constants;

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ICurveAddressProvider } from "../interfaces/curve/ICurveAddressProvider.sol";
import { ICurveReentrencyWrapper } from "../interfaces/ICurveReentrencyWrapper.sol";

/**
 * @title CurveTricryptoOracle
 * @author BlueberryProtocol
 * @notice Oracle contract that provides price feeds for Curve volatile pool LP tokens.
 */
contract CurveTricryptoOracle is CurveBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                      CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Max gas for reentrancy check.
    uint256 internal constant _MAX_GAS = 10_000;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract
     * @param addressProvider Address of the curve address provider
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(ICurveAddressProvider addressProvider, IBaseOracle base, address owner) external initializer {
        __CurveBaseOracle_init(addressProvider, base, owner);
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address crvLp) external view override returns (uint256) {
        (address pool, address[] memory tokens, uint256 virtualPrice) = _getPoolInfo(crvLp);

        if (_checkReentrant(pool, tokens.length)) revert Errors.REENTRANCY_RISK(pool);

        IBaseOracle base = getBaseOracle();

        /// Check if the token list length is 3 (tricrypto)
        if (tokens.length == 3) {
            return _lpPrice(virtualPrice, base.getPrice(tokens[0]), base.getPrice(tokens[1]), base.getPrice(tokens[2]));
        }
        revert Errors.ORACLE_NOT_SUPPORT_LP(crvLp);
    }

    /**
     * @dev Calculates the LP price using provided token prices and virtual price.
     * @param virtualPrice The virtual price from the pool.
     * @param p1 Price of the first token.
     * @param p2 Price of the second token.
     * @param p3 Price of the third token.
     * @return The calculated LP price.
     */
    function _lpPrice(uint256 virtualPrice, uint256 p1, uint256 p2, uint256 p3) internal pure returns (uint256) {
        return
            (3 * virtualPrice * _cubicRoot(((p1 * p2) / Constants.PRICE_PRECISION) * p3)) / Constants.PRICE_PRECISION;
    }

    /**
     * @dev Calculates the cubic root of the provided value using the Newton-Raphson method.
     * @param x The value to find the cubic root for.
     * @return The calculated cubic root.
     */
    function _cubicRoot(uint256 x) internal pure returns (uint256) {
        uint256 d = x / Constants.PRICE_PRECISION;
        for (uint256 i; i < 255; ++i) {
            uint256 dPrev = d;
            d = (d * (2e18 + ((((x / d) * Constants.PRICE_PRECISION) / d) * Constants.PRICE_PRECISION) / d)) / (3e18);
            uint256 diff = (d > dPrev) ? d - dPrev : dPrev - d;
            if (diff < 2 || diff * Constants.PRICE_PRECISION < d) return d;
        }
        revert("Did Not Converge");
    }

    /// @inheritdoc CurveBaseOracle
    function _checkReentrant(address _pool, uint256) internal view override returns (bool) {
        ICurveReentrencyWrapper pool = ICurveReentrencyWrapper(_pool);

        uint256 gasStart = gasleft();

        //  solhint-disable no-empty-blocks
        try pool.claim_admin_fees{ gas: _MAX_GAS }() {} catch (bytes memory) {}

        uint256 gasSpent;
        unchecked {
            gasSpent = gasStart - gasleft();
        }

        // If the gas spent is greater than the maximum gas, then the call is not-vulnerable to
        // read-only reentrancy
        return gasSpent > _MAX_GAS ? false : true;
    }
}
