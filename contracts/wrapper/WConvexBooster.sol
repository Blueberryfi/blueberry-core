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
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { FixedPointMathLib } from "../libraries/FixedPointMathLib.sol";
/* solhint-enable max-line-length */

import "../utils/BlueberryErrors.sol" as Errors;

import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IConvex } from "../interfaces/convex/IConvex.sol";
import { ICvxBooster } from "../interfaces/convex/ICvxBooster.sol";
import { ICvxStashToken } from "../interfaces/convex/ICvxStashToken.sol";
import { ICvxExtraRewarder } from "../interfaces/convex/ICvxExtraRewarder.sol";
import { IPoolEscrow } from "./escrow/interfaces/IPoolEscrow.sol";
import { IPoolEscrowFactory } from "./escrow/interfaces/IPoolEscrowFactory.sol";
import { IRewarder } from "../interfaces/convex/IRewarder.sol";
import { ITokenWrapper } from "../interfaces/convex/ITokenWrapper.sol";
import { IWConvexBooster } from "../interfaces/IWConvexBooster.sol";

/**
 * @title WConvexBooster
 * @author BlueberryProtocol
 * @notice Wrapped Convex Booster is the wrapper of LP positions
 * @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank
 *      and do not generate yields. LP Tokens are identified by tokenIds
 *      encoded from lp token address.
 */
