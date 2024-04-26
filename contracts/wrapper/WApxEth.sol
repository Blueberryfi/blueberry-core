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
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IWApxETH } from "../interfaces/IWApxETH.sol";
import { IApxEth } from "../interfaces/IApxETH.sol";
import "../interfaces/IWERC4626.sol";

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
    IApxEth private _apxETH;

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
        if (address(apxETH) == address(0) || address(owner) == address(0))
            revert Errors.ZERO_ADDRESS();

        __Ownable2Step_init();
        _transferOwnership(owner);
        __ReentrancyGuard_init();
        __ERC1155_init("wApxETH");

        _apxETH = IApxEth(apxETH);
    }

    // @inheritdoc IWERC4626
    function decodeId(uint256 tokenId) public pure returns (address) {
        return address(uint160(tokenId));
    }

    // @inheritdoc IWERC4626
    function encodeId(address token) public pure returns (uint256) {
        return uint256(uint160(token));
    }

    /// @inheritdoc IWERC4626
    function mint(uint256 amount) external nonReentrant returns (uint256) {
        IApxEth apxETH = getApxETH();
        address pxETH = apxETH.asset();
        IERC20Upgradeable(pxETH).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(pxETH).universalApprove(address(apxETH), amount);
        apxETH.deposit(amount, address(this));

        uint256 id = encodeId(apxETH.asset());

        _mint(msg.sender, id, amount, "");

        emit Minted(id, amount);

        return id;
    }

    /// @inheritdoc IWERC4626
    function burn(uint256 amount) external nonReentrant returns (uint256) {
        uint256 id = encodeId(address(getUnderlyingToken()));
        _burn(msg.sender, id, amount);

        IApxEth apxETH = getApxETH();
        address pxETH = apxETH.asset();

        // Collect lpToken + reward
        apxETH.harvest();
        uint256 assets = apxETH.redeem(apxETH.convertToShares(amount), address(this), address(this));
        uint256 reward = IERC20Upgradeable(pxETH).balanceOf(address(this)) - amount;

        /// Transfer LP Tokens
        IERC20Upgradeable(pxETH).safeTransfer(msg.sender, assets);

        emit Burned(id, amount);
        return reward;
    }

    /// @inheritdoc IWERC4626
    function balanceOf(address account) external view returns (uint256) {
        return balanceOf(account, encodeId(getApxETH().asset()));
    }

    /// @inheritdoc IWERC4626
    function getUnderlyingToken() public view returns (IERC20Upgradeable) {
        return IERC20Upgradeable(getApxETH().asset());
    }

    /**
     * @notice Get the apxETH contract address for this wrapper.
     * @return An IApxEth interface of the apxETH contract.
     */
    function getApxETH() public view returns (IApxEth) {
        return _apxETH;
    }
}
