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

import { ApproxParams, TokenInput, TokenOutput, LimitOrderData } from "../interfaces/pendle-v2/IPendleRouter.sol";
import { IPMarket } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import { IPendleRouter } from "../interfaces/pendle-v2/IPendleRouter.sol";
import { IRewardManager } from "../interfaces/pendle-v2/IRewardManager.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { IWMasterPenPie } from "../interfaces/IWMasterPenPie.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";

/**
 * @title WMasterPenPie
 * @author BlueberryProtocol
 * @notice Wrapped Master PenPie is the wrapper of LP positions on Pendle Finance staked in PenPie farms.
 * @dev Leveraged LP Tokens will be wrapped here, deposited into PenPie and be held in BlueberryBank
 *      LP Tokens are identified by tokenIds
 *      encoded from lp token address.
 */
contract WMasterPenPie is IWMasterPenPie, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////////////////*/
    IPendleRouter private _pendleRouter;

    /// @dev Address of the PenPie token
    address private _penPie;

    mapping(address => EnumerableSetUpgradeable.AddressSet) private _rewardTokens;

    /// @dev Mapping of markets to a mapping of reward tokens to their reward index
    mapping(address => mapping(address => uint256)) private _rewardIndex;

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
     * @param owner The owner of the contract.
     */
    function initialize(IPendleRouter pendleRouter, address owner) external initializer {
        if (address(pendleRouter) == address(0) || owner == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("WMasterPenPie");
    }

    function encodeId(address market, uint256 activeBalance) public pure returns (uint256 id) {
        // Ensure the pool id and auraPerShare are within expected bounds
        // if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        // if (balPerShare >= (1 << 240)) revert Errors.BAD_REWARD_PER_SHARE(balPerShare);
        // return (pid << 240) | balPerShare;
    }

    function decodeId(uint256 id) public pure returns (address market, uint256 pnpPerShare) {
        // market = id >> 240; // Extracting the first 16 bits
        // balPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    function mint(address market, uint256 amount, bytes memory data) external nonReentrant returns (uint256 id) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();

        (ApproxParams memory params, TokenInput memory input, LimitOrderData memory limitOrder) = abi.decode(
            data,
            (ApproxParams, TokenInput, LimitOrderData)
        );

        // Deposit into the Pendle Market
        IPendleRouter(_pendleRouter).addLiquiditySingleToken(
            address(this),
            market,
            0, // adjust for slippage
            params,
            input,
            limitOrder
        );

        id = encodeId(market, 0);
        _mint(msg.sender, id, amount, "");
    }

    function burn(
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external nonReentrant returns (address[] memory rewardTokens, uint256[] memory rewards) {
        (address market, ) = decodeId(id);

        (TokenOutput memory output, LimitOrderData memory limitOrder) = abi.decode(data, (TokenOutput, LimitOrderData));
        // Withdraw from the Pendle Market
        IPendleRouter(_pendleRouter).removeLiquiditySingleToken(msg.sender, market, amount, output, limitOrder);

        _burn(msg.sender, id, amount);

        (rewardTokens, rewards) = pendingRewards(id, amount);
    }

    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    ) public view returns (address[] memory tokens, uint256[] memory rewards) {}

    function getUnderlyingToken(uint256 id) external view returns (address uToken) {}

    function _syncRewardTokens(address market) internal {
        // Tokens can get added but not removed
        uint256 currentRewardLength = _rewardTokens[market].length();

        address[] memory newRewardTokens = IPMarket(market).getRewardTokens();
        uint256 newRewardLength = newRewardTokens.length;

        if (currentRewardLength == newRewardLength) {
            return;
        }

        for (uint256 i = currentRewardLength; i < newRewardLength; i++) {
            _rewardTokens[market].add(newRewardTokens[i]);
            uint256 rewardIndex = IRewardManager(market).rewardState(newRewardTokens[i]).index;
            _rewardIndex[market][newRewardTokens[i]] = rewardIndex;
        }
    }

    function mint(address market, uint256 amount) external override returns (uint256 id) {}

    function burn(
        uint256 id,
        uint256 amount
    ) external override returns (address[] memory rewardTokens, uint256[] memory rewards) {}

    function getPenPie() external view override returns (address) {
        return _penPie;
    }
}
