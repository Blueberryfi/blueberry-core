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

import "../utils/BlueberryErrors.sol" as Errors;

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
                                      STRUCTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to ICHI Vaults
     * @param token0 Address of token0
     * @param token1 Address of token1
     * @param token0Decimals Decimals of token0
     * @param token1Decimals Decimals of token1
     */
    struct TokenInfo {
        address token0;
        address token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Mapping of uniswap pair address to token info
    mapping(address => TokenInfo) private _tokenInfo;

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
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IBaseOracle base, address owner) external initializer {
        __UsingBaseOracle_init(base, owner);
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address pair) external view override returns (uint256) {
        TokenInfo memory tokenInfo = getTokenInfo(pair);

        IUniswapV2Pair pool = IUniswapV2Pair(pair);
        uint256 totalSupply = pool.totalSupply();
        if (totalSupply == 0) return 0;

        address token0 = tokenInfo.token0;
        address token1 = tokenInfo.token1;

        IBaseOracle base = getBaseOracle();

        (uint256 r0, uint256 r1, ) = pool.getReserves();
        uint256 px0 = base.getPrice(token0);
        uint256 px1 = base.getPrice(token1);
        uint256 t0Decimal = tokenInfo.token0Decimals;
        uint256 t1Decimal = tokenInfo.token1Decimals;
        uint256 sqrtK = BBMath.sqrt(r0 * r1 * 10 ** (36 - t0Decimal - t1Decimal));

        return (2 * sqrtK * BBMath.sqrt(px0 * px1)) / totalSupply;
    }

    /**
     * @notice Register Uniswap V2 pair to oracle
     * @param pair Address of the Uniswap V2 pair
     */
    function registerPair(address pair) external onlyOwner {
        if (pair == address(0)) revert Errors.ZERO_ADDRESS();

        IUniswapV2Pair pool = IUniswapV2Pair(pair);
        address token0 = pool.token0();
        address token1 = pool.token1();

        _tokenInfo[pair] = TokenInfo({
            token0: token0,
            token1: token1,
            token0Decimals: IERC20Metadata(token0).decimals(),
            token1Decimals: IERC20Metadata(token1).decimals()
        });

        emit RegisterLpToken(pair);
    }

    /**
     * @notice Get token info of the pair
     * @param pair Address of the Uniswap V2 pair
     * @return tokenInfo Token info of the pair
     */
    function getTokenInfo(address pair) public view returns (TokenInfo memory) {
        return _tokenInfo[pair];
    }
}
