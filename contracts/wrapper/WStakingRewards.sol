// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../utils/BBMath.sol';
import '../interfaces/IERC20Wrapper.sol';
import '../interfaces/IStakingRewards.sol';

contract WStakingRewards is
    ERC1155('WStakingRewards'),
    ReentrancyGuard,
    IERC20Wrapper
{
    using BBMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable staking; // Staking reward contract address
    address public immutable underlying; // Underlying token address
    address public immutable reward; // Reward token address

    constructor(
        address _staking,
        address _underlying,
        address _reward
    ) {
        staking = _staking;
        underlying = _underlying;
        reward = _reward;
        IERC20(_underlying).safeApprove(_staking, type(uint256).max);
    }

    /// @dev Return the underlying ERC20 for the given ERC1155 token id.
    function getUnderlyingToken(uint256)
        external
        view
        override
        returns (address)
    {
        return underlying;
    }

    /// @dev Return the conversion rate from ERC1155 to ERC20, multiplied 2**112.
    function getUnderlyingRate(uint256)
        external
        pure
        override
        returns (uint256)
    {
        return 2**112;
    }

    /// @dev Mint ERC1155 token for the specified amount
    /// @param amount Token amount to wrap
    function mint(uint256 amount) external nonReentrant returns (uint256) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        IStakingRewards(staking).stake(amount);
        uint256 rewardPerToken = IStakingRewards(staking).rewardPerToken();
        _mint(msg.sender, rewardPerToken, amount, '');
        return rewardPerToken;
    }

    /// @dev Burn ERC1155 token to redeem ERC20 token back.
    /// @param id Token id to burn
    /// @param amount Token amount to burn
    function burn(uint256 id, uint256 amount)
        external
        nonReentrant
        returns (uint256)
    {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        _burn(msg.sender, id, amount);
        IStakingRewards(staking).withdraw(amount);
        IStakingRewards(staking).getReward();
        IERC20(underlying).safeTransfer(msg.sender, amount);
        uint256 stRewardPerToken = id;
        uint256 enRewardPerToken = IStakingRewards(staking).rewardPerToken();
        uint256 stReward = (stRewardPerToken * amount).divCeil(1e18);
        uint256 enReward = (enRewardPerToken * amount) / 1e18;
        if (enReward > stReward) {
            IERC20(reward).safeTransfer(msg.sender, enReward - stReward);
        }
        return enRewardPerToken;
    }
}
