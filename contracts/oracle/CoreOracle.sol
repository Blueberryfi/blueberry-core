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

import "../utils/BlueBerryConst.sol" as Constants;
import "../utils/BlueBerryErrors.sol" as Errors;
import "../interfaces/ICoreOracle.sol";
import "../interfaces/IERC20Wrapper.sol";

/**
 * @author gmspacex
 * @title Core Oracle
 * @notice Oracle contract which provides price feeds to Bank contract
 */
contract CoreOracle is ICoreOracle, OwnableUpgradeable {
    /// The owner sets oracle token factor for a token.
    event SetTokenSetting(address indexed token, TokenSetting tokenFactor);
    /// The owner unsets oracle token factor for a token.
    event RemoveTokenSetting(address indexed token);
    /// The owner sets token whitelist for an ERC1155 token.
    event SetWhitelist(address indexed token, bool ok);
    event SetRoute(address indexed token, address route);

    /// @dev Mapping from token address to settings.
    mapping(address => TokenSetting) public tokenSettings;
    mapping(address => bool) public whitelistedERC1155; // Mapping from token address to whitelist status

    function initialize() external initializer {
        __Ownable_init();
    }

    /// @notice Set oracle source routes for tokens
    /// @param tokens List of tokens
    /// @param routes List of oracle source routes
    function setRoute(address[] calldata tokens, address[] calldata routes)
        external
        onlyOwner
    {
        if (tokens.length != routes.length)
            revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (tokens[idx] == address(0) || routes[idx] == address(0))
                revert Errors.ZERO_ADDRESS();

            tokenSettings[tokens[idx]].route = routes[idx];
            emit SetRoute(tokens[idx], routes[idx]);
        }
    }

    /// @notice Set oracle token factors for the given list of token addresses.
    /// @param tokens List of tokens to set info
    /// @param settings List of oracle token factors
    function setTokenSettings(
        address[] memory tokens,
        TokenSetting[] memory settings
    ) external onlyOwner {
        if (tokens.length != settings.length)
            revert Errors.INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (tokens[idx] == address(0) || settings[idx].route == address(0))
                revert Errors.ZERO_ADDRESS();
            if (settings[idx].liqThreshold > Constants.DENOMINATOR)
                revert Errors.LIQ_THRESHOLD_TOO_HIGH(
                    settings[idx].liqThreshold
                );
            if (settings[idx].liqThreshold < Constants.MIN_LIQ_THRESHOLD)
                revert Errors.LIQ_THRESHOLD_TOO_LOW(settings[idx].liqThreshold);
            tokenSettings[tokens[idx]] = settings[idx];
            emit SetTokenSetting(tokens[idx], settings[idx]);
        }
    }

    /// @notice Unset token factors for the given list of token addresses
    /// @param tokens List of tokens to unset info
    function removeTokenSettings(address[] memory tokens) external onlyOwner {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            delete tokenSettings[tokens[idx]];
            emit RemoveTokenSetting(tokens[idx]);
        }
    }

    /// @notice Whitelist ERC1155(wrapped tokens)
    /// @param tokens List of tokens to set whitelist status
    /// @param ok Whitelist status
    function setWhitelistERC1155(address[] memory tokens, bool ok)
        external
        onlyOwner
    {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (tokens[idx] == address(0)) revert Errors.ZERO_ADDRESS();
            whitelistedERC1155[tokens[idx]] = ok;
            emit SetWhitelist(tokens[idx], ok);
        }
    }

    /// @notice Return USD price of given token, multiplied by 10**18.
    /// @param token The ERC-20 token to get the price of.
    function _getPrice(address token) internal view returns (uint256) {
        address route = tokenSettings[token].route;
        if (route == address(0)) revert Errors.NO_ORACLE_ROUTE(token);
        uint256 px = IBaseOracle(route).getPrice(token);
        if (px == 0) revert Errors.PRICE_FAILED(token);
        return px;
    }

    /// @notice Return USD price of given token, multiplied by 10**18.
    /// @param token The ERC-20 token to get the price of.
    function getPrice(address token) external view override returns (uint256) {
        return _getPrice(token);
    }

    /// @notice Return whether the oracle supports underlying token of given wrapper.
    /// @dev Only validate wrappers of Blueberry protocol such as WERC20
    /// @param token ERC1155 token address to check the support
    /// @param tokenId ERC1155 token id to check the support
    function isWrappedTokenSupported(address token, uint256 tokenId)
        external
        view
        override
        returns (bool)
    {
        if (!whitelistedERC1155[token]) return false;
        address uToken = IERC20Wrapper(token).getUnderlyingToken(tokenId);
        return tokenSettings[uToken].route != address(0);
    }

    /// @notice Return whether the oracle given ERC20 token
    /// @param token The ERC20 token to check the support
    function isTokenSupported(address token)
        external
        view
        override
        returns (bool)
    {
        address route = tokenSettings[token].route;
        if (route == address(0)) return false;
        try IBaseOracle(route).getPrice(token) returns (uint256 price) {
            return price != 0;
        } catch {
            return false;
        }
    }

    /**
     * @notice Return the USD value of given position
     * @param token ERC1155 token address to get collateral value
     * @param id ERC1155 token id to get collateral value
     * @param amount Token amount to get collateral value, based 1e18
     */
    function getPositionValue(
        address token,
        uint256 id,
        uint256 amount
    ) external view override returns (uint256 positionValue) {
        if (!whitelistedERC1155[token])
            revert Errors.ERC1155_NOT_WHITELISTED(token);
        address uToken = IERC20Wrapper(token).getUnderlyingToken(id);
        // Underlying token is LP token, and it always has 18 decimals
        // so skipped getting LP decimals
        positionValue = (_getPrice(uToken) * amount) / 1e18;
    }

    /**
     * @dev Return the USD value of the token and amount.
     * @param token ERC20 token address
     * @param amount ERC20 token amount
     */
    function getTokenValue(address token, uint256 amount)
        external
        view
        override
        returns (uint256 debtValue)
    {
        uint256 decimals = IERC20MetadataUpgradeable(token).decimals();
        debtValue = (_getPrice(token) * amount) / 10**decimals;
    }

    /**
     * @notice Returns the Liquidation Threshold setting of collateral token.
     * @dev 85% for volatile tokens, 90% for stablecoins
     * @param token Underlying token address
     * @return liqThreshold of given token
     */
    function getLiqThreshold(address token) external view returns (uint256) {
        return tokenSettings[token].liqThreshold;
    }
}
