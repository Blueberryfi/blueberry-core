// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import './BasicSpell.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract WhitelistSpell is BasicSpell, Ownable {
    mapping(address => bool) public whitelistedLpTokens; // mapping from lp token to whitelist status

    modifier onlyWhitelistedLp(address lpToken) {
        if (!whitelistedLpTokens[lpToken]) revert LP_NOT_WHITELISTED(lpToken);
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
        if (lpTokens.length != statuses.length) revert INPUT_ARRAY_MISMATCH();
        for (uint256 idx = 0; idx < lpTokens.length; idx++) {
            if (statuses[idx] && !bank.support(lpTokens[idx]))
                revert ORACLE_NOT_SUPPORT_LP(lpTokens[idx]);

            whitelistedLpTokens[lpTokens[idx]] = statuses[idx];
        }
    }
}
