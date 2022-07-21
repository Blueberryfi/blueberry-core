// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../Governable.sol';
import '../utils/HomoraMath.sol';
import '../interfaces/IERC20Wrapper.sol';
import '../interfaces/ICurveRegistry.sol';
import '../interfaces/ILiquidityGauge.sol';

interface ILiquidityGaugeMinter {
    function mint(address gauge) external;
}

contract WLiquidityGauge is
    ERC1155('WLiquidityGauge'),
    ReentrancyGuard,
    IERC20Wrapper,
    Governable
{
    using HomoraMath for uint256;
    using SafeERC20 for IERC20;

    struct GaugeInfo {
        ILiquidityGauge impl; // Gauge implementation
        uint256 accCrvPerShare; // Accumulated CRV per share
    }

    ICurveRegistry public immutable registry; // Curve registry
    IERC20 public immutable crv; // CRV token
    /// @dev Mapping from pool id to (mapping from gauge id to GaugeInfo)
    mapping(uint256 => mapping(uint256 => GaugeInfo)) public gauges;

    constructor(ICurveRegistry _registry, IERC20 _crv) {
        __Governable__init();
        registry = _registry;
        crv = _crv;
    }

    /// @dev Encode pid, gid, crvPerShare to a ERC1155 token id
    /// @param pid Curve pool id (10-bit)
    /// @param gid Curve gauge id (6-bit)
    /// @param crvPerShare CRV amount per share, multiplied by 1e18 (240-bit)
    function encodeId(
        uint256 pid,
        uint256 gid,
        uint256 crvPerShare
    ) public pure returns (uint256) {
        require(pid < (1 << 10), 'bad pid');
        require(gid < (1 << 6), 'bad gid');
        require(crvPerShare < (1 << 240), 'bad crv per share');
        return (pid << 246) | (gid << 240) | crvPerShare;
    }

    /// @dev Decode ERC1155 token id to pid, gid, crvPerShare
    /// @param id Token id to decode
    function decodeId(uint256 id)
        public
        pure
        returns (
            uint256 pid,
            uint256 gid,
            uint256 crvPerShare
        )
    {
        pid = id >> 246; // First 10 bits
        gid = (id >> 240) & (63); // Next 6 bits
        crvPerShare = id & ((1 << 240) - 1); // Last 240 bits
    }

    /// @dev Get underlying ERC20 token of ERC1155 given pid, gid
    /// @param pid pool id
    /// @param gid gauge id
    function getUnderlyingTokenFromIds(uint256 pid, uint256 gid)
        public
        view
        returns (address)
    {
        ILiquidityGauge impl = gauges[pid][gid].impl;
        require(address(impl) != address(0), 'no gauge');
        return impl.lp_token();
    }

    /// @dev Get underlying ERC20 token of ERC1155 given token id
    /// @param id Token id
    function getUnderlyingToken(uint256 id)
        external
        view
        override
        returns (address)
    {
        (uint256 pid, uint256 gid, ) = decodeId(id);
        return getUnderlyingTokenFromIds(pid, gid);
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

    /// @dev Register curve gauge to storage given pool id and gauge id
    /// @param pid Pool id
    /// @param gid Gauge id
    function registerGauge(uint256 pid, uint256 gid) external onlyGov {
        require(
            address(gauges[pid][gid].impl) == address(0),
            'gauge already exists'
        );
        address pool = registry.pool_list(pid);
        require(pool != address(0), 'no pool');
        (address[10] memory _gauges, ) = registry.get_gauges(pool);
        address gauge = _gauges[gid];
        require(gauge != address(0), 'no gauge');
        IERC20 lpToken = IERC20(ILiquidityGauge(gauge).lp_token());
        lpToken.approve(gauge, 0);
        lpToken.approve(gauge, type(uint256).max);
        gauges[pid][gid] = GaugeInfo({
            impl: ILiquidityGauge(gauge),
            accCrvPerShare: 0
        });
    }

    /// @dev Mint ERC1155 token for the given ERC20 token
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
        require(address(impl) != address(0), 'gauge not registered');
        mintCrv(gauge);
        IERC20 lpToken = IERC20(impl.lp_token());
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        impl.deposit(amount);
        uint256 id = encodeId(pid, gid, gauge.accCrvPerShare);
        _mint(msg.sender, id, amount, '');
        return id;
    }

    /// @dev Burn ERC1155 token to redeem ERC20 token back
    /// @param id Token id to burn
    /// @param amount Token amount to burn
    function burn(uint256 id, uint256 amount)
        external
        nonReentrant
        returns (uint256)
    {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        (uint256 pid, uint256 gid, uint256 stCrvPerShare) = decodeId(id);
        _burn(msg.sender, id, amount);
        GaugeInfo storage gauge = gauges[pid][gid];
        ILiquidityGauge impl = gauge.impl;
        require(address(impl) != address(0), 'gauge not registered');
        mintCrv(gauge);
        impl.withdraw(amount);
        IERC20(impl.lp_token()).safeTransfer(msg.sender, amount);
        uint256 stCrv = (stCrvPerShare * amount).divCeil(1e18);
        uint256 enCrv = (gauge.accCrvPerShare * amount) / 1e18;
        if (enCrv > stCrv) {
            crv.safeTransfer(msg.sender, enCrv - stCrv);
        }
        return pid;
    }

    /// @dev Mint CRV reward for curve gauge
    /// @param gauge Curve gauge to mint reward
    function mintCrv(GaugeInfo storage gauge) internal {
        ILiquidityGauge impl = gauge.impl;
        uint256 balanceBefore = crv.balanceOf(address(this));
        ILiquidityGaugeMinter(impl.minter()).mint(address(impl));
        uint256 balanceAfter = crv.balanceOf(address(this));
        uint256 gain = balanceAfter - balanceBefore;
        uint256 supply = impl.balanceOf(address(this));
        if (gain > 0 && supply > 0) {
            gauge.accCrvPerShare += (gain * 1e18) / supply;
        }
    }
}
