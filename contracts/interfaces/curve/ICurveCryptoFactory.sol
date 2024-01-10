// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */

interface ICurveCryptoFactory {
    function get_coins(address lp) external view returns (address[2] memory);
}
