// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IIchiFarm {
    function lpToken(uint256 pid) external view returns (address);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            uint256 accIchiPerShare,
            uint256 lastRewardBlock,
            uint256 allocPoint
        );

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) external;
}
