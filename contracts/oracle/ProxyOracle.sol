// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';

import '../interfaces/IOracle.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/IERC20Wrapper.sol';

contract ProxyOracle is IOracle, Ownable {
    /// The governor sets oracle token factor for a token.
    event SetTokenFactor(address indexed token, TokenFactors tokenFactor);
    /// The governor unsets oracle token factor for a token.
    event UnsetTokenFactor(address indexed token);
    /// The governor sets token whitelist for an ERC1155 token.
    event SetWhitelist(address indexed token, bool ok);

    struct TokenFactors {
        uint16 borrowFactor; // The borrow factor for this token, multiplied by 1e4.
        uint16 collateralFactor; // The collateral factor for this token, multiplied by 1e4.
        uint16 liqIncentive; // The liquidation incentive, multiplied by 1e4.
    }

    IBaseOracle public immutable source; // Main oracle source
    mapping(address => TokenFactors) public tokenFactors; // Mapping from token address to oracle info.
    mapping(address => bool) public whitelistERC1155; // Mapping from token address to whitelist status

    /// @dev Create the contract and initialize the first governor.
    constructor(IBaseOracle _source) {
        source = _source;
    }

    /// @dev Set oracle token factors for the given list of token addresses.
    /// @param tokens List of tokens to set info
    /// @param _tokenFactors List of oracle token factors
    function setTokenFactors(
        address[] memory tokens,
        TokenFactors[] memory _tokenFactors
    ) external onlyOwner {
        require(tokens.length == _tokenFactors.length, 'inconsistent length');
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            require(
                _tokenFactors[idx].borrowFactor >= 10000,
                'borrow factor must be at least 100%'
            );
            require(
                _tokenFactors[idx].collateralFactor <= 10000,
                'collateral factor must be at most 100%'
            );
            require(
                _tokenFactors[idx].liqIncentive >= 10000,
                'incentive must be at least 100%'
            );
            require(
                _tokenFactors[idx].liqIncentive <= 20000,
                'incentive must be at most 200%'
            );
            tokenFactors[tokens[idx]] = _tokenFactors[idx];
            emit SetTokenFactor(tokens[idx], _tokenFactors[idx]);
        }
    }

    /// @dev Unset token factors for the given list of token addresses
    /// @param tokens List of tokens to unset info
    function unsetTokenFactors(address[] memory tokens) external onlyOwner {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            delete tokenFactors[tokens[idx]];
            emit UnsetTokenFactor(tokens[idx]);
        }
    }

    /// @dev Set whitelist status for the given list of token addresses.
    /// @param tokens List of tokens to set whitelist status
    /// @param ok Whitelist status
    function setWhitelistERC1155(address[] memory tokens, bool ok)
        external
        onlyOwner
    {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            whitelistERC1155[tokens[idx]] = ok;
            emit SetWhitelist(tokens[idx], ok);
        }
    }

    /// @dev Return whether the oracle supports evaluating collateral value of the given token.
    /// @param token ERC1155 token address to check for support
    /// @param id ERC1155 token id to check for support
    function supportWrappedToken(address token, uint256 id)
        external
        view
        override
        returns (bool)
    {
        if (!whitelistERC1155[token]) return false;
        address tokenUnderlying = IERC20Wrapper(token).getUnderlyingToken(id);
        return tokenFactors[tokenUnderlying].liqIncentive != 0;
    }

    /// @dev Return whether the ERC20 token is supported
    /// @param token The ERC20 token to check for support
    function support(address token) external view override returns (bool) {
        try source.getPrice(token) returns (uint256 px) {
            return px != 0 && tokenFactors[token].liqIncentive != 0;
        } catch {
            return false;
        }
    }

    /// @dev Return the amount of token out as liquidation reward for liquidating token in.
    /// @param tokenIn Input ERC20 token
    /// @param tokenOut Output ERC1155 token
    /// @param tokenOutId Output ERC1155 token id
    /// @param amountIn Input ERC20 token amount
    function convertForLiquidation(
        address tokenIn,
        address tokenOut,
        uint256 tokenOutId,
        uint256 amountIn
    ) external view override returns (uint256) {
        require(whitelistERC1155[tokenOut], 'bad token');
        address tokenOutUnderlying = IERC20Wrapper(tokenOut).getUnderlyingToken(
            tokenOutId
        );
        uint256 rateUnderlying = IERC20Wrapper(tokenOut).getUnderlyingRate(
            tokenOutId
        );
        TokenFactors memory tokenFactorIn = tokenFactors[tokenIn];
        TokenFactors memory tokenFactorOut = tokenFactors[tokenOutUnderlying];
        require(tokenFactorIn.liqIncentive != 0, 'bad underlying in');
        require(tokenFactorOut.liqIncentive != 0, 'bad underlying out');
        uint256 pxIn = source.getPrice(tokenIn);
        uint256 pxOut = source.getPrice(tokenOutUnderlying);
        uint256 amountOut = (amountIn * pxIn) / pxOut;
        amountOut = (amountOut * 1e18) / rateUnderlying;
        return
            (amountOut *
                tokenFactorIn.liqIncentive *
                tokenFactorOut.liqIncentive) / (10000 * 10000);
    }

    /// @dev Return the USD value of the given input for collateral purpose.
    /// @param token ERC1155 token address to get collateral value
    /// @param id ERC1155 token id to get collateral value
    /// @param amount Token amount to get collateral value, based 1e18
    function getCollateralValue(
        address token,
        uint256 id,
        uint256 amount
    ) external view override returns (uint256) {
        require(whitelistERC1155[token], 'bad token');
        address tokenUnderlying = IERC20Wrapper(token).getUnderlyingToken(id);
        uint256 rateUnderlying = IERC20Wrapper(token).getUnderlyingRate(id);
        uint256 amountUnderlying = (amount * rateUnderlying) / 1e18;
        TokenFactors memory tokenFactor = tokenFactors[tokenUnderlying];
        require(tokenFactor.liqIncentive != 0, 'bad underlying collateral');
        uint256 underlyingValue = (source.getPrice(tokenUnderlying) *
            amountUnderlying) / 1e18;
        return (underlyingValue * tokenFactor.collateralFactor) / 10000;
    }

    /// @dev Return the USD value of the given input for borrow purpose.
    /// @param token ERC20 token address to get borrow value
    /// @param amount ERC20 token amount to get borrow value, based 1e18
    function getDebtValue(address token, uint256 amount)
        external
        view
        override
        returns (uint256)
    {
        TokenFactors memory tokenFactor = tokenFactors[token];
        require(tokenFactor.liqIncentive != 0, 'bad underlying borrow');
        uint256 debtVaule = (source.getPrice(token) * amount) / 1e18;
        return (debtVaule * tokenFactor.borrowFactor) / 10000;
    }
}
