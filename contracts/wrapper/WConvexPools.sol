// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/BlueberryErrors.sol" as Errors;
import { IWConvexPools, ICvxBooster } from "../interfaces/IWConvexPools.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IRewarder } from "../interfaces/convex/IRewarder.sol";
import { ICvxExtraRewarder } from "../interfaces/convex/ICvxExtraRewarder.sol";
import { IConvex } from "../interfaces/convex/IConvex.sol";
import { IPoolEscrowFactory } from "./escrow/interfaces/IPoolEscrowFactory.sol";
import { IPoolEscrow } from "./escrow/interfaces/IPoolEscrow.sol";
/* solhint-enable max-line-length */

/// @title WConvexPools
/// @author BlueberryProtocol
/// @notice Wrapped Convex Pools is the wrapper of LP positions.
/// @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank
///      and do not generate yields. LP Tokens are identified by tokenIds
///      encoded from lp token address.
contract WConvexPools is
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    IERC20Wrapper,
    IWConvexPools
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to Convex Pools contract
    ICvxBooster public cvxBooster;
    /// @dev Address to CVX token
    IConvex public cvxToken;
    /// @dev Address of the escrow factory
    IPoolEscrowFactory public escrowFactory;
    /// @dev Mapping from token id to accExtPerShare
    mapping(uint256 => mapping(address => uint256)) public accExtPerShare;
    /// @dev CVX reward per share by pid
    mapping(uint256 => uint256) public cvxPerShareByPid;
    /// token id => cvxPerShareDebt;
    mapping(uint256 => uint256) public cvxPerShareDebt;
    /// @dev pid => last crv reward per token
    mapping(uint256 => uint256) public lastCrvPerTokenByPid;
    /// @dev pid => escrow contract address
    mapping(uint256 => address) public escrows;
    /// @dev pid => A set of extra rewarders
    mapping(uint256 => EnumerableSetUpgradeable.AddressSet) private _extraRewards;

    /// @dev Initialize the smart contract references.
    /// @param cvx_ Address of the CVX token.
    /// @param cvxPools_ Address of the Convex Pools.
    function initialize(address cvx_, address cvxPools_, address escrowFactory_) external initializer {
        if (cvx_ == address(0) || cvxPools_ == address(0) || escrowFactory_ == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        __ReentrancyGuard_init();
        __ERC1155_init("WConvexPools");
        escrowFactory = IPoolEscrowFactory(escrowFactory_);
        cvxToken = IConvex(cvx_);
        cvxBooster = ICvxBooster(cvxPools_);
    }

    /// @notice Encode pid and cvxPerShare into an ERC1155 token id.
    /// @param pid Pool id which is the first 16 bits.
    /// @param cvxPerShare CVX amount per share, which should be multiplied by 1e18 and is the last 240 bits.
    /// @return id The encoded token id.
    function encodeId(uint256 pid, uint256 cvxPerShare) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (cvxPerShare >= (1 << 240)) {
            revert Errors.BAD_REWARD_PER_SHARE(cvxPerShare);
        }
        return (pid << 240) | cvxPerShare;
    }

    /// @notice Decode an ERC1155 token id into its pid and cvxPerShare components.
    /// @param id Token id.
    /// @return pid The decoded pool id.
    /// @return cvxPerShare The decoded CVX amount per share.
    function decodeId(uint256 id) public pure returns (uint256 pid, uint256 cvxPerShare) {
        pid = id >> 240; // Extract the first 16 bits
        cvxPerShare = id & ((1 << 240) - 1); // Extract the last 240 bits
    }

    /// Mints ERC1155 token for the given LP token
    /// @param pid Convex Pool id
    /// @param amount Token amount to wrap
    /// @return id The minted token ID
    function mint(uint256 pid, uint256 amount) external nonReentrant returns (uint256 id) {
        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(pid);

        /// Escrow deployment/get logic
        address escrow;

        if (escrows[pid] == address(0)) {
            escrow = escrowFactory.createEscrow(pid, cvxRewarder, lpToken);
            escrows[pid] = escrow;
        } else {
            escrow = escrows[pid];
        }

        IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, escrow, amount);

        _updateCvxReward(pid);

        /// Deposit LP from escrow contract
        IPoolEscrow(escrow).deposit(amount);

        uint256 crvRewardPerToken = IRewarder(cvxRewarder).rewardPerToken();
        id = encodeId(pid, crvRewardPerToken);

        _mint(msg.sender, id, amount, "");

        // Store extra rewards info
        uint256 _extraRewardsCount = IRewarder(cvxRewarder).extraRewardsLength();
        for (uint256 i; i < _extraRewardsCount; ++i) {
            address extraRewarder = IRewarder(cvxRewarder).extraRewards(i);
            bool mismatchFound = _syncExtraRewards(pid, id, extraRewarder);

            if (!mismatchFound) {
                _setAccExtPerShare(id, extraRewarder);
            }
        }

        cvxPerShareDebt[id] = cvxPerShareByPid[pid];
    }

    /// Burns ERC1155 token to redeem ERC20 token back and harvest rewards
    /// @param id Token id to burn
    /// @param amount Token amount to burn
    /// @return rewardTokens The array of reward token addresses
    /// @return rewards The array of harvested reward amounts
    function burn(
        uint256 id,
        uint256 amount
    ) external nonReentrant returns (address[] memory rewardTokens, uint256[] memory rewards) {
        (uint256 pid, ) = decodeId(id);
        address escrow = getEscrow(pid);

        // @dev sanity check
        assert(escrow != address(0));

        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }

        _updateCvxReward(pid);

        (rewardTokens, rewards) = pendingRewards(id, amount);

        _burn(msg.sender, id, amount);

        /// Claim and withdraw LP from escrow contract
        IPoolEscrow(escrow).withdrawLpToken(amount, msg.sender);

        uint256 rewardTokensLength = rewardTokens.length;
        for (uint256 i; i < rewardTokensLength; ++i) {
            address _rewardToken = rewardTokens[i];

            IPoolEscrow(escrow).transferToken(_rewardToken, msg.sender, rewards[i]);
        }
    }

    /// Returns pending rewards from the farming pool
    /// @param tokenId Token Id
    /// @param amount Amount of share
    /// @return tokens An array of token addresses for rewards
    /// @return rewards An array of pending rewards corresponding to the tokens
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    ) public view override returns (address[] memory tokens, uint256[] memory rewards) {
        (uint256 pid, uint256 stCrvPerShare) = decodeId(tokenId);
        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();
        uint256 _extraRewardsCount = extraRewardsLength(pid);
        tokens = new address[](_extraRewardsCount + 2);
        rewards = new uint256[](_extraRewardsCount + 2);

        /// CRV reward
        tokens[0] = IRewarder(cvxRewarder).rewardToken();
        rewards[0] = _getPendingReward(stCrvPerShare, cvxRewarder, amount, lpDecimals);

        /// CVX reward
        tokens[1] = address(cvxToken);
        rewards[1] = _getAllocatedCVX(pid, stCrvPerShare, amount);

        for (uint256 i; i < _extraRewardsCount; ++i) {
            address rewarder = getExtraRewarder(pid, i);
            uint256 stRewardPerShare = accExtPerShare[tokenId][rewarder];
            tokens[i + 2] = IRewarder(rewarder).rewardToken();
            if (stRewardPerShare == 0) {
                rewards[i + 2] = 0;
            } else {
                rewards[i + 2] = _getPendingReward(
                    stRewardPerShare == type(uint256).max ? 0 : stRewardPerShare,
                    rewarder,
                    amount,
                    lpDecimals
                );
            }
        }
    }

    /// @notice Fetch the underlying ERC20 token of the given ERC1155 token id.
    /// @param id Token id.
    /// @return uToken Address of the underlying ERC20 token.
    function getUnderlyingToken(uint256 id) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /// @notice Gets the escrow contract address for a given PID
    /// @param pid The pool ID
    /// @return escrowAddress Escrow associated with the given PID
    function getEscrow(uint256 pid) public view returns (address escrowAddress) {
        return escrows[pid];
    }

    /// @notice Fetch pool information from the Convex Booster.
    /// @param pid Convex pool id.
    /// @return lptoken Address of the liquidity provider token.
    /// @return token Address of the reward token.
    /// @return gauge Address of the gauge contract.
    /// @return crvRewards Address of the Curve rewards contract.
    /// @return stash Address of the stash contract.
    /// @return shutdown Indicates if the pool is shutdown.
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        public
        view
        returns (address lptoken, address token, address gauge, address crvRewards, address stash, bool shutdown)
    {
        return cvxBooster.poolInfo(pid);
    }

    /// @notice Get the full set of extra rewards.
    /// @return An array containing the addresses of extra reward tokens.
    function extraRewardsLength(uint256 pid) public view returns (uint256) {
        return _extraRewards[pid].length();
    }

    function getExtraRewarder(uint256 pid, uint256 index) public view returns (address) {
        return _extraRewards[pid].at(index);
    }

    /// @notice Get pending reward amount
    /// @param stRewardPerShare reward per share
    /// @param rewarder Address of rewarder contract
    /// @param amount lp amount
    /// @param lpDecimals lp decimals
    function _getPendingReward(
        uint256 stRewardPerShare,
        address rewarder,
        uint256 amount,
        uint256 lpDecimals
    ) internal view returns (uint256 rewards) {
        uint256 enRewardPerShare = IRewarder(rewarder).rewardPerToken();
        uint256 share = enRewardPerShare > stRewardPerShare ? enRewardPerShare - stRewardPerShare : 0;
        rewards = (share * amount) / (10 ** lpDecimals);
    }

    /// Calculates the CVX pending reward based on CRV reward
    /// @param crvAmount Amount of CRV reward
    /// @return mintAmount The pending CVX reward
    function _getCvxPendingReward(uint256 crvAmount) internal view returns (uint256 mintAmount) {
        if (crvAmount == 0) return 0;
        /// CVX token mint logic
        uint256 totalCliffs = cvxToken.totalCliffs();
        uint256 totalSupply = cvxToken.totalSupply();
        uint256 maxSupply = cvxToken.maxSupply();
        uint256 reductionPerCliff = cvxToken.reductionPerCliff();
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

    function _getAllocatedCVX(
        uint256 pid,
        uint256 stCrvPerShare,
        uint256 amount
    ) internal view returns (uint256 mintAmount) {
        address escrow = escrows[pid];

        (address lpToken, , , address crvRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 currentDeposits = IRewarder(crvRewarder).balanceOf(address(escrow));

        if (currentDeposits == 0) {
            return 0;
        }

        uint256 cvxPerShare = cvxPerShareByPid[pid] - cvxPerShareDebt[encodeId(pid, stCrvPerShare)];

        uint256 lastCrvPerToken = lastCrvPerTokenByPid[pid];

        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();
        uint256 earned = _getPendingReward(lastCrvPerToken, crvRewarder, currentDeposits, lpDecimals);

        if (earned != 0) {
            uint256 cvxReward = _getCvxPendingReward(earned);

            cvxPerShare += (cvxReward * 1e18) / currentDeposits;
        }

        return (cvxPerShare * amount) / 1e18;
    }

    function _setAccExtPerShare(uint256 tokenId, address rewarder) internal {
        uint256 rewardPerToken = IRewarder(rewarder).rewardPerToken();
        accExtPerShare[tokenId][rewarder] = rewardPerToken == 0 ? type(uint).max : rewardPerToken;
    }

    function _syncExtraRewards(uint256 pid, uint256 tokenId, address rewarder) internal returns (bool mismatchFound) {
        EnumerableSetUpgradeable.AddressSet storage rewards = _extraRewards[pid];
        if (!rewards.contains(rewarder)) {
            rewards.add(rewarder);
            _setAccExtPerShare(tokenId, rewarder);
            return true;
        }
        return false;
    }

    /// @notice Private function to update convex rewards
    /// @param pid The ID of the Convex pool.
    /// @dev Claims rewards and updates cvxPerShareByPid accordingly
    function _updateCvxReward(uint256 pid) private {
        address escrow = escrows[pid];

        (, , , address crvRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 currentDeposits = IRewarder(crvRewarder).balanceOf(escrow);

        lastCrvPerTokenByPid[pid] = IRewarder(crvRewarder).rewardPerToken();

        if (currentDeposits == 0) return;

        uint256 cvxBalBefore = cvxToken.balanceOf(escrow);

        /// @dev Claim extra rewards at withdrawal
        IRewarder(crvRewarder).getReward(escrow, false);

        uint256 cvxReward = cvxToken.balanceOf(escrow) - cvxBalBefore;

        _getExtraRewards(pid, escrow);

        if (cvxReward > 0) cvxPerShareByPid[pid] += (cvxReward * 1e18) / currentDeposits;
    }

    function _getExtraRewards(uint256 pid, address escrow) internal {
        uint256 currentExtraRewardsCount = _extraRewards[pid].length();
        for (uint256 i; i < currentExtraRewardsCount; ++i) {
            address extraRewarder = _extraRewards[pid].at(i);
            ICvxExtraRewarder(extraRewarder).getReward(escrow);
        }
    }

    /**
     * @notice Verifies that the provided token id is unique and has not been minted yet
     * @param id The token id to validate
     */
    function _validateTokenId(uint256 id) internal view {
        if (balanceOf(msg.sender, id) != 0) {
            revert Errors.DUPLICATE_TOKEN_ID(id);
        }
    }
}
