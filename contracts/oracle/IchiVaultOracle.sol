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

import { UniV3WrappedLibContainer } from "../libraries/UniV3/UniV3WrappedLibContainer.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";
import { BaseOracleExt } from "./BaseOracleExt.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IICHIVault } from "../interfaces/ichi/IICHIVault.sol";

/**
 * @title Ichi Vault Oracle
 * @author BlueberryProtocol
 * @notice Oracle contract provides price feeds of Ichi Vault tokens
 * @dev The logic of this oracle is using legacy & traditional mathematics of Uniswap V2 Lp Oracle.
 *      Base token prices are fetched from Chainlink or Band Protocol.
 *      To prevent flashloan price manipulations, it compares spot & twap prices from Uni V3 Pool.
 */
contract IchiVaultOracle is IBaseOracle, UsingBaseOracle, BaseOracleExt {
    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to ICHI Vaults
     * @param token0 Address of token0
     * @param token1 Address of token1
     * @param token0Decimals Decimals of token0
     * @param token1Decimals Decimals of token1
     * @param vaultDecimals Decimals of ICHI Vault
     */
    struct VaultInfo {
        address token0;
        address token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint8 vaultDecimals;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Mapping to keep track of token info related to ICHI Vaults
    mapping(address => VaultInfo) private _vaultInfo;

    /// @dev Mapping to keep track of the maximum price deviation allowed for each token
    mapping(address => uint256) private _maxPriceDeviations;

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Event emitted when the maximum price deviation for a token is set or updated.
     * @param token The address of the token.
     * @param maxPriceDeviation The new maximum price deviation (in 1e18 format).
     */
    event SetPriceDeviation(address indexed token, uint256 maxPriceDeviation);

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

    /**
     * @notice Register ICHI Vault token to oracle
     * @dev Stores persistent data of ICHI Vault token
     * @dev An oracle cannot be used for a LP token unless it is registered
     * @param vaultToken LP Token to register
     */
    function registerVault(address vaultToken) external onlyOwner {
        if (vaultToken == address(0)) revert Errors.ZERO_ADDRESS();

        IICHIVault vault = IICHIVault(vaultToken);
        address token0 = vault.token0();
        address token1 = vault.token1();

        _vaultInfo[vaultToken] = VaultInfo({
            token0: token0,
            token1: token1,
            token0Decimals: IERC20Metadata(token0).decimals(),
            token1Decimals: IERC20Metadata(token1).decimals(),
            vaultDecimals: vault.decimals()
        });

        emit RegisterLpToken(vaultToken);
    }

    /**
     * @notice Set price deviations for given token
     * @dev Input token is the underlying token of ICHI Vaults which is token0 or token1 of Uni V3 Pool
     * @param token Token to price deviation
     * @param maxPriceDeviation Max price deviation (in 1e18) of price feeds
     */
    function setPriceDeviation(address token, uint256 maxPriceDeviation) external onlyOwner {
        /// Validate inputs
        if (token == address(0)) revert Errors.ZERO_ADDRESS();
        if (maxPriceDeviation > Constants.MAX_PRICE_DEVIATION) {
            revert Errors.OUT_OF_DEVIATION_CAP(maxPriceDeviation);
        }

        _maxPriceDeviations[token] = maxPriceDeviation;

        emit SetPriceDeviation(token, maxPriceDeviation);
    }

    /**
     * @notice Get token0 spot price quoted in token1
     * @param vault ICHI Vault address
     * @return price spot price of token0 quoted in token1
     */
    function spotPrice0InToken1(IICHIVault vault) public view returns (uint256) {
        return
            UniV3WrappedLibContainer.getQuoteAtTick(
                vault.currentTick(), // current tick
                uint128(Constants.PRICE_PRECISION), // amountIn
                vault.token0(), // tokenIn
                vault.token1() // tokenOut
            );
    }

    /**
     * @notice Get token0 twap price quoted in token1
     * @param vault ICHI Vault address
     * @return price spot price of token0 quoted in token1
     */
    function twapPrice0InToken1(IICHIVault vault) public view returns (uint256) {
        uint32 twapPeriod = vault.twapPeriod();
        if (twapPeriod > Constants.MAX_TIME_GAP) revert Errors.TOO_LONG_DELAY(twapPeriod);
        if (twapPeriod < Constants.MIN_TIME_GAP) revert Errors.TOO_LOW_MEAN(twapPeriod);

        (int24 twapTick, ) = UniV3WrappedLibContainer.consult(vault.pool(), twapPeriod);

        return
            UniV3WrappedLibContainer.getQuoteAtTick(
                twapTick,
                uint128(Constants.PRICE_PRECISION), /// amountIn
                vault.token0(), /// tokenIn
                vault.token1() /// tokenOut
            );
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        IICHIVault vault = IICHIVault(token);
        VaultInfo memory vaultInfo = getVaultInfo(token);

        if (vaultInfo.token0 == address(0)) revert Errors.ORACLE_NOT_SUPPORT_LP(token);

        uint256 totalSupply = vault.totalSupply();
        if (totalSupply == 0) return 0;

        address token0 = vaultInfo.token0;
        address token1 = vaultInfo.token1;

        /// Check price manipulations on Uni V3 pool by flashloan attack
        uint256 spotPrice = spotPrice0InToken1(vault);
        uint256 twapPrice = twapPrice0InToken1(vault);
        uint256 maxPriceDeviation = _maxPriceDeviations[token0];
        if (!_isValidPrices(spotPrice, twapPrice, maxPriceDeviation)) revert Errors.EXCEED_DEVIATION();

        IBaseOracle base = getBaseOracle();

        /// Total reserve / total supply
        (uint256 r0, uint256 r1) = vault.getTotalAmounts();
        uint256 px0 = base.getPrice(address(token0));
        uint256 px1 = base.getPrice(address(token1));

        uint256 totalReserve = (r0 * px0) /
            10 ** vaultInfo.token0Decimals +
            (r1 * px1) /
            10 ** vaultInfo.token1Decimals;

        return (totalReserve * 10 ** vaultInfo.vaultDecimals) / totalSupply;
    }

    /**
     * @notice Fetches the vault info for a given LP token.
     * @param token Token address
     * @return VaultInfo struct of given token
     */
    function getVaultInfo(address token) public view returns (VaultInfo memory) {
        return _vaultInfo[token];
    }

    /**
     * @notice Fetches the max price deviation for a given token.
     * @param token Token address
     * @return The max price deviation (in 1e18 format).
     */
    function getMaxPriceDeviation(address token) external view returns (uint256) {
        return _maxPriceDeviations[token];
    }
}
