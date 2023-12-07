// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/// @dev Slimmed down interface for the IBooster interface used by Aura
/// the full interface can be found here: https://github.com/aurafinance/aura-contracts/blob/01b87464f902b1c1f3d4a022538a9b4ffb471c65/contracts/interfaces/IBooster.sol
interface IAuraBooster {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function addPool(
        address _lptoken,
        address _gauge,
        uint256 _stashVersion
    ) external returns (bool);

    function forceAddPool(
        address _lptoken,
        address _gauge,
        uint256 _stashVersion
    ) external returns (bool);

    function shutdownPool(uint256 _pid) external returns (bool);

    function poolInfo(
        uint256
    )
        external
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        );

    function poolLength() external view returns (uint256);

    function gaugeMap(address) external view returns (bool);

    function setPoolManager(address _poolM) external;

    function shutdownSystem() external;

    function setUsedAddress(address[] memory) external;

    function REWARD_MULTIPLIER_DENOMINATOR() external view returns (uint256);

    function getRewardMultipliers(address) external view returns (uint256);
}
