// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import './BasicSpell.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract WhitelistSpell is BasicSpell, Ownable {
    mapping(address => bool) public whitelistedLpTokens; // mapping from lp token to whitelist status

    modifier onlyWhitelistedLp(address lpToken) {
        require(whitelistedLpTokens[lpToken], 'lp token not whitelisted');
        _;
    }

    constructor(
        IBank _bank,
        address _werc20,
        address _weth
    ) BasicSpell(_bank, _werc20, _weth) {}

    /// @dev Set whitelist LP token statuses for spell
    /// @param lpTokens LP tokens to set whitelist statuses
    /// @param statuses Whitelist statuses
    function setWhitelistLPTokens(
        address[] calldata lpTokens,
        bool[] calldata statuses
    ) external onlyOwner {
        require(
            lpTokens.length == statuses.length,
            'lpTokens & statuses length mismatched'
        );
        for (uint256 idx = 0; idx < lpTokens.length; idx++) {
            if (statuses[idx]) {
                require(
                    bank.support(lpTokens[idx]),
                    'oracle not support lp token'
                );
            }
            whitelistedLpTokens[lpTokens[idx]] = statuses[idx];
        }
    }
}
