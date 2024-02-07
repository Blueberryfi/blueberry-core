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

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { ISwapRegistry } from "../interfaces/ISwapRegistry.sol";

abstract contract SwapRegistry is ISwapRegistry, Ownable2StepUpgradeable {
    /// @notice The address of the WETH token
    address internal _weth;
    /// @notice Mapping of a token to the DEX to use for liquidation swaps
    mapping(address => DexRoute) internal _tokenToExchange;

    /// @notice Mapping of a token pair to the poolId to use for liquidation swaps
    mapping(address => mapping(address => bytes32)) internal _balancerRoutes;

    /// @notice Mapping of a token pair to curve pool to use for liquidation swaps
    mapping(address => mapping(address => address)) internal _curveRoutes;

    /// @inheritdoc ISwapRegistry
    function registerBalancerRoute(address srcToken, address dstToken, bytes32 poolId) external {
        if (srcToken == address(0) || dstToken == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        if (poolId == bytes32(0)) {
            revert Errors.ZERO_AMOUNT();
        }

        _tokenToExchange[srcToken] = DexRoute.Balancer;
        _balancerRoutes[srcToken][dstToken] = poolId;
    }

    /// @inheritdoc ISwapRegistry
    function registerCurveRoute(address srcToken, address dstToken, address pool) external {
        if (srcToken == address(0) || dstToken == address(0) || pool == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _tokenToExchange[srcToken] = DexRoute.Curve;
        _curveRoutes[srcToken][dstToken] = pool;
    }

    /// @inheritdoc ISwapRegistry
    function registerUniswapRoute(address srcToken) external {
        if (srcToken == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _tokenToExchange[srcToken] = DexRoute.UniswapV3;
    }
}
