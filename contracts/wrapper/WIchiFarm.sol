// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../utils/BlueBerryErrors.sol";
import "../libraries/BBMath.sol";
import "../interfaces/IWIchiFarm.sol";
import "../interfaces/IERC20Wrapper.sol";
import "../interfaces/ichi/IIchiV2.sol";
import "../interfaces/ichi/IIchiFarm.sol";

contract WIchiFarm is
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    IERC20Wrapper,
    IWIchiFarm
{
    using BBMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IIchiV2;

    IERC20Upgradeable public ICHIv1;
    IIchiV2 public ICHI;
    IIchiFarm public ichiFarm;

    function initialize(
        address _ichi,
        address _ichiv1,
        address _ichiFarm
    ) external initializer {
        __ERC1155_init("WIchiFarm");
        ICHI = IIchiV2(_ichi);
        ICHIv1 = IERC20Upgradeable(_ichiv1);
        ichiFarm = IIchiFarm(_ichiFarm);
    }

    /// @dev Encode pid, ichiPerShare to ERC1155 token id
    /// @param pid Pool id (16-bit)
    /// @param ichiPerShare Ichi amount per share, multiplied by 1e18 (240-bit)
    function encodeId(uint256 pid, uint256 ichiPerShare)
        public
        pure
        returns (uint256 id)
    {
        if (pid >= (1 << 16)) revert BAD_PID(pid);
        if (ichiPerShare >= (1 << 240))
            revert BAD_REWARD_PER_SHARE(ichiPerShare);
        return (pid << 240) | ichiPerShare;
    }

    /// @dev Decode ERC1155 token id to pid, ichiPerShare
    /// @param id Token id
    function decodeId(uint256 id)
        public
        pure
        returns (uint256 pid, uint256 ichiPerShare)
    {
        pid = id >> 240; // First 16 bits
        ichiPerShare = id & ((1 << 240) - 1); // Last 240 bits
    }

    /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
    /// @param id Token id
    function getUnderlyingToken(uint256 id)
        external
        view
        override
        returns (address)
    {
        (uint256 pid, ) = decodeId(id);
        return ichiFarm.lpToken(pid);
    }

    /// @dev Mint ERC1155 token for the given pool id.
    /// @param pid Pool id
    /// @param amount Token amount to wrap
    /// @return The token id that got minted.
    function mint(uint256 pid, uint256 amount)
        external
        nonReentrant
        returns (uint256)
    {
        address lpToken = ichiFarm.lpToken(pid);
        IERC20Upgradeable(lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (
            IERC20Upgradeable(lpToken).allowance(
                address(this),
                address(ichiFarm)
            ) != type(uint256).max
        ) {
            // We only need to do this once per pool, as LP token's allowance won't decrease if it's -1.
            IERC20Upgradeable(lpToken).safeApprove(
                address(ichiFarm),
                type(uint256).max
            );
        }
        ichiFarm.deposit(pid, amount, address(this));
        (uint256 ichiPerShare, , ) = ichiFarm.poolInfo(pid);
        uint256 id = encodeId(pid, ichiPerShare);
        _mint(msg.sender, id, amount, "");
        return id;
    }

    /// @dev Burn ERC1155 token to redeem LP ERC20 token back plus ICHI rewards.
    /// @param id Token id
    /// @param amount Token amount to burn
    /// @return The pool id that that you will receive LP token back.
    function burn(uint256 id, uint256 amount)
        external
        nonReentrant
        returns (uint256)
    {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        (uint256 pid, uint256 stIchiPerShare) = decodeId(id);
        _burn(msg.sender, id, amount);

        uint256 ichiRewards = ichiFarm.pendingIchi(pid, address(this));
        ichiFarm.harvest(pid, address(this));
        ichiFarm.withdraw(pid, amount, address(this));

        // Convert Legacy ICHI to ICHI v2
        if (ichiRewards > 0) {
            ICHIv1.safeApprove(address(ICHI), ichiRewards);
            ICHI.convertToV2(ichiRewards);
        }

        // Transfer LP Tokens
        address lpToken = ichiFarm.lpToken(pid);
        IERC20Upgradeable(lpToken).safeTransfer(msg.sender, amount);

        // Transfer Reward Tokens
        (uint256 enIchiPerShare, , ) = ichiFarm.poolInfo(pid);
        uint256 stIchi = (stIchiPerShare * amount).divCeil(1e18);
        uint256 enIchi = (enIchiPerShare * amount) / 1e18;

        if (enIchi > stIchi) {
            ICHI.safeTransfer(msg.sender, enIchi - stIchi);
        }
        return pid;
    }
}
