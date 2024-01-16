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
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
/* solhint-enable max-line-length */

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseWrapper } from "./BaseWrapper.sol";

import { ICvxExtraRewarder } from "../interfaces/convex/ICvxExtraRewarder.sol";
import { IConvex } from "../interfaces/convex/IConvex.sol";
import { IPoolEscrowFactory } from "./escrow/interfaces/IPoolEscrowFactory.sol";
import { IPoolEscrow } from "./escrow/interfaces/IPoolEscrow.sol";
import { IRewarder } from "../interfaces/convex/IRewarder.sol";
import { IWConvexBooster, ICvxBooster } from "../interfaces/IWConvexBooster.sol";

/* solhint-enable max-line-length */

/**
 * @title WConvexBooster
 * @author BlueberryProtocol
 * @notice Wrapped Convex Booster is the wrapper of LP positions.
 * @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank
 *     and do not generate yields. LP Tokens are identified by tokenIds
 *    encoded from lp token address.
 */
contract WConvexBooster is IWConvexBooster, BaseWrapper, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to Convex Pools contract
    ICvxBooster private _cvxBooster;
    /// @dev Address to CVX token
    IConvex private _cvxToken;
    /// @dev Address of the escrow factory
    IPoolEscrowFactory private _escrowFactory;
    /// @dev Mapping from token id to initialTokenPerShare
    mapping(uint256 => mapping(address => uint256)) private _initialTokenPerShare;
    /// @dev CVX reward per share by pid
    mapping(uint256 => uint256) private _cvxPerShareByPid;
    /// token id => cvxPerShareDebt;
    mapping(uint256 => uint256) private _cvxPerShareDebt;
    /// @dev pid => last crv reward per token
    mapping(uint256 => uint256) private _lastCrvPerTokenByPid;
    /// @dev pid => escrow contract address
    mapping(uint256 => address) private _escrows;
    /// @dev pid => A set of extra rewarders
    mapping(uint256 => EnumerableSetUpgradeable.AddressSet) private _extraRewards;
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes contract with dependencies.
     * @param cvx Address of the CVX token.
     * @param cvxBooster Address of the Convex Booster.
     * @param escrowFactory Address of the escrow factory.
     * @param owner The owner of the contract.
     */
    function initialize(address cvx, address cvxBooster, address escrowFactory, address owner) external initializer {
        if (cvx == address(0) || cvxBooster == address(0) || escrowFactory == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("wConvexBooster");
        _escrowFactory = IPoolEscrowFactory(escrowFactory);
        _cvxToken = IConvex(cvx);
        _cvxBooster = ICvxBooster(cvxBooster);
    }

    /// @notice IWConvexBooster
    function encodeId(uint256 pid, uint256 cvxPerShare) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (cvxPerShare >= (1 << 240)) {
            revert Errors.BAD_REWARD_PER_SHARE(cvxPerShare);
        }
        return (pid << 240) | cvxPerShare;
    }

    /// @notice IWConvexBooster
    function decodeId(uint256 id) public pure returns (uint256 pid, uint256 cvxPerShare) {
        pid = id >> 240; // Extract the first 16 bits
        cvxPerShare = id & ((1 << 240) - 1); // Extract the last 240 bits
    }

    /// @notice IWConvexBooster
    function mint(uint256 pid, uint256 amount) external nonReentrant returns (uint256 id) {
        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(pid);

        /// Escrow deployment/get logic
        address escrow = getEscrow(pid);

        if (escrow == address(0)) {
            escrow = _escrowFactory.createEscrow(pid, cvxRewarder, lpToken);
            _escrows[pid] = escrow;
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
                _setInitialTokenPerShare(id, extraRewarder);
            }
        }

        _cvxPerShareDebt[id] = _cvxPerShareByPid[pid];

        emit Minted(id, pid, amount);
    }

    /// @notice IWConvexBooster
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

        emit Burned(id, pid, amount);
    }

    /// @notice IWConvexBooster
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    ) public view override returns (address[] memory tokens, uint256[] memory rewards) {
        (uint256 pid, uint256 originalCrvPerShare) = decodeId(tokenId);
        (address lpToken, , , address cvxRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();

        uint256 _extraRewardsCount = extraRewardsLength(pid);
        tokens = new address[](_extraRewardsCount + 2);
        rewards = new uint256[](_extraRewardsCount + 2);

        /// CRV reward
        tokens[0] = IRewarder(cvxRewarder).rewardToken();
        rewards[0] = _getPendingReward(originalCrvPerShare, cvxRewarder, amount, lpDecimals);

        /// CVX reward
        tokens[1] = address(_cvxToken);
        rewards[1] = _calcAllocatedCVX(pid, originalCrvPerShare, amount);

        for (uint256 i; i < _extraRewardsCount; ++i) {
            address rewarder = getExtraRewarder(pid, i);
            uint256 stRewardPerShare = _initialTokenPerShare[tokenId][rewarder];
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

    /// @inheritdoc IWConvexBooster
    function getCvxBooster() public view override returns (ICvxBooster) {
        return _cvxBooster;
    }

    /// @inheritdoc IWConvexBooster
    function getCvxToken() public view override returns (IConvex) {
        return _cvxToken;
    }

    /// @inheritdoc IWConvexBooster
    function getEscrowFactory() public view override returns (IPoolEscrowFactory) {
        return _escrowFactory;
    }

    /// @notice IERC20Wrapper
    function getUnderlyingToken(uint256 id) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /// @notice IWConvexBooster
    function getEscrow(uint256 pid) public view override returns (address escrowAddress) {
        return _escrows[pid];
    }

    /// @notice IWConvexBooster
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        public
        view
        returns (address lptoken, address token, address gauge, address crvRewards, address stash, bool shutdown)
    {
        return getCvxBooster().poolInfo(pid);
    }

    /// @notice IWConvexBooster
    function extraRewardsLength(uint256 pid) public view returns (uint256) {
        return _extraRewards[pid].length();
    }

    /// @notice IWConvexBooster
    function getExtraRewarder(uint256 pid, uint256 index) public view returns (address) {
        return _extraRewards[pid].at(index);
    }

    /// @notice IWConvexBooster
    function getInitialTokenPerShare(uint256 tokenId, address token) external view override returns (uint256) {
        return _initialTokenPerShare[tokenId][token];
    }

    /**
     * @notice Gets pending reward amount
     * @param stRewardPerShare Get pending reward amount
     * @param rewarder Address of rewarder contract
     * @param amount lp amount
     * @param lpDecimals lp decimals
     */
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

    /**
     * @notice Calculates the CVX pending reward based on CRV reward
     * @param crvAmount Amount of CRV reward
     * @return mintAmount The pending CVX reward
     */
    function _getCvxPendingReward(uint256 crvAmount) internal view returns (uint256 mintAmount) {
        if (crvAmount == 0) return 0;

        IConvex cvxToken = getCvxToken();

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

    /**
     * @notice Calculate the amount of AURA allocated for a given LP amount.
     * @param pid The pool ID representing the specific Aura pool.
     * @param originalCrvPerShare The cached value of AURA per share at the time of opening the position.
     * @param amount Amount of LP tokens to calculate the AURA allocation for.
     */
    function _calcAllocatedCVX(
        uint256 pid,
        uint256 originalCrvPerShare,
        uint256 amount
    ) internal view returns (uint256 mintAmount) {
        address escrow = getEscrow(pid);

        (address lpToken, , , address crvRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 currentDeposits = IRewarder(crvRewarder).balanceOf(address(escrow));

        if (currentDeposits == 0) {
            return 0;
        }

        uint256 cvxPerShare = _cvxPerShareByPid[pid] - _cvxPerShareDebt[encodeId(pid, originalCrvPerShare)];

        uint256 lastCrvPerToken = _lastCrvPerTokenByPid[pid];

        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();
        uint256 earned = _getPendingReward(lastCrvPerToken, crvRewarder, currentDeposits, lpDecimals);

        if (earned != 0) {
            uint256 cvxReward = _getCvxPendingReward(earned);

            cvxPerShare += (cvxReward * Constants.PRICE_PRECISION) / currentDeposits;
        }

        return (cvxPerShare * amount) / Constants.PRICE_PRECISION;
    }

    /**
     * @notice Sets the initial token per share for a given token ID and rewarder.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     * @param extraRewarder The address of the extra rewarder to set the initial token per share for.
     */
    function _setInitialTokenPerShare(uint256 tokenId, address extraRewarder) internal {
        uint256 rewardPerToken = IRewarder(extraRewarder).rewardPerToken();
        _initialTokenPerShare[tokenId][extraRewarder] = rewardPerToken == 0 ? type(uint).max : rewardPerToken;
    }

    /**
     * @notice Checks if an extra reward has been synced for a given poolId or not.
     * @dev If the extra rewarder has not been synced yet, it will be added to the set
     * @param pid The pool ID representing the specific Convex pool..
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     * @param rewarder The address of the extra rewarder to sync.
     */
    function _syncExtraRewards(uint256 pid, uint256 tokenId, address rewarder) internal returns (bool mismatchFound) {
        EnumerableSetUpgradeable.AddressSet storage rewards = _extraRewards[pid];
        if (!rewards.contains(rewarder)) {
            rewards.add(rewarder);
            _setInitialTokenPerShare(tokenId, rewarder);
            return true;
        }
        return false;
    }

    /**
     * @notice Private function to update convex rewards
     * @dev Claims rewards and updates cvxPerShareByPid accordingly
     * @param pid The ID of the Convex pool.
     */
    function _updateCvxReward(uint256 pid) private {
        IConvex cvxToken = getCvxToken();
        address escrow = getEscrow(pid);

        (, , , address crvRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 currentDeposits = IRewarder(crvRewarder).balanceOf(escrow);

        _lastCrvPerTokenByPid[pid] = IRewarder(crvRewarder).rewardPerToken();

        if (currentDeposits == 0) return;

        uint256 cvxBalBefore = cvxToken.balanceOf(escrow);

        /// @dev Claim extra rewards at withdrawal
        IRewarder(crvRewarder).getReward(escrow, false);

        uint256 cvxReward = cvxToken.balanceOf(escrow) - cvxBalBefore;

        _claimExtraRewards(pid, escrow);

        if (cvxReward > 0) _cvxPerShareByPid[pid] += (cvxReward * Constants.PRICE_PRECISION) / currentDeposits;
    }

    /**
     * @notice Claims extra rewards for a given pool ID.
     * @param pid The pool ID representing the specific Aura pool.
     * @param escrow Address of the escrow contract.
     */
    function _claimExtraRewards(uint256 pid, address escrow) internal {
        uint256 currentExtraRewardsCount = _extraRewards[pid].length();
        for (uint256 i; i < currentExtraRewardsCount; ++i) {
            address extraRewarder = _extraRewards[pid].at(i);
            ICvxExtraRewarder(extraRewarder).getReward(escrow);
        }
    }
}
