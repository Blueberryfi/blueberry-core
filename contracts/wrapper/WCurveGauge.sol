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
import "../utils/EnsureApprove.sol";
import "../interfaces/IERC20Wrapper.sol";
import "../interfaces/IWCurveGauge.sol";
import "../interfaces/curve/ILiquidityGauge.sol";

    /*//////////////////////////////////////////////////////////////////////////
                                     INTERFACE
    //////////////////////////////////////////////////////////////////////////*/
interface ILiquidityGaugeMinter {
    function mint(address gauge) external;
}

/// @title WCurveGauge - Wrapper for Curve Gauge Positions.
/// @author BlueberryProtocol
/// @notice This contract allows for wrapping of Gauge positions into a custom ERC1155 token.
/// @dev LP Tokens are identified by tokenIds, which are encoded from the LP token address.
///      This contract assumes leveraged LP Tokens are held in the BlueberryBank and do not generate yields.
contract WCurveGauge is
    ERC1155Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    EnsureApprove,
    IERC20Wrapper,
    IWCurveGauge
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/
    
    /// @dev Address of Curve Registry
    ICurveRegistry public registry;
    /// @dev Address of Curve Gauge Controller
    ICurveGaugeController public gaugeController;
    /// @dev Address of CRV token
    IERC20Upgradeable public CRV;
    /// Mapping to keep track of accumulated CRV per share for each gauge.
    mapping(uint256 => uint256) public accCrvPerShares;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with provided addresses.
    /// @param crv_ Address of the CRV token.
    /// @param crvRegistry_ Address of the Curve Registry.
    /// @param gaugeController_ Address of the Gauge Controller.
    function initialize(
        address crv_,
        address crvRegistry_,
        address gaugeController_
    ) external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("WCurveGauge");
        CRV = IERC20Upgradeable(crv_);
        registry = ICurveRegistry(crvRegistry_);
        gaugeController = ICurveGaugeController(gaugeController_);
    }

    /// @notice Encode pool id and CRV amount per share into a unique ERC1155 token id.
    /// @param pid Pool id (the first 16-bit).
    /// @param crvPerShare CRV amount per share (multiplied by 1e18 - for the last 240 bits).
    /// @return id The unique token id.
    function encodeId(
        uint256 pid,
        uint256 crvPerShare
    ) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (crvPerShare >= (1 << 240))
            revert Errors.BAD_REWARD_PER_SHARE(crvPerShare);
        return (pid << 240) | crvPerShare;
    }

    /// @notice Decode an ERC1155 token id into its components: pool id and CRV per share.
    /// @param id Unique token id.
    /// @return gid The pool id.
    /// @return crvPerShare The CRV amount per share.
    function decodeId(
        uint256 id
    ) public pure returns (uint256 gid, uint256 crvPerShare) {
        gid = id >> 240; // Extracting the first 16 bits
        crvPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    /// @notice Get the underlying ERC20 token for a given ERC1155 token id.
    /// @param id The ERC1155 token id.
    /// @return Address of the underlying ERC20 token.
    function getUnderlyingToken(
        uint256 id
    ) external view override returns (address) {
        (uint256 gid, ) = decodeId(id);
        return getLpFromGaugeId(gid);
    }

    /// @notice Given a gauge id, fetch the associated LP token.
    /// @param gid The gauge id.
    /// @return Address of the LP token.
    function getLpFromGaugeId(uint256 gid) public view returns (address) {
        return ILiquidityGauge(gaugeController.gauges(gid)).lp_token();
    }

    /// @notice Calculate pending rewards for a given ERC1155 token amount.
    /// @param tokenId Token id.
    /// @param amount Amount of tokens.
    /// @return tokens Addresses of reward tokens.
    /// @return rewards Amounts of rewards corresponding to each token.
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    )
        public
        override
        returns (address[] memory tokens, uint256[] memory rewards)
    {
        (uint256 gid, uint256 stCrvPerShare) = decodeId(tokenId);

        ILiquidityGauge gauge = ILiquidityGauge(gaugeController.gauges(gid));
        uint256 claimableCrv = gauge.claimable_tokens(address(this));
        uint256 supply = gauge.balanceOf(address(this));
        uint256 enCrvPerShare = accCrvPerShares[gid] +
            ((claimableCrv * 1e18) / supply);

        uint256 crvRewards = enCrvPerShare > stCrvPerShare
            ? ((enCrvPerShare - stCrvPerShare) * amount) / 1e18
            : 0;

        tokens = new address[](1);
        rewards = new uint256[](1);
        tokens[0] = address(CRV);
        rewards[0] = crvRewards;
    }

    /// @notice Wrap an LP token into an ERC1155 token.
    /// @param gid Gauge id.
    /// @param amount Amount of LP tokens to wrap.
    /// @return id The resulting ERC1155 token id.
    function mint(
        uint256 gid,
        uint256 amount
    ) external nonReentrant returns (uint256) {
        ILiquidityGauge gauge = ILiquidityGauge(gaugeController.gauges(gid));
        if (address(gauge) == address(0)) revert Errors.NO_GAUGE();

        _mintCrv(gauge, gid);
        IERC20Upgradeable lpToken = IERC20Upgradeable(gauge.lp_token());
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        _ensureApprove(address(lpToken), address(gauge), amount);
        gauge.deposit(amount);

        uint256 id = encodeId(gid, accCrvPerShares[gid]);
        _mint(msg.sender, id, amount, "");
        return id;
    }

    /// @notice Unwrap an ERC1155 token back into its underlying LP token.
    /// @param id ERC1155 token id.
    /// @param amount Amount of ERC1155 tokens to unwrap.
    /// @return rewards CRV rewards earned during the period the LP token was wrapped.
    function burn(
        uint256 id,
        uint256 amount
    ) external nonReentrant returns (uint256 rewards) {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }
        (uint256 gid, uint256 stCrvPerShare) = decodeId(id);
        _burn(msg.sender, id, amount);
        ILiquidityGauge gauge = ILiquidityGauge(gaugeController.gauges(gid));
        require(address(gauge) != address(0), "gauge not registered");
        _mintCrv(gauge, gid);
        gauge.withdraw(amount);
        IERC20Upgradeable(gauge.lp_token()).safeTransfer(msg.sender, amount);
        uint256 stCrv = (stCrvPerShare * amount) / 1e18;
        uint256 enCrv = (accCrvPerShares[gid] * amount) / 1e18;
        if (enCrv > stCrv) {
            rewards = enCrv - stCrv;
            CRV.safeTransfer(msg.sender, rewards);
        }
        return rewards;
    }

    /// @dev Internal function to mint CRV rewards for a curve gauge.
    /// @param gauge Curve gauge to mint rewards for.
    /// @param gid Gauge id.
    function _mintCrv(ILiquidityGauge gauge, uint256 gid) internal {
        uint256 balanceBefore = CRV.balanceOf(address(this));
        ILiquidityGaugeMinter(gauge.minter()).mint(address(gauge));
        uint256 balanceAfter = CRV.balanceOf(address(this));
        uint256 gain = balanceAfter - balanceBefore;
        uint256 supply = gauge.balanceOf(address(this));
        if (gain > 0 && supply > 0) {
            accCrvPerShares[gid] += (gain * 1e18) / supply;
        }
    }
}
