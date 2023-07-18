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

    /// @notice Encode pid, auraPerShare to ERC1155 token id
    /// @param pid Pool id (16-bit)
    /// @param auraPerShare AURA amount per share, multiplied by 1e18 (240-bit)
    function encodeId(
        uint256 pid,
        uint256 auraPerShare
    ) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (auraPerShare >= (1 << 240))
            revert Errors.BAD_REWARD_PER_SHARE(auraPerShare);
        return (pid << 240) | auraPerShare;
    }

    /// @notice Decode ERC1155 token id to pid, auraPerShare
    /// @param id Token id
    function decodeId(
        uint256 id
    ) public pure returns (uint256 gid, uint256 auraPerShare) {
        gid = id >> 240; // First 16 bits
        auraPerShare = id & ((1 << 240) - 1); // Last 240 bits
    }

    /// @notice Get underlying ERC20 token of ERC1155 given token id
    /// @param id Token id
    function getUnderlyingToken(
        uint256 id
    ) external view override returns (address uToken) {
        (uint256 pid, ) = decodeId(id);
        (uToken, , , , , ) = getPoolInfoFromPoolId(pid);
    }

    function getVault(address bpt) public view returns (IBalancerVault) {
        return IBalancerVault(IBalancerPool(bpt).getVault());
    }

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

    function getBPTPoolId(address bpt) public view returns (bytes32) {
        return IBalancerPool(bpt).getPoolId();
    }

    /// @notice Get pool info from aura booster
    /// @param pid aura finance pool id
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
        uint256 enRewardPerShare = IAuraRewarder(rewarder).rewardPerToken();
        uint256 share = enRewardPerShare > stRewardPerShare
            ? enRewardPerShare - stRewardPerShare
            : 0;
        rewards = (share * amount) / (10 ** lpDecimals);
    }

    /// @notice Get AURA pending reward
    /// @param auraRewarder Address of Aura rewarder contract
    /// @param balAmount Amount of BAL reward
    /// @dev AURA token is minted in booster contract following the mint logic in the below
    function _getAuraPendingReward(
        address auraRewarder,
        uint256 balAmount
    ) internal view returns (uint256 mintAmount) {
        // AURA mint request amount = amount * reward_multiplier / reward_multiplier_denominator
        uint256 mintRequestAmount = (balAmount *
            auraPools.getRewardMultipliers(auraRewarder)) /
            REWARD_MULTIPLIER_DENOMINATOR;

        // AURA token mint logic
        // e.g. emissionsMinted = 6e25 - 5e25 - 0 = 1e25;
        uint256 totalSupply = AURA.totalSupply();
        uint256 initAmount = AURA.INIT_MINT_AMOUNT();
        uint256 minterMinted;
        uint256 reductionPerCliff = AURA.reductionPerCliff();
        uint256 totalCliffs = AURA.totalCliffs();
        uint256 emissionMaxSupply = AURA.EMISSIONS_MAX_SUPPLY();

        uint256 emissionsMinted = totalSupply - initAmount - minterMinted;
        // e.g. reductionPerCliff = 5e25 / 500 = 1e23
        // e.g. cliff = 1e25 / 1e23 = 100
        uint256 cliff = emissionsMinted / reductionPerCliff;

        // e.g. 100 < 500
        if (cliff < totalCliffs) {
            // e.g. (new) reduction = (500 - 100) * 2.5 + 700 = 1700;
            // e.g. (new) reduction = (500 - 250) * 2.5 + 700 = 1325;
            // e.g. (new) reduction = (500 - 400) * 2.5 + 700 = 950;
            uint256 reduction = ((totalCliffs - cliff) * 5) / 2 + 700;
            // e.g. (new) amount = 1e19 * 1700 / 500 =  34e18;
            // e.g. (new) amount = 1e19 * 1325 / 500 =  26.5e18;
            // e.g. (new) amount = 1e19 * 950 / 500  =  19e17;
            mintAmount = (mintRequestAmount * reduction) / totalCliffs;

            // e.g. amtTillMax = 5e25 - 1e25 = 4e25
            uint256 amtTillMax = emissionMaxSupply - emissionsMinted;
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
        (uint256 pid, uint256 stAuraPerShare) = decodeId(tokenId);
        (address lpToken, , , address auraRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );
        uint256 lpDecimals = IERC20MetadataUpgradeable(lpToken).decimals();
        uint256 extraRewardsCount = extraRewards.length;
        tokens = new address[](extraRewardsCount + 2);
        rewards = new uint256[](extraRewardsCount + 2);

        // BAL reward
        tokens[0] = IAuraRewarder(auraRewarder).rewardToken();
        rewards[0] = _getPendingReward(
            stAuraPerShare,
            auraRewarder,
            amount,
            lpDecimals
        );

        // AURA reward
        tokens[1] = address(AURA);
        rewards[1] = _getAuraPendingReward(auraRewarder, rewards[0]);

        // Additional rewards
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

    /// @notice Mint ERC1155 token for the given LP token
    /// @param pid Aura Pool id
    /// @param amount Token amount to wrap
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

        // BAL reward handle logic
        uint256 balRewardPerToken = IAuraRewarder(auraRewarder)
            .rewardPerToken();
        id = encodeId(pid, balRewardPerToken);
        _mint(msg.sender, id, amount, "");

        // Store extra rewards info
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

        (address lpToken, , , address auraRewarder, , ) = getPoolInfoFromPoolId(
            pid
        );

        // Claim Rewards
        IAuraRewarder(auraRewarder).withdraw(amount, true);
        // Withdraw LP
        auraPools.withdraw(pid, amount);

        // Transfer LP Tokens
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

        // Transfer Reward Tokens
        (rewardTokens, rewards) = pendingRewards(id, amount);

        // Withdraw manually
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

    /// @notice Get length of extra rewards
    function extraRewardsLength() external view returns (uint256) {
        return extraRewards.length;
    }

    function _syncExtraReward(address extraReward) private {
        if (extraRewardsIdx[extraReward] == 0) {
            extraRewards.push(extraReward);
            extraRewardsIdx[extraReward] = extraRewards.length;
        }
    }
}
