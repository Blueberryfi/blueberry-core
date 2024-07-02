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
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
/* solhint-enable max-line-length */

import "../utils/BlueberryErrors.sol" as Errors;

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { ICoreOracle } from "../interfaces/ICoreOracle.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";

/**
 * @title CoreOracle
 * @notice This oracle contract provides reliable price feeds to the Bank contract.
 * @dev It maintains a registry of routes pointing to price feed sources.
 *      The price feed sources can be aggregators, liquidity pool oracles, or any other
 *      custom oracles that conform to the `IBaseOracle` interface.
 */
contract CoreOracle is ICoreOracle, Ownable2StepUpgradeable, PausableUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Mapping from token to oracle routes. => Aggregator | LP Oracle | AdapterOracle ...
    mapping(address => address) private _routes;

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
     * @notice Initializes the CoreOracle contract.
     * @param owner The address of the owner of the contract.
     */
    function initialize(address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
    }

    /// @notice Pauses the contract.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract.
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Register oracle routes for specific tokens.
     * @param tokens Array of token addresses.
     * @param oracleRoutes Array of oracle addresses corresponding to each token.
     */
    function setRoutes(address[] calldata tokens, address[] calldata oracleRoutes) external onlyOwner {
        uint256 tokenLength = tokens.length;
        if (tokenLength != oracleRoutes.length) revert Errors.INPUT_ARRAY_MISMATCH();

        for (uint256 i = 0; i < tokenLength; ++i) {
            address token = tokens[i];
            address route = oracleRoutes[i];
            if (token == address(0) || route == address(0)) revert Errors.ZERO_ADDRESS();

            _routes[token] = route;
            emit SetRoute(token, route);
        }
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) external view override returns (uint256) {
        return _getPrice(token);
    }

    /// @inheritdoc ICoreOracle
    function isTokenSupported(address token) external view override returns (bool) {
        return _isTokenSupported(token);
    }

    /// @inheritdoc ICoreOracle
    function isWrappedTokenSupported(address token, uint256 tokenId) external view override returns (bool) {
        address uToken = IERC20Wrapper(token).getUnderlyingToken(tokenId);
        return _isTokenSupported(uToken);
    }

    /// @inheritdoc ICoreOracle
    function getWrappedTokenValue(
        address token,
        uint256 id,
        uint256 amount
    ) external view override returns (uint256 positionValue) {
        address uToken = IERC20Wrapper(token).getUnderlyingToken(id);
        positionValue = _getTokenValue(uToken, amount);
    }

    /// @inheritdoc ICoreOracle
    function getTokenValue(address token, uint256 amount) external view override returns (uint256) {
        return _getTokenValue(token, amount);
    }

    /// @inheritdoc ICoreOracle
    function getRoute(address token) external view returns (address) {
        return _routes[token];
    }

    /// @notice logic for `getPrice`
    function _getPrice(address token) internal view whenNotPaused returns (uint256) {
        address route = _routes[token];
        if (route == address(0)) revert Errors.NO_ORACLE_ROUTE(token);
        uint256 px = IBaseOracle(route).getPrice(token);
        if (px == 0) revert Errors.PRICE_FAILED(token);

        return px;
    }

    /// @notice logic for `isTokenSupported` and `isWrappedTokenSupported`
    function _isTokenSupported(address token) internal view returns (bool) {
        address route = _routes[token];
        if (route == address(0)) return false;

        try IBaseOracle(route).getPrice(token) returns (uint256 price) {
            return price != 0;
        } catch {
            return false;
        }
    }

    /// @notice logic for `getTokenValue` and `getWrappedTokenValue`
    function _getTokenValue(address token, uint256 amount) internal view returns (uint256 value) {
        uint256 decimals = IERC20MetadataUpgradeable(token).decimals();
        value = (_getPrice(token) * amount) / 10 ** decimals;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     *      variables without shifting down storage in the inheritance chain.
     *      See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[10] private __gap;
}
