// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/BlueBerryErrors.sol" as Errors;
import "../utils/EnsureApprove.sol";
import "../interfaces/IWConvexPools.sol";
import "../interfaces/IERC20Wrapper.sol";
import "../interfaces/convex/IRewarder.sol";
import "../interfaces/convex/ICvxExtraRewarder.sol";
import "../interfaces/convex/IConvex.sol";

/**
 * @title WConvexPools
 * @author BlueberryProtocol
 * @notice Wrapped Convex Pools is the wrapper of LP positions
 * @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank
 *      and do not generate yields. LP Tokens are identified by tokenIds
 *      encoded from lp token address.
 */
contract WConvexPools is
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    EnsureApprove,
    IERC20Wrapper,
    IWConvexPools
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Address to Convex Pools contract
    ICvxPools public cvxPools;
    /// @dev Address to CVX token
    IConvex public CVX;
    /// @dev Mapping from token id to accExtPerShare
    mapping(uint256 => mapping(address => uint256)) public accExtPerShare;
    /// @dev Extra rewards addresses
    address[] public extraRewards;
    /// @dev The index of extra rewards
    mapping(address => uint256) public extraRewardsIdx;

    function initialize(address cvx_, address cvxPools_) external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("WConvexPools");
        CVX = IConvex(cvx_);
        cvxPools = ICvxPools(cvxPools_);
    }

    /// @notice Encode pid, cvxPerShare to ERC1155 token id
    /// @param pid Pool id (16-bit)
    /// @param cvxPerShare CVX amount per share, multiplied by 1e18 (240-bit)
    function encodeId(
        uint256 pid,
        uint256 cvxPerShare
    ) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (cvxPerShare >= (1 << 240))
            revert Errors.BAD_REWARD_PER_SHARE(cvxPerShare);
        return (pid << 240) | cvxPerShare;
    }

    /// @notice Decode ERC1155 token id to pid, cvxPerShare
    /// @param id Token id
    function decodeId(
        uint256 id
    ) public pure returns (uint256 pid, uint256 cvxPerShare) {
        pid = id >> 240; // First 16 bits
        cvxPerShare = id & ((1 << 240) - 1); // Last 240 bits
    }

    /// @notice Get underlying ERC20 token of ERC1155 given token id
    /// @param id Token id
    function getUnderlyingToken(
        uint256 id
    ) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /// @notice Get pool info from convex booster
    /// @param pid convex pool id
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        public
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address crvRewards,
            address stash,
            bool shutdown
        )
    {
        return cvxPools.poolInfo(pid);
    }

    /// @notice Get pending reward amount
    /// @param stRewardPerShare reward per share
    /// @param rewarder Address of rewarder contract
    /// @param amount lp amount
    /// @param lpDecimals lp decimals
    function _getPendingReward(
        uint stRewardPerShare,
        address rewarder,
        uint amount,
        uint lpDecimals
    ) internal view returns (uint rewards) {
        uint256 enRewardPerShare = IRewarder(rewarder).rewardPerToken();
        uint256 share = enRewardPerShare > stRewardPerShare
            ? enRewardPerShare - stRewardPerShare
            : 0;
        rewards = (share * amount) / (10 ** lpDecimals);
    }

    /// @notice Get CVX pending reward
    /// @param crvAmount Amount of CRV reward
    /// @dev CVX token is minted in booster contract following the mint logic in the below
    function _getCvxPendingReward(
        uint256 crvAmount
    ) internal view returns (uint256 mintAmount) {
        // CVX token mint logic
        uint256 totalCliffs = CVX.totalCliffs();
        uint256 totalSupply = CVX.totalSupply();
        uint256 maxSupply = CVX.maxSupply();
        uint256 reductionPerCliff = CVX.reductionPerCliff();
        uint256 cliff = totalSupply / reductionPerCliff;

        if (totalSupply == 0) {
            mintAmount = crvAmount;
        }

        if (cliff < totalCliffs) {
            uint256 reduction = totalCliffs - cliff;
            mintAmount = (crvAmount * reduction) / totalCliffs;
            uint256 amtTillMax = maxSupply - totalSupply;

            if (mintAmount > amtTillMax) {
                mintAmount = amtTillMax;
            }
        }
    }

    /// @notice Return pending rewards from the farming pool
    /// @dev Reward tokens can be multiple tokens
    /// @param tokenId Token Id
    /// @param amount amount of share
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    )
        public
        view
        override
        returns (address[] memory tokens, uint256[] memory rewards)
    {
        (uint256 pid, uint256 stCrvPerShare) = decodeId(tokenId);
        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();
        uint extraRewardsCount = extraRewards.length;
        tokens = new address[](extraRewardsCount + 2);
        rewards = new uint256[](extraRewardsCount + 2);

        // CRV reward
        tokens[0] = IRewarder(cvxRewarder).rewardToken();
        rewards[0] = _getPendingReward(
            stCrvPerShare,
            cvxRewarder,
            amount,
            lpDecimals
        );

        // CVX reward
        tokens[1] = address(CVX);
        rewards[1] = _getCvxPendingReward(rewards[0]);

        for (uint i = 0; i < extraRewardsCount; ) {
            address rewarder = extraRewards[i];
            uint256 stRewardPerShare = accExtPerShare[tokenId][rewarder];
            tokens[i + 2] = IRewarder(rewarder).rewardToken();
            if (stRewardPerShare == 0) {
                rewards[i + 2] = 0;
            } else {
                rewards[i + 2] = _getPendingReward(
                    stRewardPerShare == type(uint).max ? 0 : stRewardPerShare,
                    rewarder,
                    amount,
                    lpDecimals
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Mint ERC1155 token for the given LP token
    /// @param pid Convex Pool id
    /// @param amount Token amount to wrap
    function mint(
        uint256 pid,
        uint256 amount
    ) external nonReentrant returns (uint256 id) {
        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        IERC20Upgradeable(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        _ensureApprove(lpToken, address(cvxPools), amount);
        cvxPools.deposit(pid, amount, true);

        uint256 crvRewardPerToken = IRewarder(cvxRewarder).rewardPerToken();
        id = encodeId(pid, crvRewardPerToken);
        _mint(msg.sender, id, amount, "");
        // Store extra rewards info
        uint extraRewardsCount = IRewarder(cvxRewarder).extraRewardsLength();
        for (uint i; i < extraRewardsCount; ) {
            address extraRewarder = IRewarder(cvxRewarder).extraRewards(i);
            uint rewardPerToken = IRewarder(extraRewarder).rewardPerToken();
            accExtPerShare[id][extraRewarder] = rewardPerToken == 0
                ? type(uint).max
                : rewardPerToken;

            _syncExtraReward(extraRewarder);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Burn ERC1155 token to redeem ERC20 token back
    /// @param id Token id to burn
    /// @param amount Token amount to burn
    /// @return rewardTokens Reward tokens rewards harvested
    function burn(
        uint256 id,
        uint256 amount
    )
        external
        nonReentrant
        returns (address[] memory rewardTokens, uint256[] memory rewards)
    {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        (uint256 pid, ) = decodeId(id);
        _burn(msg.sender, id, amount);

        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        // Claim Rewards
        IRewarder(cvxRewarder).withdraw(amount, true);
        // Withdraw LP
        cvxPools.withdraw(pid, amount);

        // Transfer LP Tokens
        IERC20Upgradeable(lpToken).safeTransfer(msg.sender, amount);

        uint extraRewardsCount = IRewarder(cvxRewarder).extraRewardsLength();

        for (uint i; i < extraRewardsCount; ) {
            _syncExtraReward(IRewarder(cvxRewarder).extraRewards(i));

            unchecked {
                ++i;
            }
        }
        uint storedExtraRewardLength = extraRewards.length;
        bool hasDiffExtraRewards = extraRewardsCount != storedExtraRewardLength;

        // Transfer Reward Tokens
        (rewardTokens, rewards) = pendingRewards(id, amount);

        // Withdraw manually
        if (hasDiffExtraRewards) {
            for (uint i; i < storedExtraRewardLength; ) {
                ICvxExtraRewarder(extraRewards[i]).getReward();

                unchecked {
                    ++i;
                }
            }
        }

        uint rewardLen = rewardTokens.length;
        for (uint i; i < rewardLen; ) {
            IERC20Upgradeable(rewardTokens[i]).safeTransfer(
                msg.sender,
                rewards[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get length of extra rewards
    function extraRewardsLength() external view returns (uint) {
        return extraRewards.length;
    }

    function _syncExtraReward(address extraReward) private {
        if (extraRewardsIdx[extraReward] == 0) {
            extraRewards.push(extraReward);
            extraRewardsIdx[extraReward] = extraRewards.length;
        }
    }
}
