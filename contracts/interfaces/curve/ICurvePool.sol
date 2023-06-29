// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface ICurvePool {
    function add_liquidity(uint256[2] calldata, uint256) external;

    function add_liquidity(uint256[3] calldata, uint256) external;

    function add_liquidity(uint256[4] calldata, uint256) external;

    function remove_liquidity(uint256, uint256[2] calldata) external;

    function remove_liquidity(uint256, uint256[3] calldata) external;

    function remove_liquidity(uint256, uint256[4] calldata) external;

    function remove_liquidity_imbalance(uint256[2] calldata, uint256) external;

    function remove_liquidity_imbalance(uint256[3] calldata, uint256) external;

    function remove_liquidity_imbalance(uint256[4] calldata, uint256) external;

    function remove_liquidity_one_coin(uint256, int128, uint256) external;

    function get_virtual_price() external view returns (uint256);

    function lp_token() external view returns (address); // v1

    function token() external view returns (address); // v2

    function balances(uint256 i) external view returns (uint256);

    function withdraw_admin_fees() external;

    function claim_admin_fees() external;

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
}
