// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../utils/BBMath.sol';
import '../interfaces/IWIchiFarm.sol';
import '../interfaces/IERC20Wrapper.sol';
import '../interfaces/ichi/IIchiFarm.sol';

contract WIchiFarm is
    ERC1155('WIchiFarm'),
    ReentrancyGuard,
    IERC20Wrapper,
    IWIchiFarm
{
    using BBMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable ICHI;
    IIchiFarm public immutable ichiFarm;

    constructor(address _ichi, address _ichiFarm) {
        ICHI = IERC20(_ichi);
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
        require(pid < (1 << 16), 'bad pid');
        require(ichiPerShare < (1 << 240), 'bad ichi per share');
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

    /// @dev Return the conversion rate from ERC-1155 to ERC-20, multiplied by 2**112.
    function getUnderlyingRate(uint256)
        external
        pure
        override
        returns (uint256)
    {
        return 2**112;
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
        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        if (
            IERC20(lpToken).allowance(address(this), address(ichiFarm)) !=
            type(uint256).max
        ) {
            // We only need to do this once per pool, as LP token's allowance won't decrease if it's -1.
            IERC20(lpToken).safeApprove(address(ichiFarm), type(uint256).max);
        }
        ichiFarm.deposit(pid, amount, address(this));
        (uint256 ichiPerShare, , ) = ichiFarm.poolInfo(pid);
        uint256 id = encodeId(pid, ichiPerShare);
        _mint(msg.sender, id, amount, '');
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
        ichiFarm.withdraw(pid, amount, address(this));
        address lpToken = ichiFarm.lpToken(pid);
        (uint256 enIchiPerShare, , ) = ichiFarm.poolInfo(pid);
        IERC20(lpToken).safeTransfer(msg.sender, amount);
        uint256 stIchi = (stIchiPerShare * amount).divCeil(1e18);
        uint256 enIchi = (enIchiPerShare * amount) / 1e18;
        if (enIchi > stIchi) {
            ICHI.safeTransfer(msg.sender, enIchi - stIchi);
        }
        return pid;
    }
}
