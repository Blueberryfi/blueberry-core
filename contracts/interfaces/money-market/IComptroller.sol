// SPDX-License-Identifier: MIT

/* solhint-disable private-vars-leading-underscore */

pragma solidity 0.8.22;

interface IComptroller {
    function setCreditLimit(address protocol, address market, uint256 creditLimit) external;

    function supportMarket(address bToken, uint8 version) external;

    function enterMarkets(address[] memory bTokens) external returns (uint256[] memory);

    function isMarketListed(address bToken) external view returns (bool);

    function getAssetsIn(address account) external returns (address[] memory);

    function _setMarketBorrowCaps(address[] memory bTokens, uint256[] memory newBorrowCaps) external;

    function admin() external view returns (address);

    function _setBorrowPaused(address bToken, bool state) external;
}
