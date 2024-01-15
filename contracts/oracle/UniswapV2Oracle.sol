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

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import { BBMath } from "../libraries/BBMath.sol";

import { UsingBaseOracle } from "./UsingBaseOracle.sol";
import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 *  @author BlueberryProtocol
 *  @title Uniswap V2 Oracle
 *  @notice Oracle contract which privides price feeds of Uni V2 Lp tokens
 *  @dev Implented Fair Lp Pricing
 *      Ref: https://blog.alphaventuredao.io/fair-lp-token-pricing/
 */
contract UniswapV2Oracle is IBaseOracle, UsingBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(IBaseOracle base) UsingBaseOracle(base) {}

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaseOracle
    function getPrice(address pair) external override returns (uint256) {
        IUniswapV2Pair pool = IUniswapV2Pair(pair);
        uint256 totalSupply = pool.totalSupply();
        if (totalSupply == 0) return 0;

        address token0 = pool.token0();
        address token1 = pool.token1();

        (uint256 r0, uint256 r1, ) = pool.getReserves();
        uint256 px0 = base.getPrice(token0);
        uint256 px1 = base.getPrice(token1);
        uint256 t0Decimal = IERC20Metadata(token0).decimals();
        uint256 t1Decimal = IERC20Metadata(token1).decimals();
        uint256 sqrtK = BBMath.sqrt(r0 * r1 * 10 ** (36 - t0Decimal - t1Decimal));

        return (2 * sqrtK * BBMath.sqrt(px0 * px1)) / totalSupply;
    }
}
