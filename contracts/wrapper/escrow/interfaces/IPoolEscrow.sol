// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.16;

interface IPoolEscrow {
    /// @dev Initializes the pool escrow with the given PID.
    function initialize(
        uint256 _pid,
        address _wrapper,
        address _auraPools,
        address _auraRewarder,
        address _lpToken
    ) external;

    /**
     * @notice Transfers tokens to and from a specified address
     * @param _from The address from which the tokens will be transferred
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferTokenFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external;

    /**
     * @notice Transfers tokens to a specified address
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferToken(
        address _token,
        address _to,
        uint256 _amount
    ) external;

    /**
     * @notice Deposits tokens to pool
     * @param _amount The amount of tokens to be deposited
     */
    function deposit(uint256 _amount) external;

    /**
     * @notice Withdraws tokens for a given user
     * @param _amount The amount of tokens to be withdrawn
     * @param _user The user to withdraw tokens to
     */
    function withdraw(uint256 _amount, address _user) external;

    /**
     * @notice Gets rewards from the extra rewarder
     * @param _extraRewardsAddress the rewards address to gather from
     */
    function getRewardExtra(address _extraRewardsAddress) external;

    /**
     * @notice Claims rewards from the aura rewarder
     * @param _amount The amount of tokens
     */
    function claimRewards(uint256 _amount) external;

    /**
     * @notice claims rewards and withdraws for a given user
     * @param _amount The amount of tokens to be withdrawn
     * @param _user The user to withdraw tokens to
     */
    function claimAndWithdraw(uint256 _amount, address _user) external;
}
