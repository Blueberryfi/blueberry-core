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
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/BlueBerryErrors.sol" as Errors;

import "../interfaces/IERC20Wrapper.sol";
import "../interfaces/IWCurveGauge.sol";
import "../interfaces/curve/ICurveRegistry.sol";
import "../interfaces/curve/ILiquidityGauge.sol";

interface ILiquidityGaugeMinter {
    function mint(address gauge) external;
}

contract WCurveGauge is
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    IERC20Wrapper,
    IWCurveGauge
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct GaugeInfo {
        ILiquidityGauge impl; // Gauge implementation
        uint256 accCrvPerShare; // Accumulated CRV per share
    }

    /// @dev Address of Curve Registry
    ICurveRegistry public registry;
    /// @dev Address of CRV token
    IERC20Upgradeable public CRV;
    /// @dev Mapping from pool id to (mapping from gauge id to GaugeInfo)
    mapping(uint256 => mapping(uint256 => GaugeInfo)) public gauges;

    function initialize(
        address crv_,
        address crvRegistry_
    ) external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("WCurveGauge");
        CRV = IERC20Upgradeable(crv_);
        registry = ICurveRegistry(crvRegistry_);
    }

    /// @notice Encode pid, gid, crvPerShare to a ERC1155 token id
    /// @param pid Curve pool id (10-bit)
    /// @param gid Curve gauge id (6-bit)
    /// @param crvPerShare CRV amount per share, multiplied by 1e18 (240-bit)
    function encodeId(
        uint256 pid,
        uint256 gid,
        uint256 crvPerShare
    ) public pure returns (uint256) {
        require(pid < (1 << 10), "bad pid");
        require(gid < (1 << 6), "bad gid");
        require(crvPerShare < (1 << 240), "bad crv per share");
        return (pid << 246) | (gid << 240) | crvPerShare;
    }

    /// @notice Decode ERC1155 token id to pid, gid, crvPerShare
    /// @param id Token id to decode
    function decodeId(
        uint256 id
    ) public pure returns (uint256 pid, uint256 gid, uint256 crvPerShare) {
        pid = id >> 246; // First 10 bits
        gid = (id >> 240) & (63); // Next 6 bits
        crvPerShare = id & ((1 << 240) - 1); // Last 240 bits
    }

    /// @notice Get underlying ERC20 token of ERC1155 given pid, gid
    /// @param pid pool id
    /// @param gid gauge id
    function getUnderlyingTokenFromIds(
        uint256 pid,
        uint256 gid
    ) public view returns (address) {
        ILiquidityGauge impl = gauges[pid][gid].impl;
        if (address(impl) == address(0)) revert Errors.NO_GAUGE();
        return impl.lp_token();
    }

    /// @notice Get underlying ERC20 token of ERC1155 given token id
    /// @param id Token id
    function getUnderlyingToken(
        uint256 id
    ) external view override returns (address) {
        (uint256 pid, uint256 gid, ) = decodeId(id);
        return getUnderlyingTokenFromIds(pid, gid);
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
        // TODO:
    }

    /// @notice Register curve gauge to storage given pool id and gauge id
    /// @param pid Pool id
    /// @param gid Gauge id
    function registerGauge(uint256 pid, uint256 gid) external onlyOwner {
        if (address(gauges[pid][gid].impl) != address(0))
            revert Errors.EXISTING_GAUGE(pid, gid);
        address pool = registry.pool_list(pid);
        if (pool == address(0)) revert Errors.NO_CURVE_POOL(pid);
        (address[10] memory _gauges, ) = registry.get_gauges(pool);
        address gauge = _gauges[gid];
        if (gauge == address(0)) revert Errors.NO_GAUGE();
        IERC20Upgradeable lpToken = IERC20Upgradeable(
            ILiquidityGauge(gauge).lp_token()
        );
        lpToken.approve(gauge, 0);
        lpToken.approve(gauge, type(uint256).max);
        gauges[pid][gid] = GaugeInfo({
            impl: ILiquidityGauge(gauge),
            accCrvPerShare: 0
        });
    }

    /// @notice Mint ERC1155 token for the given ERC20 token
    /// @param pid Pool id
    /// @param gid Gauge id
    /// @param amount Token amount to wrap
    function mint(
        uint256 pid,
        uint256 gid,
        uint256 amount
    ) external nonReentrant returns (uint256) {
        GaugeInfo storage gauge = gauges[pid][gid];
        ILiquidityGauge impl = gauge.impl;
        if (address(impl) == address(0)) revert Errors.NO_GAUGE();
        _mintCrv(gauge);
        IERC20Upgradeable lpToken = IERC20Upgradeable(impl.lp_token());
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        impl.deposit(amount);
        uint256 id = encodeId(pid, gid, gauge.accCrvPerShare);
        _mint(msg.sender, id, amount, "");
        return id;
    }

    /// @notice Burn ERC1155 token to redeem ERC20 token back
    /// @param id Token id to burn
    /// @param amount Token amount to burn
    function burn(
        uint256 id,
        uint256 amount
    ) external nonReentrant returns (uint256) {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        (uint256 pid, uint256 gid, uint256 stCrvPerShare) = decodeId(id);
        _burn(msg.sender, id, amount);
        GaugeInfo storage gauge = gauges[pid][gid];
        ILiquidityGauge impl = gauge.impl;
        require(address(impl) != address(0), "gauge not registered");
        _mintCrv(gauge);
        impl.withdraw(amount);
        IERC20Upgradeable(impl.lp_token()).safeTransfer(msg.sender, amount);
        uint256 stCrv = (stCrvPerShare * amount) / 1e18;
        uint256 enCrv = (gauge.accCrvPerShare * amount) / 1e18;
        if (enCrv > stCrv) {
            CRV.safeTransfer(msg.sender, enCrv - stCrv);
        }
        return pid;
    }

    /// @notice Mint CRV reward for curve gauge
    /// @param gauge Curve gauge to mint reward
    function _mintCrv(GaugeInfo storage gauge) internal {
        ILiquidityGauge impl = gauge.impl;
        uint256 balanceBefore = CRV.balanceOf(address(this));
        ILiquidityGaugeMinter(impl.minter()).mint(address(impl));
        uint256 balanceAfter = CRV.balanceOf(address(this));
        uint256 gain = balanceAfter - balanceBefore;
        uint256 supply = impl.balanceOf(address(this));
        if (gain > 0 && supply > 0) {
            gauge.accCrvPerShare += (gain * 1e18) / supply;
        }
    }
}
