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

interface ISwapRegistry {
    /// @dev Enum representing the different DEXs that can be used for liquidation swaps
    enum DexRoute {
        UniswapV3, // 0 Uniswap is the default DexRoute
        Balancer, // 1
        Curve // 2
    }

    /**
     * @notice Registers a Balancer route for a token pair to be used for liquidation swaps
     * @dev These swaps convert assets received from liquidations to the debt token
     * @param srcToken The address of the token to swap from
     * @param dstToken The address of the token to swap to
     * @param poolId The PoolId for a given token pair
     */
    function registerBalancerRoute(address srcToken, address dstToken, bytes32 poolId) external;

    /**
     * @notice Registers a Balancer route for a token pair to be used for liquidation swaps
     * @dev These swaps convert assets received from liquidations to the debt token
     * @param srcToken The address of the token to swap from
     * @param dstToken The address of the token to swap to
     * @param pool The Pool address for a given token pair
     */
    function registerCurveRoute(address srcToken, address dstToken, address pool) external;

    /**
     * @notice Registers a Uniswap route for a token to be used for liquidation swaps
     * @param srcToken The address of the token to swap from
     */
    function registerUniswapRoute(address srcToken) external;

    /**
     * @notice Registers a token as a protocol token
     * @dev Due to lack of liquidity depth traditionally protocol tokens do not have smooth swap routes
     *      to most other tokens.
     *      This function allows the system to know which tokens are protocol tokens and should be treated differently
     *      resulting in swapping to WETH before swapping to the debt token
     * @param token The address of the token to register
     * @param isProtocolToken A boolean indicating if the token is a protocol token
     */
    function setProtocolToken(address token, bool isProtocolToken) external;
}
