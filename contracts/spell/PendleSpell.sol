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

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { PSwapLib } from "../libraries/Paraswap/PSwapLib.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { BasicSpell } from "./BasicSpell.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IWERC20 } from "../interfaces/IWERC20.sol";
import { IPMarket, IPPrincipalToken, IPYieldToken } from "@pendle/core-v2/contracts/interfaces/IPMarket.sol";
import { IPendleRouter } from "../interfaces/pendle-v2/IPendleRouter.sol";
import { ApproxParams, TokenInput, TokenOutput, LimitOrderData } from "../interfaces/pendle-v2/IPendleRouter.sol";

// import { IWPendleGauge } from "../interfaces/IWPendleGauge.sol";
import { IPendleSpell } from "../interfaces/spell/IPendleSpell.sol";

/**
 * @title PendleSpell
 * @author BlueberryProtocol
 * @notice PendleSpell is the factory contract that
 *         defines how Blueberry Protocol interacts with Pendle PTs and LPs
 */
contract PendleSpell is IPendleSpell, BasicSpell {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Address of the Pendle Router contract
    IPendleRouter private _pendleRouter;
    /// @dev Address of PNP token
    address private _penPie;
    /// @dev Mapping of Principal Tokens to their respective markets
    mapping(address => address) private _ptToMarket;

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
     * @notice Initializes the contract with required parameters.
     * @param bank Reference to the Bank contract.
     * @param werc20 Reference to the WERC20 contract.
     * @param weth Address of the wrapped Ether token.
     * @param pendleRouter Address of the Pendle Router contract.
     * @param wPendleGauge Address of the wrapped Pendle Gauge contract.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     * @param owner Address of the owner of the contract.
     */
    function initialize(
        IBank bank,
        address werc20,
        address weth,
        address pendleRouter,
        address wPendleGauge,
        address augustusSwapper,
        address tokenTransferProxy,
        address owner
    ) external initializer {
        __BasicSpell_init(bank, werc20, weth, augustusSwapper, tokenTransferProxy, owner);
        if (pendleRouter == address(0) || wPendleGauge == address(0)) revert Errors.ZERO_ADDRESS();

        // _penPie = address(IWAuraBooster(wAuraBooster).getAuraToken());
        _pendleRouter = IPendleRouter(pendleRouter);
        // IWAuraBooster(wAuraBooster).setApprovalForAll(address(bank), true);
    }

    /// @inheritdoc IPendleSpell
    function addStrategy(address token, uint256 minCollSize, uint256 maxPosSize) external override onlyOwner {
        /// TODO: Handle expirations
        _addStrategy(token, minCollSize, maxPosSize);
    }

    /// @inheritdoc IPendleSpell
    function openPosition(OpenPosParam calldata param, uint256 minimumPt, bytes memory data) external override {
        address pt = _strategies[param.strategyId].vault;

        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(param.collToken, param.collAmount);

        /// 2. Borrow funds based on specified amount
        _doBorrow(param.borrowToken, param.borrowAmount);

        /// 3. Swap borrowToken to PT
        (ApproxParams memory params, TokenInput memory input, LimitOrderData memory limitOrder) = abi.decode(
            data,
            (ApproxParams, TokenInput, LimitOrderData)
        );

        (uint256 ptAmount, , ) = IPendleRouter(_pendleRouter).swapExactTokenForPt(
            address(this),
            _ptToMarket[pt],
            minimumPt,
            params,
            input,
            limitOrder
        );

        /// 4. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 5. Validate Max Pos Size
        _validatePosSize(param.strategyId);

        /// 6. Wrap PT and deposit to Bank
        _doPutCollateral(pt, ptAmount);
    }

    // function openPositionFarm(OpenPosParam calldata param, uint256 minimumLP, bytes memory data) external override {}

    function closePosition(ClosePosParam calldata param, bytes memory data) external override {
        IBank bank = getBank();
        IWERC20 werc20 = getWrappedERC20();
        address pt = _strategies[param.strategyId].vault;

        /// 1. Validate input data
        IBank.Position memory pos = bank.getCurrentPositionInfo();
        address posCollToken = pos.collToken;
        uint256 collId = pos.collId;

        if (IWERC20(posCollToken).getUnderlyingToken(collId) != pt) revert Errors.INCORRECT_UNDERLYING(pt);
        if (posCollToken != address(werc20)) revert Errors.INCORRECT_COLTOKEN(posCollToken);

        /// 2. Take out collateral
        uint256 burnAmount = bank.takeCollateral(param.amountPosRemove);
        werc20.burn(pt, burnAmount);

        /// 3. Exit PT position
        {
            (TokenOutput memory output, LimitOrderData memory limitOrder) = abi.decode(
                data,
                (TokenOutput, LimitOrderData)
            );
            address market = _ptToMarket[pt];
            (, , IPYieldToken yt) = IPMarket(market).readTokens();

            // If the PT has expired, we need to redeem, if not we can swap
            if (IPMarket(market).isExpired()) {
                IPendleRouter(_pendleRouter).redeemPyToToken(msg.sender, address(yt), burnAmount, output);
            } else {
                IPendleRouter(_pendleRouter).swapExactPtForToken(msg.sender, market, burnAmount, output, limitOrder);
            }
        }

        /// 4. Withdraw isolated collateral from Bank
        _doWithdraw(param.collToken, param.amountShareWithdraw);

        /// 5. Swap some collateral to repay debt(for negative PnL)
        _swapCollToDebt(param.collToken, param.amountToSwap, param.swapData);

        /// 6. Repay
        {
            uint256 amountRepay = param.amountRepay;
            if (amountRepay == type(uint256).max) {
                amountRepay = bank.currentPositionDebt(bank.POSITION_ID());
            }
            _doRepay(param.borrowToken, amountRepay);
        }

        /// 7. Validate MAX LTV
        _validateMaxLTV(param.strategyId);

        /// 8. Refund
        _doRefund(param.borrowToken);
        _doRefund(param.collToken);
    }

    // function closePositionFarm(
    //     ClosePosParam calldata param,
    //     uint256[] calldata expectedRewards,
    //     bytes[] calldata swapDatas
    // ) external override {}

    function getPendle() external view override returns (address) {}

    // function getPenPie() external view override returns (address) {}
}
