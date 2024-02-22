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
import { IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IApxEth } from "../interfaces/IApxETH.sol";
import { IBaseOracle } from "../interfaces/IBaseOracle.sol";

/**
 * @title ERC4626Oracle
 * @author BlueberryProtocol
 * @notice Oracle contract which privides price feeds of token vaults that conform to the ERC4626 standard
 */
contract ERC4626Oracle is IBaseOracle, UsingBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to the ERC4626 Token
     * @param underlyingToken The base ERC20 token associated with the ERC4626 token
     * @param underlyingDecimals The decimals of the underlying token
     * @param erc4626Decimals The decimals of the ERC4626 token
     */
    struct TokenInfo {
        address underlyingToken;
        uint8 underlyingDecimals;
        uint8 erc4626Decimals;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev mapping of registered ERC4626 Tokens to their TokenInfo Struct
    mapping(address => TokenInfo) private _tokenInfo;

    /// @dev Address of the APXETH token
    address private constant _APXETH = 0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6;

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
    function getPrice(address token) public view override returns (uint256) {
        TokenInfo memory tokenInfo = _tokenInfo[token];
        if (tokenInfo.underlyingToken == address(0)) {
            revert Errors.ORACLE_NOT_SUPPORT(token);
        }
        uint256 fixedPointOne = 10 ** (18 + tokenInfo.erc4626Decimals - tokenInfo.underlyingDecimals);

        return
            (_base.getPrice(tokenInfo.underlyingToken) * _assetsPerShare(token, fixedPointOne)) /
            (Constants.PRICE_PRECISION);
    }

    /**
     * @notice Registers the token with the oracle
     * @dev Stores persistent data of an ERC4626 token
     * @dev An oracle cannot be used for a token unless it is registered
     * @dev The tokens corresponding underlying token's price feed must be registered within
     *      the base oracle to provide accurate price feeds.
     * @param token Address of the ERC4626 Token
     */
    function registerToken(address token) external onlyOwner {
        if (token == address(0)) revert Errors.ZERO_ADDRESS();

        IERC4626 erc4626 = IERC4626(token);
        address underlyingToken = erc4626.asset();

        _tokenInfo[token] = TokenInfo({
            underlyingToken: underlyingToken,
            underlyingDecimals: IERC20Metadata(underlyingToken).decimals(),
            erc4626Decimals: erc4626.decimals()
        });
    }

    /**
     *
     * @param token The token address of the ERC4626 vault
     * @param fixedPointOne Fixed point one representing 1 share of the ERC4626 vault
     * @return The number of underlying assets per 1 share of the ERC4626 vault
     */
    function _assetsPerShare(address token, uint256 fixedPointOne) internal view returns (uint256) {
        if (token == _APXETH) {
            return IApxEth(_APXETH).assetsPerShare();
        }

        return IERC4626(token).convertToAssets(fixedPointOne);
    }
}
