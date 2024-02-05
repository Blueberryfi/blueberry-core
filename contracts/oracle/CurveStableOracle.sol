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

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ICurveAddressProvider } from "../interfaces/curve/ICurveAddressProvider.sol";
import { ICurveReentrencyWrapper } from "../interfaces/ICurveReentrencyWrapper.sol";

/**
 * @title CurveStableOracle
 * @author BlueberryProtocol
 * @notice Oracle contract that provides price feeds for Curve stable LP tokens.
 */
contract CurveStableOracle is CurveBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                      CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Max gas for reentrancy check.
    uint256 private constant _MAX_GAS = 10_000;

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

        uint256 minPrice = type(uint256).max;
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 tokenPrice = _base.getPrice(tokens[i]);
            if (tokenPrice < minPrice) minPrice = tokenPrice;
        }

        // Calculate LP token price using the minimum underlying token price
        return (minPrice * virtualPrice) / Constants.PRICE_PRECISION;
    }

    /// @inheritdoc CurveBaseOracle
    function _checkReentrant(address _pool, uint256 _numTokens) internal view override returns (bool) {
        ICurveReentrencyWrapper pool = ICurveReentrencyWrapper(_pool);

        uint256 gasStart = gasleft();

        //  solhint-disable no-empty-blocks
        if (_numTokens == 2) {
            uint256[2] memory amounts;
            try pool.remove_liquidity{ gas: _MAX_GAS }(0, amounts) {} catch (bytes memory) {}
        } else if (_numTokens == 3) {
            uint256[3] memory amounts;
            try pool.remove_liquidity{ gas: _MAX_GAS }(0, amounts) {} catch (bytes memory) {}
        } else if (_numTokens == 4) {
            uint256[4] memory amounts;
            try pool.remove_liquidity{ gas: _MAX_GAS }(0, amounts) {} catch (bytes memory) {}
        }

        uint256 gasSpent;
        unchecked {
            gasSpent = gasStart - gasleft();
        }

        // If the gas spent is greater than the maximum gas, then the call is not-vulnerable to
        // read-only reentrancy
        return gasSpent > _MAX_GAS ? false : true;
    }

    /// @notice Fallback function to receive Ether.
    receive() external payable {}
}
