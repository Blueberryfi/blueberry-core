// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

interface IComptroller {
    function setCreditLimit(address protocol, address market, uint256 creditLimit) external;

    function supportMarket(address bToken, uint8 version) external;

    function enterMarkets(address[] memory bTokens) external returns (uint256[] memory);

    function _setMarketBorrowCaps(address[] memory bTokens, uint256[] memory newBorrowCaps) external;
}
