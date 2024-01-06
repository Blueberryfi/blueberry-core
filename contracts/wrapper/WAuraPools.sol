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

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";

import "../utils/BlueBerryErrors.sol" as Errors;

import {IWAuraPools} from "../interfaces/IWAuraPools.sol";
import {IERC20Wrapper} from "../interfaces/IERC20Wrapper.sol";
import {IAura} from "../interfaces/aura/IAura.sol";
import {IAuraBooster} from "../interfaces/aura/IAuraBooster.sol";
import {IAuraStashToken} from "../interfaces/aura/IAuraStashToken.sol";
import {ICvxExtraRewarder} from "../interfaces/convex/ICvxExtraRewarder.sol";
import {IBalancerVault} from "../interfaces/balancer/IBalancerVault.sol";
import {IBalancerPool} from "../interfaces/balancer/IBalancerPool.sol";
import {IPoolEscrow} from "./escrow/interfaces/IPoolEscrow.sol";
import {IPoolEscrowFactory} from "./escrow/interfaces/IPoolEscrowFactory.sol";
import {IRewarder} from "../interfaces/convex/IRewarder.sol";

/**
 * @title WauraPools
 * @author BlueberryProtocol
 * @notice Wrapped Aura Pools is the wrapper of LP positions
 * @dev Leveraged LP Tokens will be wrapped here and be held in BlueberryBank
 *      and do not generate yields. LP Tokens are identified by tokenIds
 *      encoded from lp token address.
 */
