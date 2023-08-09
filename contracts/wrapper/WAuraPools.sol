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
import "../interfaces/IWAuraPools.sol";
import "../interfaces/IERC20Wrapper.sol";
import "../interfaces/aura/IAuraRewarder.sol";
import "../interfaces/aura/IAuraExtraRewarder.sol";
import "../interfaces/aura/IAura.sol";

/**
 * @title WAuraPools
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
    EnsureApprove,
    IERC20Wrapper,
    IWAuraPools
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address to Aura Pools contract
    IAuraPools public auraPools;
    /// @dev Address to AURA token
    IAura public AURA;
    /// @dev Address to STASH_AURA token
    address public STASH_AURA;
    /// @dev Mapping from token id to accExtPerShare
    mapping(uint256 => mapping(address => uint256)) public accExtPerShare;
    /// @dev Aura extra rewards addresses
    address[] public extraRewards;
    /// @dev The index of extra rewards
    mapping(address => uint256) public extraRewardsIdx;

    uint public REWARD_MULTIPLIER_DENOMINATOR;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes contract with dependencies
    /// @param aura_ The AURA token address
    /// @param auraPools_ The auraPools contract address
    /// @param stash_aura_ The stash for AURA
    function initialize(
        address aura_,
        address auraPools_,
        address stash_aura_
    ) external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("WAuraPools");
        AURA = IAura(aura_);
        STASH_AURA = stash_aura_;
        auraPools = IAuraPools(auraPools_);
        REWARD_MULTIPLIER_DENOMINATOR = auraPools
            .REWARD_MULTIPLIER_DENOMINATOR();
    }

    /// @notice Encodes pool id and AURA per share into an ERC1155 token id
    /// @param pid The pool id (The first 16-bits)
    /// @param auraPerShare Amount of AURA per share, multiplied by 1e18 (The last 240-bits)
    /// @return id The resulting ERC1155 token id

    function encodeId(
        uint256 pid,
        uint256 auraPerShare
    ) public pure returns (uint256 id) {
        // Ensure the pool id and auraPerShare are within expected bounds
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (auraPerShare >= (1 << 240))
            revert Errors.BAD_REWARD_PER_SHARE(auraPerShare);
        return (pid << 240) | auraPerShare;
    }

    /// @notice Decodes ERC1155 token id to pool id and AURA per share
    /// @param id The ERC1155 token id
    /// @return gid The decoded pool id
    /// @return auraPerShare The decoded amount of AURA per share
    function decodeId(
        uint256 id
    ) public pure returns (uint256 gid, uint256 auraPerShare) {
        gid = id >> 240; // Extracting the first 16 bits
        auraPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    /// @notice Retrieves the underlying ERC20 token of the specified ERC1155 token id
    /// @param id The ERC1155 token id
    /// @return uToken Address of the underlying ERC20 token
    function getUnderlyingToken(
        uint256 id
    ) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    /// @notice Gets the Balancer vault for a given BPT token
    /// @param bpt Address of the BPT token
    /// @return Vault associated with the provided BPT token
    function getVault(address bpt) public view returns (IBalancerVault) {
        return IBalancerVault(IBalancerPool(bpt).getVault());
    }

    /// @notice Retrieves pool tokens from a given BPT address
    /// @param bpt Address of the BPT token
    /// @return tokens Array of token addresses in the pool
    /// @return balances Corresponding balances of the tokens in the pool
    /// @return lastChangedBlock The last block when the pool composition changed
    function getPoolTokens(
        address bpt
    )
        external
        view
        returns (
            address[] memory tokens,
            uint256[] memory balances,
            uint256 lastChangedBlock
        )
    {
        return getVault(bpt).getPoolTokens(IBalancerPool(bpt).getPoolId());
    }

    /// @notice Retrieves pool id from a BPT token
    /// @param bpt Address of the BPT token
    /// @return Pool id associated with the BPT token
    function getBPTPoolId(address bpt) public view returns (bytes32) {
        return IBalancerPool(bpt).getPoolId();
    }

    /// @notice Fetches pool information using a provided aura finance pool id
    /// @param pid The aura finance pool id
    /// @return lptoken Address of the LP token
    /// @return token Address of the associated token
    /// @return gauge Address of the gauge
    /// @return auraRewards Address for AURA rewards
    /// @return stash Address of the stash
    /// @return shutdown Boolean indicating if the pool is shut down
    function getPoolInfoFromPoolId(
        uint256 pid
    )
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
        return auraPools.poolInfo(pid);
    }

    /// @notice Calculate the amount of pending reward for a given LP amount.
    /// @param stRewardPerShare The stored reward per share value.
    /// @param rewarder The address of the rewarder contract.
    /// @param amount The amount of LP for which reward is being calculated.
    /// @param lpDecimals The number of decimals of the LP token.
    /// @return rewards The calculated reward amount.
    function _getPendingReward(
        uint256 stRewardPerShare,
        address rewarder,
        uint256 amount,
        uint256 lpDecimals
    ) internal view returns (uint256 rewards) {
        /// Retrieve current reward per token from rewarder
        uint256 enRewardPerShare = IAuraRewarder(rewarder).rewardPerToken();
        /// Calculatethe difference in reward per share
        uint256 share = enRewardPerShare > stRewardPerShare
            ? enRewardPerShare - stRewardPerShare
            : 0;
        /// Calculate the total rewards base on share and amount.
        rewards = (share * amount) / (10 ** lpDecimals);
    }

    /// @notice  Calculate the pending AURA reward amount.
    /// @dev AuraMinter can mint additional tokens after `inflationProtectionTime` has passed
    /// And its value is `1749120350`  ==> Thursday 5 June 2025 12:32:30 PM GMT+07:00
    /// @param auraRewarder Address of Aura rewarder contract
    /// @param balAmount The amount of BAL reward for AURA calculation.
    /// @dev AURA token is minted in booster contract following the mint logic in the below
    function _getAuraPendingReward(
        address auraRewarder,
        uint256 balAmount
    ) internal view returns (uint256 mintAmount) {
        /// AURA mint request amount = amount * reward_multiplier / reward_multiplier_denominator
        uint256 mintRequestAmount = (balAmount *
            auraPools.getRewardMultipliers(auraRewarder)) /
            REWARD_MULTIPLIER_DENOMINATOR;

        /// AURA token mint logic
        /// e.g. emissionsMinted = 6e25 - 5e25 - 0 = 1e25;
        uint256 totalSupply = AURA.totalSupply();
        uint256 initAmount = AURA.INIT_MINT_AMOUNT();
        uint256 minterMinted;
        uint256 reductionPerCliff = AURA.reductionPerCliff();
        uint256 totalCliffs = AURA.totalCliffs();
        uint256 emissionMaxSupply = AURA.EMISSIONS_MAX_SUPPLY();

        uint256 emissionsMinted = totalSupply - initAmount - minterMinted;
        /// e.g. reductionPerCliff = 5e25 / 500 = 1e23
        /// e.g. cliff = 1e25 / 1e23 = 100
        uint256 cliff = emissionsMinted / reductionPerCliff;

        /// e.g. 100 < 500
        if (cliff < totalCliffs) {
            /// e.g. (new) reduction = (500 - 100) * 2.5 + 700 = 1700;
            /// e.g. (new) reduction = (500 - 250) * 2.5 + 700 = 1325;
            /// e.g. (new) reduction = (500 - 400) * 2.5 + 700 = 950;
            uint256 reduction = ((totalCliffs - cliff) * 5) / 2 + 700;
            /// e.g. (new) amount = 1e19 * 1700 / 500 =  34e18;
            /// e.g. (new) amount = 1e19 * 1325 / 500 =  26.5e18;
            /// e.g. (new) amount = 1e19 * 950 / 500  =  19e17;
            mintAmount = (mintRequestAmount * reduction) / totalCliffs;

            /// e.g. amtTillMax = 5e25 - 1e25 = 4e25
            uint256 amtTillMax = emissionMaxSupply - emissionsMinted;
            if (mintAmount > amtTillMax) {
                mintAmount = amtTillMax;
            }
        }
    }

    /// @notice Retrieve pending rewards for a given tokenId and amount.
    /// @dev The rewards can be split among multiple tokens.
    /// @param tokenId The ID of the token.
    /// @param amount The amount of the token.
    /// @return tokens Array of token addresses.
    /// @return rewards Array of corresponding reward amounts.
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    )
        public
        view
        override
        returns (address[] memory tokens, uint256[] memory rewards)
    {
        (uint256 pid, uint256 stAuraPerShare) = decodeId(tokenId);
        (address lpToken, , , address auraRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();
        uint256 extraRewardsCount = extraRewards.length;
        tokens = new address[](extraRewardsCount + 2);
        rewards = new uint256[](extraRewardsCount + 2);

        /// BAL reward
        tokens[0] = IAuraRewarder(auraRewarder).rewardToken();
        rewards[0] = _getPendingReward(
            stAuraPerShare,
            auraRewarder,
            amount,
            lpDecimals
        );

        /// AURA reward
        tokens[1] = address(AURA);
        rewards[1] = _getAuraPendingReward(auraRewarder, rewards[0]);

        /// Additional rewards
        for (uint256 i; i != extraRewardsCount; ) {
            address rewarder = extraRewards[i];
            uint256 stRewardPerShare = accExtPerShare[tokenId][rewarder];
            tokens[i + 2] = IAuraRewarder(rewarder).rewardToken();
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
        IERC20Upgradeable(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        _ensureApprove(lpToken, address(auraPools), amount);
        auraPools.deposit(pid, amount, true);

        /// BAL reward handle logic
        uint256 balRewardPerToken = IAuraRewarder(auraRewarder)
            .rewardPerToken();
        id = encodeId(pid, balRewardPerToken);
        _mint(msg.sender, id, amount, "");

        /// Store extra rewards info
        uint256 extraRewardsCount = IAuraRewarder(auraRewarder)
            .extraRewardsLength();
        for (uint256 i; i != extraRewardsCount; ) {
            address extraRewarder = IAuraRewarder(auraRewarder).extraRewards(i);
            uint256 rewardPerToken = IAuraRewarder(extraRewarder)
                .rewardPerToken();
            accExtPerShare[id][extraRewarder] = rewardPerToken == 0
                ? type(uint).max
                : rewardPerToken;

            _syncExtraReward(extraRewarder);

            unchecked {
                ++i;
            }
        }
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
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        (uint256 pid, ) = decodeId(id);
        _burn(msg.sender, id, amount);

        (address lpToken, , , address auraRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );

        /// Claim Rewards
        IAuraRewarder(auraRewarder).withdraw(amount, true);
        /// Withdraw LP
        auraPools.withdraw(pid, amount);

        /// Transfer LP Tokens
        IERC20Upgradeable(lpToken).safeTransfer(msg.sender, amount);

        uint256 extraRewardsCount = IAuraRewarder(auraRewarder)
            .extraRewardsLength();

        for (uint256 i; i != extraRewardsCount; ) {
            _syncExtraReward(IAuraRewarder(auraRewarder).extraRewards(i));

            unchecked {
                ++i;
            }
        }
        uint256 storedExtraRewardLength = extraRewards.length;
        bool hasDiffExtraRewards = extraRewardsCount != storedExtraRewardLength;

        /// Transfer Reward Tokens
        (rewardTokens, rewards) = pendingRewards(id, amount);

        /// Withdraw manually
        if (hasDiffExtraRewards) {
            for (uint256 i; i != storedExtraRewardLength; ) {
                IAuraExtraRewarder(extraRewards[i]).getReward();

                unchecked {
                    ++i;
                }
            }
        }

        uint256 rewardTokensLength = rewardTokens.length;
        for (uint256 i; i != rewardTokensLength; ) {
            IERC20Upgradeable(rewardTokens[i]).safeTransfer(
                msg.sender,
                rewards[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get the full set of extra rewards.
    /// @return An array containing the addresses of extra reward tokens.
    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    /// @notice Internal function to sync any extra rewards with the contract.
    /// @param extraReward The address of the extra reward token.
    /// @dev Adds the extra reward to the internal list if not already present.
    function _syncExtraReward(address extraReward) private {
        if (extraRewardsIdx[extraReward] == 0) {
            extraRewards.push(extraReward);
            extraRewardsIdx[extraReward] = extraRewards.length;
        }
    }
}