contract WConvexBooster is IWConvexBooster, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to Convex token
    IConvex private _cvxToken;
    /// @dev Address of the Convex Booster contract
    ICvxBooster private _cvxBooster;
    /// @dev Address of the escrow factory
    IPoolEscrowFactory private _escrowFactory;
    /// @dev Mapping from token id to initialTokenPerShare
    mapping(uint256 => mapping(address => uint256)) private _initialTokenPerShare;
    /// @dev Convex reward per share by pid
    mapping(uint256 => uint256) private _cvxPerShareByPid;
    /// token id => cvxPerShareDebt;
    mapping(uint256 => uint256) private _cvxPerShareDebt;
    /// @dev pid => escrow contract address
    mapping(uint256 => address) private _escrows;
    /// @dev pid => stash token data
    mapping(uint256 => StashTokenInfo) private _stashTokenInfo;
    /// @dev pid => A set of extra rewarders
    mapping(uint256 => EnumerableSetUpgradeable.AddressSet) private _extraRewards;
    /// @dev pid => packed balances
    mapping(uint256 => uint256) private _packedBalances;

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

    /// @inheritdoc IWConvexBooster
    function encodeId(uint256 pid, uint256 crvPerShare) public pure returns (uint256 id) {
        // Ensure the pool id and crvPerShare are within expected bounds
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (crvPerShare >= (1 << 240)) revert Errors.BAD_REWARD_PER_SHARE(crvPerShare);
        return (pid << 240) | crvPerShare;
    }

    /// @inheritdoc IWConvexBooster
    function decodeId(uint256 id) public pure returns (uint256 gid, uint256 crvPerShare) {
        gid = id >> 240; // Extracting the first 16 bits
        crvPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    /// @inheritdoc IWConvexBooster
    function mint(uint256 pid, uint256 amount) external nonReentrant returns (uint256 id) {
        (address lpToken, , , address convexRewarder, , ) = getPoolInfoFromPoolId(pid);
        /// Escrow deployment/get logic
        address escrow = getEscrow(pid);

        if (escrow == address(0)) {
            escrow = _escrowFactory.createEscrow(pid, address(_cvxBooster), convexRewarder, lpToken);
            _escrows[pid] = escrow;
        }

        IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, escrow, amount);

        _updateConvexReward(pid, 0);

        /// Deposit LP from escrow contract
        IPoolEscrow(escrow).deposit(amount);

        /// crv reward handle logic
        uint256 crvRewardPerToken = IRewarder(convexRewarder).rewardPerToken();
        id = encodeId(pid, crvRewardPerToken);

        _mint(msg.sender, id, amount, "");

        // Store extra rewards info
        uint256 extraRewardsCount = IRewarder(convexRewarder).extraRewardsLength();
        for (uint256 i; i < extraRewardsCount; ++i) {
            address extraRewarder = IRewarder(convexRewarder).extraRewards(i);
            bool mismatchFound = _syncExtraRewards(_extraRewards[pid], id, extraRewarder);

            if (!mismatchFound) {
                _setInitialTokenPerShare(id, extraRewarder);
            }
        }

        _cvxPerShareDebt[id] = _cvxPerShareByPid[pid];

        emit Minted(id, pid, amount);
    }

    /// @inheritdoc IWConvexBooster
    function burn(
        uint256 id,
        uint256 amount
    ) external nonReentrant returns (address[] memory rewardTokens, uint256[] memory rewards) {
        (uint256 pid, ) = decodeId(id);
        address escrow = getEscrow(pid);
        // @dev sanity check
        assert(escrow != address(0));

        _updateConvexReward(pid, id);

        (rewardTokens, rewards) = pendingRewards(id, amount);

        _burn(msg.sender, id, amount);

        (uint256 lastCrvPerToken, uint256 cvxBalance) = _unpackBalances(_packedBalances[pid]);

        /// Claim and withdraw LP from escrow contract
        IPoolEscrow(escrow).withdrawLpToken(amount, msg.sender);

        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ++i) {
            address _rewardToken = rewardTokens[i];
            uint256 rewardAmount = rewards[i];

            if (rewardAmount == 0) {
                continue;
            }

            if (_rewardToken == address(getCvxToken())) {
                cvxBalance -= rewardAmount;
            }

            IPoolEscrow(escrow).transferToken(_rewardToken, msg.sender, rewardAmount);
        }

        _packedBalances[pid] = _packBalances(lastCrvPerToken, cvxBalance);

        emit Burned(id, pid, amount);
    }

    /// @inheritdoc IERC20Wrapper
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    ) public view override returns (address[] memory tokens, uint256[] memory rewards) {
        (uint256 pid, uint256 originalCrvPerShare) = decodeId(tokenId);

        address stashToken = _stashTokenInfo[pid].stashToken;

        uint256 extraRewardsCount = extraRewardsLength(pid);
        tokens = new address[](extraRewardsCount + 2);
        rewards = new uint256[](extraRewardsCount + 2);

        // CVX reward
        {
            (, , , address convexRewarder, , ) = getPoolInfoFromPoolId(pid);
            /// CVX reward
            tokens[0] = IRewarder(convexRewarder).rewardToken();
            rewards[0] = _getPendingReward(originalCrvPerShare, convexRewarder, amount);
        }
        // Convex reward
        tokens[1] = address(getCvxToken());
        rewards[1] = _calcAllocatedConvex(pid, originalCrvPerShare, amount);

        // This index is used to make sure that there is no gap in the returned array
        uint256 index = 0;
        bool stashTokenFound = false;
        // Additional rewards
        for (uint256 i; i < extraRewardsCount; ++i) {
            address rewarder = _extraRewards[pid].at(i);
            address rewardToken = IRewarder(rewarder).rewardToken();

            if (rewardToken == stashToken) {
                stashTokenFound = true;
                continue;
            }

            // From pool 151 onwards, extra reward tokens are wrapped
            if (pid >= 151) {
                rewardToken = ITokenWrapper(rewardToken).token();
            }

            uint256 tokenRewardPerShare = _initialTokenPerShare[tokenId][rewarder];
            tokens[index + 2] = rewardToken;

            if (tokenRewardPerShare == 0) {
                rewards[index + 2] = 0;
            } else {
                rewards[index + 2] = _getPendingReward(
                    tokenRewardPerShare == type(uint).max ? 0 : tokenRewardPerShare,
                    rewarder,
                    amount
                );
            }

            index++;
        }

        if (stashTokenFound) {
            assembly {
                mstore(tokens, sub(mload(tokens), 1))
                mstore(rewards, sub(mload(rewards), 1))
            }
        }
    }

    /// @inheritdoc IWConvexBooster
    function syncExtraRewards(uint256 pid, uint256 tokenId) public override {
        (, , , address rewarder, , ) = getPoolInfoFromPoolId(pid);
        EnumerableSetUpgradeable.AddressSet storage rewards = _extraRewards[pid];
        uint256 extraRewardsCount = IRewarder(rewarder).extraRewardsLength();
        for (uint256 i; i < extraRewardsCount; ++i) {
            address extraRewarder = IRewarder(rewarder).extraRewards(i);
            bool mismatchFound = _syncExtraRewards(rewards, tokenId, extraRewarder);

            if (!mismatchFound && _initialTokenPerShare[tokenId][extraRewarder] == type(uint).max) {
                uint256 rewardPerToken = IRewarder(extraRewarder).rewardPerToken();

                if (rewardPerToken != 0) {
                    _initialTokenPerShare[tokenId][extraRewarder] = rewardPerToken;
                }
            }
        }
    }

    /// @inheritdoc IWConvexBooster
    function getCvxToken() public view override returns (IConvex) {
        return _cvxToken;
    }

    /// @inheritdoc IWConvexBooster
    function getCvxBooster() public view override returns (ICvxBooster) {
        return _cvxBooster;
    }

    /// @inheritdoc IWConvexBooster
    function getEscrowFactory() public view override returns (IPoolEscrowFactory) {
        return _escrowFactory;
    }

    /// @inheritdoc IWConvexBooster
    function getEscrow(uint256 pid) public view override returns (address escrowAddress) {
        return _escrows[pid];
    }

    /// @inheritdoc IWConvexBooster
    function extraRewardsLength(uint256 pid) public view override returns (uint256) {
        return _extraRewards[pid].length();
    }

    /// @inheritdoc IWConvexBooster
    function getExtraRewarder(uint256 pid, uint256 index) public view override returns (address) {
        return _extraRewards[pid].at(index);
    }

    function getInitialTokenPerShare(uint256 tokenId, address token) external view override returns (uint256) {
        return _initialTokenPerShare[tokenId][token];
    }

    /// @inheritdoc IWConvexBooster
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        public
        view
        returns (address lptoken, address token, address gauge, address convexRewards, address stash, bool shutdown)
    {
        return getCvxBooster().poolInfo(pid);
    }

    /// @inheritdoc IERC20Wrapper
    function getUnderlyingToken(uint256 id) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /**
     * @notice Calculate the amount of pending reward for a given LP amount.
     * @param originalRewardPerShare The cached value of Crv per share at the time of opening the position.
     * @param rewarder The address of the rewarder contract.
     * @param amount The calculated reward amount.
     */
    function _getPendingReward(
        uint256 originalRewardPerShare,
        address rewarder,
        uint256 amount
    ) internal view returns (uint256 rewards) {
        /// Retrieve current reward per token from rewarder
        uint256 currentRewardPerShare = IRewarder(rewarder).rewardPerToken();

        /// Calculate the difference in reward per share
        uint256 share = currentRewardPerShare > originalRewardPerShare
            ? currentRewardPerShare - originalRewardPerShare
            : 0;

        /// Calculate the total rewards base on share and amount.
        rewards = share.mulWadDown(amount);
    }

    /**
     * @notice Calculate the amount of Convex allocated for a given LP amount.
     * @param pid The pool ID representing the specific Convex pool.
     * @param originalCrvPerShare The cached value of CRV per share at the time of opening the position.
     * @param amount Amount of LP tokens to calculate the Convex allocation for.
     */
    function _calcAllocatedConvex(
        uint256 pid,
        uint256 originalCrvPerShare,
        uint256 amount
    ) internal view returns (uint256 mintAmount) {
        address escrow = getEscrow(pid);
        (, , , address convexRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 currentDeposits = IRewarder(convexRewarder).balanceOf(escrow);

        if (currentDeposits == 0) {
            return 0;
        }

        uint256 cvxPerShare = _cvxPerShareByPid[pid] - _cvxPerShareDebt[encodeId(pid, originalCrvPerShare)];

        return cvxPerShare.mulWadDown(amount);
    }

    /**
     * @notice Updates the cvxPerShareByPid value for a given pool ID.
     * @dev Claims rewards and updates cvxPerShareByPid accordingly
     * @param pid The pool ID representing the specific Convex pool.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     */
    function _updateConvexReward(uint256 pid, uint256 tokenId) private {
        StashTokenInfo storage stashTokenInfo = _stashTokenInfo[pid];
        IConvex cvxToken = getCvxToken();
        address escrow = getEscrow(pid);
        address stashToken = stashTokenInfo.stashToken;

        // _convexRewarder rewards users in Convex
        (, , , address _convexRewarder, address stashConvex, ) = getPoolInfoFromPoolId(pid);
        uint256 lastCrvPerToken = IRewarder(_convexRewarder).rewardPerToken();

        // If the token is not minted yet the tokenId will be 0
        //   and rewards will be synced later
        if (tokenId != 0) {
            syncExtraRewards(pid, tokenId);
        }

        if (stashToken == address(0)) {
            _setConvexStashToken(stashTokenInfo, _convexRewarder, stashConvex);
        }

        uint256 currentDeposits = IRewarder(_convexRewarder).balanceOf(escrow);

        if (currentDeposits == 0) {
            _packedBalances[pid] = _packBalances(lastCrvPerToken, cvxToken.balanceOf(escrow));
            return;
        }

        (, uint256 cvxPreBalance) = _unpackBalances(_packedBalances[pid]);

        IRewarder(_convexRewarder).getReward(escrow, false);

        _claimExtraRewards(pid, escrow);

        uint256 cvxPostBalance = cvxToken.balanceOf(escrow);
        uint256 cvxReceived = cvxPostBalance - cvxPreBalance;

        if (cvxReceived > 0) {
            _cvxPerShareByPid[pid] += cvxReceived.divWadDown(currentDeposits);
        }

        _packedBalances[pid] = _packBalances(lastCrvPerToken, cvxPostBalance);
    }

    /**
     * @notice Packs the Convex balance and the lastCrvPerToken into a single uint256 value
     * @param lastCrvPerToken Bal per token staked at the time of the last update
     * @param cvxBalance The escrows Convex balance at the time of the last update
     * @return packedBalance The packed balance
     */
    function _packBalances(uint256 lastCrvPerToken, uint256 cvxBalance) internal pure returns (uint256) {
        return (lastCrvPerToken << 128) | cvxBalance;
    }

    /**
     * @notice Unpacks the packed balance
     * @param packedBalance The packed balance
     * @return lastCrvPerToken CRV per token staked at the time of the last update
     * @return cvxBalance The escrows Convex balance at the time of the last update
     */
    function _unpackBalances(
        uint256 packedBalance
    ) internal pure returns (uint256 lastCrvPerToken, uint256 cvxBalance) {
        lastCrvPerToken = packedBalance >> 128;
        cvxBalance = packedBalance & ((1 << 128) - 1);
    }

    /**
     * @notice Claims extra rewards from their respective rewarder contract
     * @param pid The pool ID representing the specific Convex pool.
     * @param escrow The escrow contract address
     */
    function _claimExtraRewards(uint256 pid, address escrow) internal {
        uint256 currentExtraRewardsCount = extraRewardsLength(pid);
        for (uint256 i; i < currentExtraRewardsCount; ++i) {
            address extraRewarder = getExtraRewarder(pid, i);
            ICvxExtraRewarder(extraRewarder).getReward(escrow);
        }
    }

    /**
     * @notice Sets the Convex Stash token
     * @param convexRewarder Address of the Convex Rewarder
     * @param stashConvex Address of the stash Convex
     */
    function _setConvexStashToken(
        StashTokenInfo storage stashTokenData,
        address convexRewarder,
        address stashConvex
    ) internal {
        uint256 length = IRewarder(convexRewarder).extraRewardsLength();
        for (uint256 i; i < length; ++i) {
            address _extraRewarder = IRewarder(convexRewarder).extraRewards(i);

            address _rewardToken = IRewarder(_extraRewarder).rewardToken();
            // Initialize the stashToken if it is not initialized
            if (_isConvexStashToken(_rewardToken, stashConvex)) {
                stashTokenData.stashToken = _rewardToken;
                stashTokenData.rewarder = _extraRewarder;
                break;
            }
        }
    }

    /**
     * @notice Sets the initial token per share for a given token ID and extra rewarder
     * @dev This allows the wrapper to track individual rewards for each user
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     * @param extraRewarder The address of the extra rewarder to set the initial token per share for.
     */
    function _setInitialTokenPerShare(uint256 tokenId, address extraRewarder) internal {
        uint256 rewardPerToken = IRewarder(extraRewarder).rewardPerToken();
        _initialTokenPerShare[tokenId][extraRewarder] = rewardPerToken == 0 ? type(uint).max : rewardPerToken;
    }

    /**
     * @notice Checks if an extra rewards has been synced for a given poolId or not.
     * @param rewards Cached set of extra rewards for a given pool ID.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     * @param rewarder The address of the extra rewarder to sync.
     */
    function _syncExtraRewards(
        EnumerableSetUpgradeable.AddressSet storage rewards,
        uint256 tokenId,
        address rewarder
    ) internal returns (bool mismatchFound) {
        if (!rewards.contains(rewarder)) {
            rewards.add(rewarder);
            _setInitialTokenPerShare(tokenId, rewarder);
            return true;
        }
        return false;
    }

    /**
     * @notice Checks if a token is an Convex Stash token
     * @param token Address of the token to check
     * @param convexStash Address of the Convex Stash
     */
    function _isConvexStashToken(address token, address convexStash) internal view returns (bool) {
        try ICvxStashToken(token).stash() returns (address stash) {
            return stash == convexStash;
        } catch {
            return false;
        }
    }
}
