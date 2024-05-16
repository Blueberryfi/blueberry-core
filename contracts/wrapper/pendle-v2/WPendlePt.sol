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
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
/* solhint-enable max-line-length */

import { ApproxParams, TokenInput, TokenOutput, LimitOrderData } from "../../interfaces/pendle-v2/IPendleRouter.sol";
import { IPMarket, IPYieldToken } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import { IPendleRouter } from "../../interfaces/pendle-v2/IPendleRouter.sol";
import { IRewardManager } from "../../interfaces/pendle-v2/IRewardManager.sol";
import "../../utils/BlueberryErrors.sol" as Errors;

import { IWPendlePt } from "../../interfaces/IWPendlePt.sol";
import { IERC20Wrapper } from "../../interfaces/IERC20Wrapper.sol";

/**
 * @title WPendleGauge
 * @author BlueberryProtocol
 * @notice Wrapped Pendle Gauge is the wrapper for PT positions on Pendle Finance
 * @dev Leveraged PT Tokens will be minted and wrapped here and be held in BlueberryBank
 *      PT Tokens are identified by tokenIds
 */
contract WPendlePt is IWPendlePt, ERC1155Upgradeable, ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/
    /// @notice The Pendle Router contract
    IPendleRouter private _pendleRouter;

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
        __ERC1155_init("wPendlePt");

        _pendleRouter = pendleRouter;
    }

    /// @inheritdoc IWPendlePt
    function mint(
        address market,
        uint256 amount,
        bytes memory data
    ) external override nonReentrant returns (uint256 id, uint256 ptAmount) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();

        (ApproxParams memory params, TokenInput memory input, LimitOrderData memory limitOrder) = abi.decode(
            data,
            (ApproxParams, TokenInput, LimitOrderData)
        );

        // Deposit into the Pendle Market
        (ptAmount, , ) = IPendleRouter(_pendleRouter).swapExactTokenForPt(
            address(this),
            market,
            amount, // adjust for slippage
            params,
            input,
            limitOrder
        );

        id = _encodeTokenId(market);
        _mint(msg.sender, id, ptAmount, "");
    }

    /// @inheritdoc IWPendlePt
    function burn(
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external override nonReentrant returns (uint256 amountOut) {
        if (amount == 0) revert Errors.ZERO_AMOUNT();

        address market = _decodeTokenId(id);
        (, , IPYieldToken yt) = IPMarket(market).readTokens();
        (TokenOutput memory output, LimitOrderData memory limitOrder) = abi.decode(data, (TokenOutput, LimitOrderData));

        // If the PT has expired, we need to redeem, if not we can swap
        if (IPMarket(market).isExpired()) {
            (amountOut, ) = IPendleRouter(_pendleRouter).redeemPyToToken(msg.sender, address(yt), amount, output);
        } else {
            (amountOut, , ) = IPendleRouter(_pendleRouter).swapExactPtForToken(
                msg.sender,
                market,
                amount,
                output,
                limitOrder
            );
        }

        _burn(msg.sender, id, amount);
    }

    /// @inheritdoc IWPendlePt
    function getMarket(uint256 id) external pure override returns (address market) {
        return _decodeTokenId(id);
    }

    /**
     * @dev Encodes a given Pendle market into a unique tokenId for ERC1155.
     * @param market The address of the Pendle market.
     * @return The unique tokenId.
     */
    function _encodeTokenId(address market) internal pure returns (uint) {
        return uint256(uint160(market));
    }

    /**
     * @dev Decodes a given tokenId back into its correspondingPendle market address.
     * @param tokenId The tokenId to decode.
     * @return The decoded Pendle market address.
     */
    function _decodeTokenId(uint tokenId) internal pure returns (address) {
        return address(uint160(tokenId));
    }
}
