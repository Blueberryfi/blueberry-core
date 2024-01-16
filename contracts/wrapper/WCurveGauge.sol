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
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/* solhint-enable max-line-length */

import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;

import { BaseWrapper } from "./BaseWrapper.sol";

import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { ICurveRegistry } from "../interfaces/curve/ICurveRegistry.sol";
import { ICurveGaugeController } from "../interfaces/curve/ICurveGaugeController.sol";
import { ILiquidityGauge } from "../interfaces/curve/ILiquidityGauge.sol";
import { ILiquidityGaugeMinter } from "../interfaces/curve/ILiquidityGaugeMinter.sol";
import { IWCurveGauge } from "../interfaces/IWCurveGauge.sol";

/**
 * @title WCurveGauge
 * @author BlueberryProtocol
 * @notice This contract allows for wrapping of Gauge positions into a custom ERC1155 token.
 * @dev LP Tokens are identified by tokenIds, which are encoded from the LP token address.
 *     This contract assumes leveraged LP Tokens are held in the BlueberryBank and do not generate yields.
 */
contract WCurveGauge is IWCurveGauge, BaseWrapper, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of Curve Registry
    ICurveRegistry private _registry;
    /// @dev Address of Curve Gauge Controller
    ICurveGaugeController private _gaugeController;
    /// @dev Address of CRV token
    IERC20Upgradeable private _crvToken;
    /// Mapping to keep track of accumulated CRV per share for each gauge.
    mapping(uint256 => uint256) private _accCrvPerShares;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with provided addresses.
     * @param crv Address of the CRV token.
     * @param crvRegistry Address of the Curve Registry.
     * @param gaugeController Address of the Gauge Controller.
     */
    function initialize(address crv, address crvRegistry, address gaugeController) external initializer {
        __ReentrancyGuard_init();
        __ERC1155_init("wCurveGauge");
        _crvToken = IERC20Upgradeable(crv);
        _registry = ICurveRegistry(crvRegistry);
        _gaugeController = ICurveGaugeController(gaugeController);
    }

    /// @inheritdoc IWCurveGauge
    function encodeId(uint256 pid, uint256 crvPerShare) public pure returns (uint256 id) {
        if (pid >= (1 << 16)) revert Errors.BAD_PID(pid);
        if (crvPerShare >= (1 << 240)) revert Errors.BAD_REWARD_PER_SHARE(crvPerShare);
        return (pid << 240) | crvPerShare;
    }

    /// @inheritdoc IWCurveGauge
    function decodeId(uint256 id) public pure returns (uint256 gid, uint256 crvPerShare) {
        gid = id >> 240; // Extracting the first 16 bits
        crvPerShare = id & ((1 << 240) - 1); // Extracting the last 240 bits
    }

    /// @inheritdoc IWCurveGauge
    function mint(uint256 gid, uint256 amount) external nonReentrant returns (uint256) {
        ILiquidityGauge gauge = ILiquidityGauge(_gaugeController.gauges(gid));
        if (address(gauge) == address(0)) revert Errors.ZERO_ADDRESS();

        _mintCrv(getCrvToken(), gauge, gid);
        IERC20Upgradeable lpToken = IERC20Upgradeable(gauge.lp_token());
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        IERC20(address(lpToken)).universalApprove(address(gauge), amount);
        gauge.deposit(amount);

        uint256 id = encodeId(gid, _accCrvPerShares[gid]);
        _validateTokenId(id);
        _mint(msg.sender, id, amount, "");

        emit Minted(id, gid, amount);

        return id;
    }

    /// @inheritdoc IWCurveGauge
    function burn(uint256 id, uint256 amount) external nonReentrant returns (uint256 rewards) {
        if (amount == type(uint256).max) {
            amount = balanceOf(msg.sender, id);
        }

        (uint256 gid, uint256 stCrvPerShare) = decodeId(id);
        _burn(msg.sender, id, amount);

        ILiquidityGauge gauge = ILiquidityGauge(_gaugeController.gauges(gid));

        if (address(gauge) == address(0)) revert Errors.ZERO_ADDRESS();

        IERC20Upgradeable crvToken = getCrvToken();

        _mintCrv(crvToken, gauge, gid);
        gauge.withdraw(amount);
        IERC20Upgradeable(gauge.lp_token()).safeTransfer(msg.sender, amount);

        uint256 stCrv = (stCrvPerShare * amount) / Constants.PRICE_PRECISION;
        uint256 enCrv = (_accCrvPerShares[gid] * amount) / Constants.PRICE_PRECISION;

        if (enCrv > stCrv) {
            rewards = enCrv - stCrv;
            crvToken.safeTransfer(msg.sender, rewards);
        }

        emit Burned(id, gid, amount);

        return rewards;
    }

    //// @inheritdoc IERC20Wrapper
    function pendingRewards(
        uint256 tokenId,
        uint256 amount
    ) public override returns (address[] memory tokens, uint256[] memory rewards) {
        (uint256 gid, uint256 stCrvPerShare) = decodeId(tokenId);

        ILiquidityGauge gauge = ILiquidityGauge(_gaugeController.gauges(gid));
        uint256 claimableCrv = gauge.claimable_tokens(address(this));
        uint256 supply = gauge.balanceOf(address(this));

        uint256 enCrvPerShare = _accCrvPerShares[gid] + ((claimableCrv * Constants.PRICE_PRECISION) / supply);
        uint256 crvRewards = enCrvPerShare > stCrvPerShare
            ? ((enCrvPerShare - stCrvPerShare) * amount) / Constants.PRICE_PRECISION
            : 0;

        tokens = new address[](1);
        rewards = new uint256[](1);
        tokens[0] = address(getCrvToken());
        rewards[0] = crvRewards;
    }

    /// @inheritdoc IWCurveGauge
    function getCrvToken() public view override returns (IERC20Upgradeable) {
        return _crvToken;
    }

    /// @inheritdoc IWCurveGauge
    function getGaugeController() external view override returns (ICurveGaugeController) {
        return _gaugeController;
    }

    /// @inheritdoc IWCurveGauge
    function getCurveRegistry() external view override returns (ICurveRegistry) {
        return _registry;
    }

    /// @inheritdoc IERC20Wrapper
    function getUnderlyingToken(uint256 id) external view override returns (address) {
        (uint256 gid, ) = decodeId(id);
        return getLpFromGaugeId(gid);
    }

    /// @inheritdoc IWCurveGauge
    function getAccumulatedCrvPerShare(uint256 gid) external view override returns (uint256) {
        return _accCrvPerShares[gid];
    }

    /// @inheritdoc IWCurveGauge
    function getLpFromGaugeId(uint256 gid) public view returns (address) {
        return ILiquidityGauge(_gaugeController.gauges(gid)).lp_token();
    }

    /**
     * @notice Mints CRV rewards for a curve gauge.
     * @param crvToken The CRV token interface
     * @param gauge Curve gauge to mint rewards for.
     * @param gid Gauge id.
     */
    function _mintCrv(IERC20Upgradeable crvToken, ILiquidityGauge gauge, uint256 gid) internal {
        uint256 balanceBefore = crvToken.balanceOf(address(this));
        ILiquidityGaugeMinter(gauge.minter()).mint(address(gauge));
        uint256 balanceAfter = crvToken.balanceOf(address(this));

        uint256 gain = balanceAfter - balanceBefore;
        uint256 supply = gauge.balanceOf(address(this));

        if (gain > 0 && supply > 0) {
            _accCrvPerShares[gid] += (gain * Constants.PRICE_PRECISION) / supply;
        }
    }
}