contract WAuraPools is
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    IERC20Wrapper,
    IWAuraPools
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using FixedPointMathLib for uint256;

    event Minted(uint256 pid, uint256 amount, address indexed user);

    event Burned(uint256 id, uint256 amount, address indexed user);

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to AURA token
    IAura public AURA;
    /// @dev Address of the Aura Booster contract
    IAuraBooster public auraBooster;
    /// @dev Address of the escrow factory
    IPoolEscrowFactory public escrowFactory;
    /// @dev Mapping from token id to accExtPerShare
    mapping(uint256 => mapping(address => uint256)) public accExtPerShare;
    /// @dev AURA reward per share by pid
    mapping(uint256 => uint256) public auraPerShareByPid;
    /// token id => auraPerShareDebt;
    mapping(uint256 => uint256) public auraPerShareDebt;
    /// @dev pid => escrow contract address
    mapping(uint256 => address) public escrows;
    /// @dev pid => stash token data
    mapping(uint256 => StashTokenInfo) public stashTokenInfo;
    /// @dev pid => A set of extra rewarders
    mapping(uint256 => EnumerableSetUpgradeable.AddressSet) private extraRewards;
    /// @dev pid => packed balances
    mapping(uint256 => uint256) private packedBalances;

    uint256 public REWARD_MULTIPLIER_DENOMINATOR;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes contract with dependencies
    /// @param aura_ The AURA token address
    /// @param auraBooster_ The auraBooster contract address
    /// @param escrowFactory_ The escrow factory contract address
    function initialize(
        address aura_,
        address auraBooster_,
        address escrowFactory_
    ) external initializer {
        if (
            aura_ == address(0) ||
            auraBooster_ == address(0) ||
            escrowFactory_ == address(0)
        ) {
            revert Errors.ZERO_ADDRESS();
        }
        __ReentrancyGuard_init();
        __ERC1155_init("WauraBooster");
        AURA = IAura(aura_);
        escrowFactory = IPoolEscrowFactory(escrowFactory_);
        auraBooster = IAuraBooster(auraBooster_);
        REWARD_MULTIPLIER_DENOMINATOR = auraBooster
            .REWARD_MULTIPLIER_DENOMINATOR();
    }

    /// @notice Encodes pool id and BAL per share into an ERC1155 token id
    /// @param pid The pool id (The first 16-bits)
    /// @param balPerShare Amount of BAL per share, multiplied by 1e18 (The last 240-bits)
    /// @return id The resulting ERC1155 token id
    function encodeId(
        uint256 pid,
        uint256 balPerShare
    ) public pure returns (uint256 id) {
        // Ensure the pool id and auraPerShare are within expected bounds
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (balPerShare >= (1 << 240))
            revert Errors.BAD_REWARD_PER_SHARE(balPerShare);
        return (pid << 240) | balPerShare;
    }

    /// @notice Decodes ERC1155 token id to pool id and BAL per share
    /// @param id The ERC1155 token id
    /// @return gid The decoded pool id
    /// @return balPerShare The decoded amount of BAL per share
    function decodeId(
        uint256 id
    ) public pure returns (uint256 gid, uint256 balPerShare) {
        gid = id >> 240; // Extracting the first 16 bits
        balPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    /// @notice Mint an ERC1155 token corresponding to the provided LP token amount.
    /// @param pid The ID of the AURA pool.
    /// @param amount The amount of the LP token to be wrapped.
    /// @return id The minted ERC1155 token's ID.
    function mint(
        uint256 pid,
        uint256 amount
    ) external nonReentrant returns (uint256 id) {
        (address lpToken, , , address auraRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        /// Escrow deployment/get logic
        address escrow;

        if (getEscrow(pid) == address(0)) {
            escrow = escrowFactory.createEscrow(pid, auraRewarder, lpToken);
            escrows[pid] = escrow;
        } else {
            escrow = escrows[pid];
        }

        IERC20Upgradeable(lpToken).safeTransferFrom(
            msg.sender,
            escrow,
            amount
        );

        _updateAuraReward(pid, 0);

        /// Deposit LP from escrow contract
        IPoolEscrow(escrow).deposit(amount);
        
        /// BAL reward handle logic
        uint256 balRewardPerToken = IRewarder(auraRewarder)
            .rewardPerToken();
        id = encodeId(pid, balRewardPerToken);

        _mint(msg.sender, id, amount, "");

        // Store extra rewards info
        uint256 extraRewardsCount = IRewarder(auraRewarder)
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsCount; ++i) {
            address extraRewarder = IRewarder(auraRewarder).extraRewards(i);
            bool mismatchFound = _syncExtraRewards(extraRewards[pid], id, extraRewarder);
            
            if (!mismatchFound) {
                _setAccExtPerShare(id, extraRewarder);
            }
        }

        auraPerShareDebt[id] += auraPerShareByPid[pid];

        emit Minted(pid, amount, msg.sender);
    }

    /// @notice Burn the provided ERC1155 token and redeem its underlying ERC20 token.
    /// @param id The ID of the ERC1155 token to burn.
    /// @param amount The amount of the ERC1155 token to burn.
    /// @return rewardTokens An array of reward tokens that the user is eligible to receive.
    /// @return rewards The corresponding amounts of reward tokens.
    function burn(
        uint256 id,
        uint256 amount
    )
        external
        nonReentrant
        returns (address[] memory rewardTokens, uint256[] memory rewards)
    {
        (uint256 pid, ) = decodeId(id);
        address escrow = getEscrow(pid);
        // @dev sanity check
        assert(escrow != address(0));

        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }

        _updateAuraReward(pid, id);

        (rewardTokens, rewards) = pendingRewards(id, amount);
        
        _burn(msg.sender, id, amount);

        (uint256 lastBalPerToken, uint256 auraBalance) = _unpackBalances(packedBalances[pid]);
        
        /// Claim and withdraw LP from escrow contract
        IPoolEscrow(escrow).withdrawLpToken(amount, msg.sender);
        
        uint256 rewardTokensLength = rewardTokens.length;

        for (uint256 i; i < rewardTokensLength; ++i) {
            address _rewardToken = rewardTokens[i];
            uint256 rewardAmount = rewards[i];

            if (rewardAmount == 0) {
                continue;
            }
            
            if (_rewardToken == address(AURA)) {
                auraBalance -= rewardAmount;
            }

            IPoolEscrow(escrow).transferToken(
                _rewardToken,
                msg.sender,
                rewardAmount
            );
        }

        packedBalances[pid] = _packBalances(lastBalPerToken, auraBalance);

        emit Burned(id, amount, msg.sender);
    }

    /// @notice Retrieve pending rewards for a given tokenId and amount.
    /// @dev The rewards can be split among multiple tokens.
    /// @param tokenId The ID of the token.
    /// @param amount The amount of the token.
    /// @return tokens Array of token addresses.
    /// @return rewards Array of corresponding reward amounts.
    function pendingRewards(uint256 tokenId, uint256 amount)
        public
        view
        override
        returns (address[] memory tokens, uint256[] memory rewards)
    {
        (uint256 pid, uint256 originalBalPerShare) = decodeId(tokenId);

        address stashToken = stashTokenInfo[pid].stashToken;

        uint256 extraRewardsCount = extraRewardsLength(pid);
        tokens = new address[](extraRewardsCount + 2);
        rewards = new uint256[](extraRewardsCount + 2);
        
        // BAL reward 
        {
            (, , , address auraRewarder, , ) = getPoolInfoFromPoolId(pid);
            /// BAL reward
            tokens[0] = IRewarder(auraRewarder).rewardToken();
            rewards[0] = _getPendingReward(
                originalBalPerShare,
                auraRewarder,
                amount
            );
        }
        // AURA reward
        tokens[1] = address(AURA);
        rewards[1] = _getAllocatedAURA(pid, originalBalPerShare, amount);
        
        // This index is used to make sure that there is no gap in the returned array
        uint256 index = 0;
        bool stashTokenFound = false;
        // Additional rewards
        for (uint256 i; i < extraRewardsCount; ++i) {
            address rewarder = extraRewards[pid].at(i);
            address rewardToken = IRewarder(rewarder).rewardToken();

            if (rewardToken == stashToken) {
                stashTokenFound = true;
                continue;
            }

            uint256 tokenRewardPerShare = accExtPerShare[tokenId][rewarder];
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

    /// @notice Get the full set of extra rewards.
    /// @return An array containing the addresses of extra reward tokens.
    function extraRewardsLength(uint256 pid) public view returns (uint256) {
        return extraRewards[pid].length();
    }

    /// @notice Retrieves pool id from a BPT token
    /// @param bpt Address of the BPT token
    /// @return Pool id associated with the BPT token
    function getBPTPoolId(address bpt) public view returns (bytes32) {
        return IBalancerPool(bpt).getPoolId();
    }
    
    /// @notice Gets the escrow contract address for a given PID
    /// @param pid The pool ID
    /// @return escrowAddress Escrow associated with the given PID
    function getEscrow(
        uint256 pid
    ) public view returns (address escrowAddress) {
        return escrows[pid];
    }

    function getExtraRewarder(
        uint256 pid,
        uint256 index
    ) external view returns (address) {
        return extraRewards[pid].at(index);
    }

    /// @notice Fetches pool information using a provided aura finance pool id
    /// @param pid The aura finance pool id
    /// @return lptoken Address of the LP token
    /// @return token Address of the associated token
    /// @return gauge Address of the gauge
    /// @return auraRewards Address for AURA rewards
    /// @return stash Address of the stash
    /// @return shutdown Boolean indicating if the pool is shut down
    function getPoolInfoFromPoolId(uint256 pid)
        public
        view
        returns (
            address lptoken,
            address token,
            address gauge,
            address auraRewards,
            address stash,
            bool shutdown
        )
    {
        return auraBooster.poolInfo(pid);
    }

    /// @notice Retrieves pool tokens from a given BPT address
    /// @param bpt Address of the BPT token
    /// @return tokens Array of token addresses in the pool
    /// @return balances Corresponding balances of the tokens in the pool
    /// @return lastChangedBlock The last block when the pool composition changed
    function getPoolTokens(address bpt)
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangedBlock
        )
    {
        return getVault(bpt).getPoolTokens(getBPTPoolId(bpt));
    }

    /// @notice Retrieves the underlying ERC20 token of the specified ERC1155 token id
    /// @param id The ERC1155 token id
    /// @return uToken Address of the underlying ERC20 token
    function getUnderlyingToken(uint256 id)
        external
        view
        override
        returns (address uToken)
    {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /// @notice Gets the Balancer vault for a given BPT token
    /// @param bpt Address of the BPT token
    /// @return Vault associated with the provided BPT token
    function getVault(address bpt) public view returns (IBalancerVault) {
        return IBalancerVault(IBalancerPool(bpt).getVault());
    }

    /// @notice Calculate the amount of pending reward for a given LP amount.
    /// @param originalRewardPerShare The cached value of BAL per share at the time of opening the position.
    /// @param rewarder The address of the rewarder contract.
    /// @param amount The amount of LP for which reward is being calculated.
    /// @return rewards The calculated reward amount.
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

    function _getAllocatedAURA(
        uint256 pid,
        uint256 originalBalPerShare,
        uint256 amount
    ) internal view returns (uint256 mintAmount) {
        address escrow = getEscrow(pid);
        (, , , address auraRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        uint256 currentDeposits = IRewarder(auraRewarder).balanceOf(
            escrow
        );

        if (currentDeposits == 0) {
            return 0;
        }

        uint256 auraPerShare = auraPerShareByPid[pid] -
            auraPerShareDebt[encodeId(pid, originalBalPerShare)];

        return auraPerShare.mulWadDown(amount);
    }

    /// @notice Private function to update aura rewards
    /// @param pid The pool id.
    /// @param tokenId The token id.
    /// @dev Claims rewards and updates auraPerShareByPid accordingly
    function _updateAuraReward(uint256 pid, uint256 tokenId) private {
        StashTokenInfo storage _stashTokenInfo = stashTokenInfo[pid];
        address escrow = getEscrow(pid);
        address stashToken = _stashTokenInfo.stashToken;
        // _auraRewarder rewards users in AURA
        (, , , address _auraRewarder, address stashAura, ) = getPoolInfoFromPoolId(pid);
        uint256 lastBalPerToken = IRewarder(_auraRewarder).rewardPerToken();

        // If the token is not minted yet the tokenId will be 0
        //   and rewards will be synced later
        if (tokenId != 0) {
            syncExtraRewards(pid, tokenId);
        }

        if (stashToken == address(0)) {
            _setAuraStashToken(_stashTokenInfo, _auraRewarder, stashAura);
        }

        uint256 currentDeposits = IRewarder(_auraRewarder).balanceOf(
            escrow
        );

        if (currentDeposits == 0) {
            packedBalances[pid] = _packBalances(lastBalPerToken, AURA.balanceOf(escrow));
            return;
        }
        
        (, uint256 auraPreBalance) = _unpackBalances(packedBalances[pid]);

        IRewarder(_auraRewarder).getReward(escrow, false);

        _getExtraRewards(pid, escrow);

        uint256 auraPostBalance = AURA.balanceOf(escrow);
        uint256 auraReceived = auraPostBalance - auraPreBalance;

        if (auraReceived > 0) {
            auraPerShareByPid[pid] += auraReceived.divWadDown(currentDeposits);
        }

        packedBalances[pid] = _packBalances(lastBalPerToken, auraPostBalance);
    }

    function _packBalances(uint256 lastBalPerToken, uint256 auraBalance) internal pure returns (uint256) {
        return lastBalPerToken << 128 | auraBalance;
    }

    function _unpackBalances(uint256 packedBalance) internal pure returns (uint256 lastBalPerToken, uint256 auraBalance) {
        lastBalPerToken = packedBalance >> 128;
        auraBalance = packedBalance & ((1 << 128) - 1);
    }

    function _getExtraRewards(uint256 pid, address escrow) internal {
        uint256 currentExtraRewardsCount = extraRewards[pid].length();
        for (uint256 i; i < currentExtraRewardsCount; ++i) {
            address extraRewarder = extraRewards[pid].at(i);
            ICvxExtraRewarder(extraRewarder).getReward(escrow);
        }
    }

    /**
     * @notice Sets the Aura Stash token
     * @param auraRewarder Address of the Aura Rewarder
     * @param stashAura Address of the stash Aura
     */
    function _setAuraStashToken(StashTokenInfo storage stashTokenData, address auraRewarder, address stashAura) internal {
        uint256 length = IRewarder(auraRewarder).extraRewardsLength();
        for (uint256 i; i < length; ++i) {
            address _extraRewarder = IRewarder(auraRewarder)
                .extraRewards(i);

            address _rewardToken = IRewarder(_extraRewarder)
                .rewardToken();
            // Initialize the stashToken if it is not initialized
            if (_isAuraStashToken(_rewardToken, stashAura)) {
                stashTokenData.stashToken = _rewardToken;
                stashTokenData.rewarder = _extraRewarder;
                break;
            }
        }
    }

    function syncExtraRewards(uint256 pid, uint256 tokenId) public {
        (, , , address rewarder, , ) = getPoolInfoFromPoolId(pid);
        EnumerableSetUpgradeable.AddressSet storage rewards = extraRewards[pid];
        uint256 extraRewardsCount = IRewarder(rewarder)
            .extraRewardsLength();
        for (uint256 i; i < extraRewardsCount; ++i) {
            address extraRewarder = IRewarder(rewarder).extraRewards(i);
            bool mismatchFound = _syncExtraRewards(rewards, tokenId, extraRewarder);

            if (!mismatchFound && accExtPerShare[tokenId][extraRewarder] == type(uint).max) {
                uint256 rewardPerToken = IRewarder(extraRewarder)
                    .rewardPerToken();

                if (rewardPerToken != 0) {
                    accExtPerShare[tokenId][extraRewarder] = rewardPerToken;
                }
            }
        }
    }
    
    function _setAccExtPerShare(uint256 tokenId, address extraRewarder) internal {
        uint256 rewardPerToken = IRewarder(extraRewarder)
            .rewardPerToken();
        accExtPerShare[tokenId][extraRewarder] = rewardPerToken == 0
            ? type(uint).max
            : rewardPerToken;
    }

    function _syncExtraRewards(
        EnumerableSetUpgradeable.AddressSet storage rewards,
        uint256 tokenId,
        address rewarder
    ) internal returns (bool mismatchFound) {
        if (!rewards.contains(rewarder)) {
            rewards.add(rewarder);
            _setAccExtPerShare(tokenId, rewarder);
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
        try IAuraStashToken(token).stash() returns (address stash) {
            return stash == auraStash;
        } catch  {
            return false;
        }
    }
}

