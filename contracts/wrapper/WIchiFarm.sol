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
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
/* solhint-enable max-line-length */

import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BBMath } from "../libraries/BBMath.sol";
import { IWIchiFarm } from "../interfaces/IWIchiFarm.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IIchiV2 } from "../interfaces/ichi/IIchiV2.sol";
import { IIchiFarm } from "../interfaces/ichi/IIchiFarm.sol";

/**
 * @title WIchiFarm
 * @author BlueberryProtocol
 * @notice Wrapped IchiFarm is the wrapper of ICHI MasterChef
 * @dev Leveraged ICHI Lp Tokens will be wrapped here and be held in BlueberryBank.
 *      At the same time, Underlying LPs will be deposited to ICHI farming pools and generate yields
 *      LP Tokens are identified by tokenIds encoded from lp token address and accPerShare of deposited time
 */
contract WIchiFarm is IWIchiFarm, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    using BBMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IIchiV2;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev address of legacy ICHI token
    IERC20Upgradeable private _ichiV1;
    /// @dev address of ICHI v2
    IIchiV2 private _ichiV2;
    /// @dev address of ICHI farming contract
    IIchiFarm private _ichiFarm;

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
     * @notice Initializes the contract with the given ICHI token addresses.
     * @param ichi Address of ICHI v2 token.
     * @param ichiV1 Address of legacy ICHI token.
     * @param ichiFarm Address of ICHI farming contract.
     * @param owner The owner of the contract.
     */
    function initialize(address ichi, address ichiV1, address ichiFarm, address owner) external initializer {
        if (address(ichi) == address(0) || address(ichiV1) == address(0) || address(ichiFarm) == address(0))
            revert Errors.ZERO_ADDRESS();

        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("wIchiFarm");

        _ichiV2 = IIchiV2(ichi);
        _ichiV1 = IERC20Upgradeable(ichiV1);
        _ichiFarm = IIchiFarm(ichiFarm);
    }

    /// @inheritdoc IWIchiFarm
    function encodeId(uint256 pid, uint256 ichiPerShare) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (ichiPerShare >= (1 << 240)) revert Errors.BAD_REWARD_PER_SHARE(ichiPerShare);

        return (pid << 240) | ichiPerShare;
    }

    /// @inheritdoc IWIchiFarm
    function decodeId(uint256 id) public pure returns (uint256 pid, uint256 ichiPerShare) {
        pid = id >> 240; // First 16 bits
        ichiPerShare = id & ((1 << 240) - 1); // Last 240 bits
    }

    /// @inheritdoc IWIchiFarm
    function mint(uint256 pid, uint256 amount) external nonReentrant returns (uint256) {
        IIchiFarm ichiFarm = getIchiFarm();
        address lpToken = ichiFarm.lpToken(pid);
        IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(lpToken).universalApprove(address(ichiFarm), amount);
        ichiFarm.deposit(pid, amount, address(this));

        (uint256 ichiPerShare, , ) = ichiFarm.poolInfo(pid);

        uint256 id = encodeId(pid, ichiPerShare);

        _mint(msg.sender, id, amount, "");

        emit Minted(id, pid, amount);

        return id;
    }

    /// @inheritdoc IWIchiFarm
    function burn(uint256 id, uint256 amount) external nonReentrant returns (uint256) {
        (uint256 pid, ) = decodeId(id);
        _burn(msg.sender, id, amount);

        IIchiFarm ichiFarm = getIchiFarm();
        IIchiV2 ichiV2 = getIchiV2();

        uint256 ichiRewards = ichiFarm.pendingIchi(pid, address(this));
        ichiFarm.harvest(pid, address(this));
        ichiFarm.withdraw(pid, amount, address(this));

        /// Convert Legacy ICHI to ICHI v2
        if (ichiRewards > 0) {
            IERC20(address(_ichiV1)).universalApprove(address(ichiV2), ichiRewards);
            ichiV2.convertToV2(ichiRewards);
        }

        /// Transfer LP Tokens
        address lpToken = ichiFarm.lpToken(pid);
        IERC20Upgradeable(lpToken).safeTransfer(msg.sender, amount);

        /// Transfer Reward Tokens
        (, uint256[] memory rewards) = pendingRewards(id, amount);

        if (rewards[0] > 0) {
            /// Transfer minimum amount to prevent reverted tx
            ichiV2.safeTransfer(
                msg.sender,
                ichiV2.balanceOf(address(this)) >= rewards[0] ? rewards[0] : ichiV2.balanceOf(address(this))
            );
        }

        emit Burned(id, pid, amount);

        return rewards[0];
    }

    /// @inheritdoc IERC20Wrapper
    function pendingRewards(
        uint256 tokenId,
        uint amount
    ) public view override returns (address[] memory tokens, uint256[] memory rewards) {
        (uint256 pid, uint256 stIchiPerShare) = decodeId(tokenId);
        IIchiFarm ichiFarm = getIchiFarm();

        uint256 lpDecimals = IERC20MetadataUpgradeable(ichiFarm.lpToken(pid)).decimals();
        (uint256 enIchiPerShare, , ) = ichiFarm.poolInfo(pid);

        /// Multiple by 1e9 because reward token should be converted from ICHI v1 to ICHI v2
        /// ICHI v1 decimal: 9, ICHI v2 Decimal: 18
        uint256 stIchi = 1e9 * (stIchiPerShare * amount).divCeil(10 ** lpDecimals);
        uint256 enIchi = (1e9 * (enIchiPerShare * amount)) / (10 ** lpDecimals);
        uint256 ichiRewards = enIchi > stIchi ? enIchi - stIchi : 0;

        tokens = new address[](1);
        rewards = new uint256[](1);
        tokens[0] = address(getIchiV2());
        rewards[0] = ichiRewards;
    }

    /// @inheritdoc IWIchiFarm
    function getIchiV1() external view override returns (IERC20Upgradeable) {
        return _ichiV1;
    }

    /// @inheritdoc IWIchiFarm
    function getIchiV2() public view override returns (IIchiV2) {
        return _ichiV2;
    }

    /// @inheritdoc IWIchiFarm
    function getIchiFarm() public view override returns (IIchiFarm) {
        return _ichiFarm;
    }

    /// @inheritdoc IERC20Wrapper
    function getUnderlyingToken(uint256 id) external view override returns (address) {
        (uint256 pid, ) = decodeId(id);
        return _ichiFarm.lpToken(pid);
    }
}
