// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../utils/BlueBerryConst.sol" as Constants;
import "../utils/BlueBerryErrors.sol" as Errors;
import "../interfaces/ICoreOracle.sol";
import "../interfaces/IERC20Wrapper.sol";

/// @title CoreOracle
/// @author BlueberryProtocol
/// @notice This oracle contract provides reliable price feeds to the Bank contract.
/// It maintains a registry of routes pointing to price feed sources.
/// The price feed sources can be aggregators, liquidity pool oracles, or any other
/// custom oracles that conform to the `IBaseOracle` interface.
contract CoreOracle is ICoreOracle, OwnableUpgradeable, PausableUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                      PUBLIC STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Mapping from token to oracle routes. => Aggregator | LP Oracle | AdapterOracle ...
    mapping(address => address) public routes;

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

    /// @dev Initializes the CoreOracle contract
    function initialize() external initializer {
        __Ownable_init();
    }

    /// @notice Pauses the contract.
    /// This function can only be called by the owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract.
    /// This function can only be called by the owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Register oracle routes for specific tokens.
    /// @param tokens Array of token addresses.
    /// @param oracleRoutes Array of oracle addresses corresponding to each token.
    function setRoutes(
        address[] calldata tokens,
        address[] calldata oracleRoutes
    ) external onlyOwner {
        if (tokens.length != oracleRoutes.length)
            revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            address token = tokens[idx];
            address route = oracleRoutes[idx];
            if (token == address(0) || route == address(0))
                revert Errors.ZERO_ADDRESS();

            routes[token] = route;
            emit SetRoute(token, route);
        }
    }

    /// @dev Fetches the price of the given token in USD with 18 decimals precision.
    /// @param token ERC-20 token address.
    /// @return price Price of the token.
    function _getPrice(address token) internal whenNotPaused returns (uint256) {
        address route = routes[token];
        if (route == address(0)) revert Errors.NO_ORACLE_ROUTE(token);
        uint256 px = IBaseOracle(route).getPrice(token);
        if (px == 0) revert Errors.PRICE_FAILED(token);
        return px;
    }

    /// @notice Fetches the price of the given token in USD with 18 decimals precision.
    /// @param token ERC-20 token address.
    /// @return price Price of the token.
    function getPrice(address token) external override returns (uint256) {
        return _getPrice(token);
    }

    /// @dev Checks if the oracle supports the given ERC20 token.
    /// @param token ERC20 token address to check.
    /// @return bool True if supported, false otherwise.
    function _isTokenSupported(address token) internal returns (bool) {
        address route = routes[token];
        if (route == address(0)) return false;
        try IBaseOracle(route).getPrice(token) returns (uint256 price) {
            return price != 0;
        } catch {
            return false;
        }
    }

    /// @notice Checks if the oracle supports the given ERC20 token.
    /// @param token ERC20 token address to check.
    /// @return bool True if supported, false otherwise.
    function isTokenSupported(address token) external override returns (bool) {
        return _isTokenSupported(token);
    }

    /// @notice Determines if the oracle supports the underlying token of a given wrapped token.
    /// @dev This is specific to the Blueberry protocol's ERC1155 wrappers (e.g., WERC20).
    /// @param token ERC1155 token address.
    /// @param tokenId ERC1155 token ID.
    /// @return bool True if the underlying token is supported, false otherwise
    function isWrappedTokenSupported(
        address token,
        uint256 tokenId
    ) external override returns (bool) {
        address uToken = IERC20Wrapper(token).getUnderlyingToken(tokenId);
        return _isTokenSupported(uToken);
    }

    /// @dev Fetches the USD value of the specified amount of a token.
    /// @param token ERC20 token address.
    /// @param amount Amount of the token.
    /// @return value USD value of the token amount.
    function _getTokenValue(
        address token,
        uint256 amount
    ) internal returns (uint256 value) {
        uint256 decimals = IERC20MetadataUpgradeable(token).decimals();
        value = (_getPrice(token) * amount) / 10 ** decimals;
    }

    /// @notice Calculates the USD value of wrapped ERC1155 tokens.
    /// @param token ERC1155 Wrapper token address.
    /// @param id ERC1155 token ID.
    /// @param amount Token amount (assumed to be in 1e18 format).
    /// @return positionValue The USD value of the wrapped token.
    function getWrappedTokenValue(
        address token,
        uint256 id,
        uint256 amount
    ) external override returns (uint256 positionValue) {
        address uToken = IERC20Wrapper(token).getUnderlyingToken(id);
        positionValue = _getTokenValue(uToken, amount);
    }

    /// @notice Fetches the USD value of the specified amount of a token.
    /// @param token ERC20 token address.
    /// @param amount Amount of the token.
    /// @return value USD value of the token amount.
    function getTokenValue(
        address token,
        uint256 amount
    ) external override returns (uint256) {
        return _getTokenValue(token, amount);
    }
}
