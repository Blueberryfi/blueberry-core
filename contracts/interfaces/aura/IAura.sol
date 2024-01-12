// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable func-name-mixedcase */

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IAura is IERC20MetadataUpgradeable {
    function INIT_MINT_AMOUNT() external view returns (uint256);

    function reductionPerCliff() external view returns (uint256);

    function totalCliffs() external view returns (uint256);

    function EMISSIONS_MAX_SUPPLY() external view returns (uint256);
}
