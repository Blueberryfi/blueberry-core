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
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
/* solhint-enable max-line-length */

import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BBMath } from "../libraries/BBMath.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IWERC4626 } from "../interfaces/IWERC4626.sol";
import { IApxEth } from "../interfaces/IApxETH.sol";

/**
 * @title WApxEth
 * @author BlueberryProtocol
 * @notice Wrapped ApxETH is the wrapper for the Auto-compounding Pirex Ether (apxETH) contract
 * @dev PxETH Lp Tokens will be wrapped here and held in BlueberryBank.
 *      At the same time, the pxETH will be deposited to apxETH contract to generate yield
 *      LP Tokens are identified by tokenIds encoded from lp token address and accPerShare of deposited time
 */
contract WApxEth is IWERC4626, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    using BBMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev apxETH contract address
    address private _apxETH;

    /// @dev pxETH contract address
    address private _pxETH;

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
     * @notice Initializes the contract with the given apxETH contract address.
     * @param apxETH Address of the Auto-compounding Pirex Ether (apxETH)
     * @param owner The owner of the contract.
     */
    function initialize(address apxETH, address owner) external initializer {
        if (address(apxETH) == address(0) || address(owner) == address(0)) revert Errors.ZERO_ADDRESS();

        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("wApxETH");

        _apxETH = apxETH;
        _pxETH = IERC4626(apxETH).asset();
    }

    /// @inheritdoc IWERC4626
    function mint(uint256 amount) external override nonReentrant returns (uint256 id) {
        IApxEth apxETH = IApxEth(_apxETH);
        address pxETH = _pxETH;
        IERC20Upgradeable(pxETH).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(pxETH).universalApprove(address(apxETH), amount);
        apxETH.deposit(amount, address(this));

        uint256 rewardPerToken = apxETH.rewardPerToken();

        id = encodeId(rewardPerToken);
        _mint(msg.sender, id, amount, "");

        emit Minted(id, amount);
    }

    /// @inheritdoc IWERC4626
    function burn(uint256 id, uint256 amount) external nonReentrant returns (uint256 assetsReceived) {
        IApxEth apxETH = IApxEth(_apxETH);
        address pxETH = _pxETH;

        (, uint256[] memory rewards) = pendingRewards(id, amount);
        _burn(msg.sender, id, amount);
        amount += rewards[0];

        uint256 shares = apxETH.convertToShares(amount);
        uint256 apxEthBal = apxETH.balanceOf(address(this));
        if (shares > apxEthBal) {
            shares = apxEthBal;
        }
        assetsReceived = apxETH.redeem(shares, address(this), address(this));

        /// Transfer LP Tokens
        IERC20Upgradeable(pxETH).safeTransfer(msg.sender, assetsReceived);

        emit Burned(id, amount);
    }

    /// @notice IWERC4626
    function pendingRewards(
        uint256 rewardId,
        uint256 amount
    ) public view returns (address[] memory tokens, uint256[] memory rewards) {
        IApxEth apxETH = IApxEth(_apxETH);
        uint256 prevRewardPerToken = decodeId(rewardId);
        uint256 currRewardPerToken = apxETH.rewardPerToken();
        uint256 share = currRewardPerToken > prevRewardPerToken ? currRewardPerToken - prevRewardPerToken : 0;

        tokens = new address[](1);
        rewards = new uint256[](1);

        tokens[0] = apxETH.asset();
        rewards[0] = (share * amount) / (10 ** apxETH.decimals());
    }

    /// @inheritdoc IERC20Wrapper
    function getUnderlyingToken(uint256 /*tokenId*/) external view override returns (address) {
        return _apxETH;
    }

    /// @inheritdoc IWERC4626
    function getAsset() external view override returns (IERC20) {
        return IERC20(_pxETH);
    }

    // @inheritdoc IWERC4626
    function decodeId(uint256 rewardId) public pure returns (uint256) {
        return rewardId;
    }

    // @inheritdoc IWERC4626
    function encodeId(uint256 rewardPerToken) public pure returns (uint256) {
        return rewardPerToken;
    }
}
