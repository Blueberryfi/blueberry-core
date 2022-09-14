// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/math/SafeCast.sol';

import '../Governable.sol';
import '../interfaces/IBaseOracle.sol';
import '../interfaces/chainlink/IFeedRegistry.sol';

contract ChainlinkAdapterOracleV2 is IBaseOracle, Governable {
    using SafeCast for int256;

    event SetMaxDelayTime(address indexed token, uint256 maxDelayTime);
    event SetTokenRemapping(
        address indexed token,
        address indexed remappedToken
    );
    event SetRemappedTokenDecimal(address indexed token, uint8 decimal);

    // Chainlink denominations
    // (source: https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/Denominations.sol)
    IFeedRegistry public constant registry =
        IFeedRegistry(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address public constant USD = address(840);

    /// @dev Mapping from original token to remapped token for price querying (e.g. WBTC -> BTC, renBTC -> BTC)
    mapping(address => address) public remappedTokens;
    /// @dev Mapping from token address to max delay time
    mapping(address => uint256) public maxDelayTimes;

    constructor() {
        __Governable__init();
    }

    /// @dev Set max delay time for each token
    /// @param _remappedTokens List of remapped tokens to set max delay
    /// @param _maxDelayTimes List of max delay times to set to
    function setMaxDelayTimes(
        address[] calldata _remappedTokens,
        uint256[] calldata _maxDelayTimes
    ) external onlyGov {
        require(
            _remappedTokens.length == _maxDelayTimes.length,
            '_remappedTokens & _maxDelayTimes length mismatched'
        );
        for (uint256 idx = 0; idx < _remappedTokens.length; idx++) {
            maxDelayTimes[_remappedTokens[idx]] = _maxDelayTimes[idx];
            emit SetMaxDelayTime(_remappedTokens[idx], _maxDelayTimes[idx]);
        }
    }

    /// @dev Set token remapping
    /// @param _tokens List of tokens to set remapping
    /// @param _remappedTokens List of tokens to set remapping to
    /// @notice Token decimals of the original and remapped tokens should be the same
    function setTokenRemappings(
        address[] calldata _tokens,
        address[] calldata _remappedTokens
    ) external onlyGov {
        require(
            _tokens.length == _remappedTokens.length,
            '_tokens & _remappedTokens length mismatched'
        );
        for (uint256 idx = 0; idx < _tokens.length; idx++) {
            remappedTokens[_tokens[idx]] = _remappedTokens[idx];
            emit SetTokenRemapping(_tokens[idx], _remappedTokens[idx]);
        }
    }

    /// @dev Return token price in ETH, multiplied by 2**112
    /// @param _token Token address to get price of
    function getETHPx(address _token) external view override returns (uint256) {
        // remap token if possible
        address token = remappedTokens[_token];
        if (token == address(0)) token = _token;

        if (token == ETH) return uint256(2**112);

        uint256 maxDelayTime = maxDelayTimes[token];
        require(maxDelayTime != 0, 'max delay time not set');

        // try to get token-ETH price
        // if feed not available, use token-USD price with ETH-USD
        try registry.decimals(token, ETH) returns (uint8 decimals) {
            (, int256 answer, , uint256 updatedAt, ) = registry.latestRoundData(
                token,
                ETH
            );
            require(
                updatedAt >= block.timestamp - maxDelayTime,
                'delayed token-eth update time'
            );
            return (answer.toUint256() * 2**112) / 10**decimals;
        } catch {
            uint8 decimals = registry.decimals(token, USD);
            (, int256 answer, , uint256 updatedAt, ) = registry.latestRoundData(
                token,
                USD
            );
            require(
                updatedAt >= block.timestamp - maxDelayTime,
                'delayed token-usd update time'
            );
            (, int256 ethAnswer, , uint256 ethUpdatedAt, ) = registry
                .latestRoundData(ETH, USD);
            require(
                ethUpdatedAt >= block.timestamp - maxDelayTimes[ETH],
                'delayed eth-usd update time'
            );

            if (decimals > 18) {
                return
                    (answer.toUint256() * 2**112) /
                    (ethAnswer.toUint256() * 10**(decimals - 18));
            } else {
                return
                    (answer.toUint256() * 2**112 * 10**(18 - decimals)) /
                    ethAnswer.toUint256();
            }
        }

        revert('no valid price reference for token');
    }
}
