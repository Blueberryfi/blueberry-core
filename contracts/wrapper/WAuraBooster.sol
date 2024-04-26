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

import { IWAuraBooster } from "../interfaces/IWAuraBooster.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IAura } from "../interfaces/aura/IAura.sol";
import { IAuraBooster } from "../interfaces/aura/IAuraBooster.sol";
import { ICvxExtraRewarder } from "../interfaces/convex/ICvxExtraRewarder.sol";
import { IBalancerVault } from "../interfaces/balancer-v2/IBalancerVault.sol";
import { IBalancerV2Pool } from "../interfaces/balancer-v2/IBalancerV2Pool.sol";
import { IPoolEscrow } from "./escrow/interfaces/IPoolEscrow.sol";
import { IPoolEscrowFactory } from "./escrow/interfaces/IPoolEscrowFactory.sol";
import { IRewarder } from "../interfaces/convex/IRewarder.sol";
import { IStashToken } from "../interfaces/aura/IStashToken.sol";

/**
 * @title WAuraBooster
 * @author BlueberryProtocol
 * @notice Wrapped Aura Booster is the wrapper of LP positions
 * @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank
 *      and do not generate yields. LP Tokens are identified by tokenIds
 *      encoded from lp token address.
 */
contract WAuraBooster is IWAuraBooster, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to AURA token
    IAura private _auraToken;
    /// @dev Address of the Aura Booster contract
    IAuraBooster private _auraBooster;
    /// @dev Address of the escrow factory
    IPoolEscrowFactory private _escrowFactory;
    /// @dev Address of the balancer vault
    IBalancerVault private _balancerVault;
    /// @dev Mapping from token id to initialTokenPerShare
    mapping(uint256 => mapping(address => uint256)) private _initialTokenPerShare;
    /// @dev AURA reward per share by pid
    mapping(uint256 => uint256) private _auraPerShareByPid;
    /// token id => auraPerShareDebt;
    mapping(uint256 => uint256) private _auraPerShareDebt;
    /// @dev pid => escrow contract address
    mapping(uint256 => address) private _escrows;
    /// @dev pid => stashAura token data
    mapping(uint256 => StashAuraInfo) private _stashAuraInfo;
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
     * @notice Initializes contract with dependencies
     * @param aura The AURA token address
     * @param auraBooster The auraBooster contract address
     * @param escrowFactory The escrow factory contract address
     * @param balancerVault The balancer vault contract address
     * @param owner The owner of the contract.
     */
    function initialize(
        address aura,
        address auraBooster,
        address escrowFactory,
        address balancerVault,
        address owner
    ) external initializer {
        if (
            aura == address(0) ||
            auraBooster == address(0) ||
            escrowFactory == address(0) ||
            balancerVault == address(0)
        ) {
            revert Errors.ZERO_ADDRESS();
        }

        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("wAuraBooster");

        _auraToken = IAura(aura);
        _escrowFactory = IPoolEscrowFactory(escrowFactory);
        _auraBooster = IAuraBooster(auraBooster);
        _balancerVault = IBalancerVault(balancerVault);
    }

    /// @inheritdoc IWAuraBooster
    function encodeId(uint256 pid, uint256 balPerShare) public pure returns (uint256 id) {
        // Ensure the pool id and auraPerShare are within expected bounds
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (balPerShare >= (1 << 240)) revert Errors.BAD_REWARD_PER_SHARE(balPerShare);
        return (pid << 240) | balPerShare;
    }

    /// @inheritdoc IWAuraBooster
    function decodeId(uint256 id) public pure returns (uint256 gid, uint256 balPerShare) {
        gid = id >> 240; // Extracting the first 16 bits
        balPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    /// @inheritdoc IWAuraBooster
    function mint(uint256 pid, uint256 amount) external nonReentrant returns (uint256 id) {
        (address lpToken, , , address auraRewarder, , ) = getPoolInfoFromPoolId(pid);
        /// Escrow deployment/get logic
        address escrow = getEscrow(pid);

        if (escrow == address(0)) {
            escrow = _escrowFactory.createEscrow(pid, address(_auraBooster), auraRewarder, lpToken);
            _escrows[pid] = escrow;
        }

        IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, escrow, amount);

        _updateAuraReward(pid, 0);

        /// Deposit LP from escrow contract
        IPoolEscrow(escrow).deposit(amount);

        /// BAL reward handle logic
        uint256 balRewardPerToken = IRewarder(auraRewarder).rewardPerToken();
        id = encodeId(pid, balRewardPerToken);

        _mint(msg.sender, id, amount, "");

        // Store extra rewards info
        uint256 extraRewardsCount = IRewarder(auraRewarder).extraRewardsLength();
        for (uint256 i; i < extraRewardsCount; ++i) {
            address extraRewarder = IRewarder(auraRewarder).extraRewards(i);
            bool mismatchFound = _syncExtraRewards(_extraRewards[pid], id, extraRewarder);

            if (!mismatchFound) {
                _setInitialTokenPerShare(id, extraRewarder);
            }
        }

        _auraPerShareDebt[id] = _auraPerShareByPid[pid];

        emit Minted(id, pid, amount);
    }

    /// @inheritdoc IWAuraBooster
    function burn(
        uint256 id,
        uint256 amount
    ) external nonReentrant returns (address[] memory rewardTokens, uint256[] memory rewards) {
        (uint256 pid, ) = decodeId(id);
        address escrow = getEscrow(pid);
        // @dev sanity check
        assert(escrow != address(0));

        _updateAuraReward(pid, id);

        (rewardTokens, rewards) = pendingRewards(id, amount);

        _burn(msg.sender, id, amount);

        (uint256 lastBalPerToken, uint256 auraBalance) = _unpackBalances(_packedBalances[pid]);

        /// Claim and withdraw LP from escrow contract
        IPoolEscrow(escrow).withdrawLpToken(amount, msg.sender);

        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ++i) {
            address _rewardToken = rewardTokens[i];
            uint256 rewardAmount = rewards[i];

            if (rewardAmount == 0) {
                continue;
            }

            if (_rewardToken == address(getAuraToken())) {
                auraBalance -= rewardAmount;
            }

            IPoolEscrow(escrow).transferToken(_rewardToken, msg.sender, rewardAmount);
        }

        _packedBalances[pid] = _packBalances(lastBalPerToken, auraBalance);

        emit Burned(id, pid, amount);
    }

    /// @inheritdoc IERC20Wrapper
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    ) public view override returns (address[] memory tokens, uint256[] memory rewards) {
        (uint256 pid, uint256 originalBalPerShare) = decodeId(tokenId);

        address stashAura = _stashAuraInfo[pid].stashAuraToken;

        uint256 extraRewardsCount = extraRewardsLength(pid);
        tokens = new address[](extraRewardsCount + 2);
        rewards = new uint256[](extraRewardsCount + 2);

        // BAL reward
        {
            (, , , address auraRewarder, , ) = getPoolInfoFromPoolId(pid);
            /// BAL reward
            tokens[0] = IRewarder(auraRewarder).rewardToken();
            rewards[0] = _getPendingReward(originalBalPerShare, auraRewarder, amount);
        }
        // AURA reward
        tokens[1] = address(getAuraToken());
        rewards[1] = _calcAllocatedAURA(pid, originalBalPerShare, amount);

        // This index is used to make sure that there is no gap in the returned array
        uint256 index = 0;
        bool stashAuraFound = false;
        // Additional rewards
        for (uint256 i; i < extraRewardsCount; ++i) {
            address rewarder = _extraRewards[pid].at(i);
            address rewardToken = IRewarder(rewarder).rewardToken();

            if (rewardToken == stashAura) {
                stashAuraFound = true;
                continue;
            }

            rewardToken = IStashToken(rewardToken).baseToken();

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

        if (stashAuraFound) {
            assembly {
                mstore(tokens, sub(mload(tokens), 1))
                mstore(rewards, sub(mload(rewards), 1))
            }
        }
    }

    /// @inheritdoc IWAuraBooster
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

    /// @inheritdoc IWAuraBooster
    function getAuraToken() public view override returns (IAura) {
        return _auraToken;
    }

    /// @inheritdoc IWAuraBooster
    function getAuraBooster() public view override returns (IAuraBooster) {
        return _auraBooster;
    }

    /// @inheritdoc IWAuraBooster
    function getEscrowFactory() public view override returns (IPoolEscrowFactory) {
        return _escrowFactory;
    }

    /// @inheritdoc IWAuraBooster
    function getBPTPoolId(address bpt) public view override returns (bytes32) {
        return IBalancerV2Pool(bpt).getPoolId();
    }

    /// @inheritdoc IWAuraBooster
    function getVault() public view override returns (IBalancerVault) {
        return _balancerVault;
    }

    /// @inheritdoc IWAuraBooster
    function getEscrow(uint256 pid) public view override returns (address escrowAddress) {
        return _escrows[pid];
    }

    /// @inheritdoc IWAuraBooster
    function extraRewardsLength(uint256 pid) public view override returns (uint256) {
        return _extraRewards[pid].length();
    }

    /// @inheritdoc IWAuraBooster
    function getExtraRewarder(uint256 pid, uint256 index) public view override returns (address) {
        return _extraRewards[pid].at(index);
    }

    function getInitialTokenPerShare(uint256 tokenId, address token) external view override returns (uint256) {
        return _initialTokenPerShare[tokenId][token];
    }

    /// @inheritdoc IWAuraBooster
    function getPoolInfoFromPoolId(
        uint256 pid
    )
        public
        view
        returns (address lptoken, address token, address gauge, address auraRewards, address stash, bool shutdown)
    {
        return getAuraBooster().poolInfo(pid);
    }

    /// @inheritdoc IWAuraBooster
    function getPoolTokens(
        address bpt
    ) external view returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangedBlock) {
        return getVault().getPoolTokens(getBPTPoolId(bpt));
    }

    /// @inheritdoc IERC20Wrapper
    function getUnderlyingToken(uint256 id) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /**
     * @notice Calculate the amount of pending reward for a given LP amount.
     * @param originalRewardPerShare The cached value of BAL per share at the time of opening the position.
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
     * @notice Calculate the amount of AURA allocated for a given LP amount.
     * @param pid The pool ID representing the specific Aura pool.
     * @param originalBalPerShare The cached value of AURA per share at the time of opening the position.
     * @param amount Amount of LP tokens to calculate the AURA allocation for.
     */
    function _calcAllocatedAURA(
        uint256 pid,
        uint256 originalBalPerShare,
        uint256 amount
    ) internal view returns (uint256 mintAmount) {
        address escrow = getEscrow(pid);
        (, , , address auraRewarder, , ) = getPoolInfoFromPoolId(pid);
        uint256 currentDeposits = IRewarder(auraRewarder).balanceOf(escrow);

        if (currentDeposits == 0) {
            return 0;
        }

        uint256 auraPerShare = _auraPerShareByPid[pid] - _auraPerShareDebt[encodeId(pid, originalBalPerShare)];

        return auraPerShare.mulWadDown(amount);
    }

    /**
     * @notice Updates the auraPerShareByPid value for a given pool ID.
     * @dev Claims rewards and updates auraPerShareByPid accordingly
     * @param pid The pool ID representing the specific Aura pool.
     * @param tokenId The ID of the ERC1155 token representing the staked position.
     */
    function _updateAuraReward(uint256 pid, uint256 tokenId) private {
        StashAuraInfo storage stashAuraInfo = _stashAuraInfo[pid];
        IAura auraToken = getAuraToken();
        address escrow = getEscrow(pid);
        address stashAuraToken = stashAuraInfo.stashAuraToken;

        // _auraRewarder rewards users in AURA
        (, , , address _auraRewarder, address stashAura, ) = getPoolInfoFromPoolId(pid);
        uint256 lastBalPerToken = IRewarder(_auraRewarder).rewardPerToken();

        // If the token is not minted yet the tokenId will be 0
        //   and rewards will be synced later
        if (tokenId != 0) {
            syncExtraRewards(pid, tokenId);
        }

        if (stashAuraToken == address(0)) {
            _setAuraStashToken(stashAuraInfo, _auraRewarder, stashAura);
        }

        uint256 currentDeposits = IRewarder(_auraRewarder).balanceOf(escrow);

        if (currentDeposits == 0) {
            _packedBalances[pid] = _packBalances(lastBalPerToken, auraToken.balanceOf(escrow));
            return;
        }

        (, uint256 auraPreBalance) = _unpackBalances(_packedBalances[pid]);

        IRewarder(_auraRewarder).getReward(escrow, false);

        _claimExtraRewards(pid, escrow);

        uint256 auraPostBalance = auraToken.balanceOf(escrow);
        uint256 auraReceived = auraPostBalance - auraPreBalance;

        if (auraReceived > 0) {
            _auraPerShareByPid[pid] += auraReceived.divWadDown(currentDeposits);
        }

        _packedBalances[pid] = _packBalances(lastBalPerToken, auraPostBalance);
    }

    /**
     * @notice Packs the Aura balance and the lastBalPerToken into a single uint256 value
     * @param lastBalPerToken Bal per token staked at the time of the last update
     * @param auraBalance The escrows AURA balance at the time of the last update
     * @return packedBalance The packed balance
     */
    function _packBalances(uint256 lastBalPerToken, uint256 auraBalance) internal pure returns (uint256) {
        return (lastBalPerToken << 128) | auraBalance;
    }

    /**
     * @notice Unpacks the packed balance
     * @param packedBalance The packed balance
     * @return lastBalPerToken Bal per token staked at the time of the last update
     * @return auraBalance The escrows AURA balance at the time of the last update
     */
    function _unpackBalances(
        uint256 packedBalance
    ) internal pure returns (uint256 lastBalPerToken, uint256 auraBalance) {
        lastBalPerToken = packedBalance >> 128;
        auraBalance = packedBalance & ((1 << 128) - 1);
    }

    /**
     * @notice Claims extra rewards from their respective rewarder contract
     * @param pid The pool ID representing the specific Aura pool.
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
     * @notice Sets the Aura Stash token
     * @param auraRewarder Address of the Aura Rewarder
     * @param stashAura Address of the stash Aura
     */
    function _setAuraStashToken(StashAuraInfo storage stashAuraData, address auraRewarder, address stashAura) internal {
        uint256 length = IRewarder(auraRewarder).extraRewardsLength();
        for (uint256 i; i < length; ++i) {
            address _extraRewarder = IRewarder(auraRewarder).extraRewards(i);

            address _rewardToken = IRewarder(_extraRewarder).rewardToken();
            // Initialize the stashAura if it is not initialized
            if (_isAuraStashToken(_rewardToken, stashAura)) {
                stashAuraData.stashAuraToken = _rewardToken;
                stashAuraData.rewarder = _extraRewarder;
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
     * @notice Checks if a token is an Aura Stash token
     * @param token Address of the token to check
     * @param auraStash Address of the Aura Stash
     */
    function _isAuraStashToken(address token, address auraStash) internal view returns (bool) {
        try IStashToken(token).stash() returns (address stash) {
            return stash == auraStash;
        } catch {
            return false;
        }
    }
}
