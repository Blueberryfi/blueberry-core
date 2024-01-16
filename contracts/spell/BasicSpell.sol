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
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
/* solhint-enable max-line-length */

import { PSwapLib } from "../libraries/Paraswap/PSwapLib.sol";
import { UniversalERC20, IERC20 } from "../libraries/UniversalERC20.sol";

import "../utils/BlueberryConst.sol" as Constants;
import "../utils/BlueberryErrors.sol" as Errors;
import { ERC1155NaiveReceiver } from "../utils/ERC1155NaiveReceiver.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IERC20Wrapper } from "../interfaces/IERC20Wrapper.sol";
import { IWERC20 } from "../interfaces/IWERC20.sol";
import { IWETH } from "../interfaces/IWETH.sol";

/**
 * @title BasicSpell
 * @author BlueberryProtocol
 * @notice BasicSpell is the abstract contract that other spells utilize
 * @dev It extends functionalities from ERC1155NaiveReceiver, OwnableUpgradeable
 */
abstract contract BasicSpell is ERC1155NaiveReceiver, OwnableUpgradeable {
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                   STRUCTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Defines strategies for Blueberry Protocol.
     * @param vault Address of the vault where assets are held.
     * @param minPositionSize Minimum size of the position in USD.
     * @param maxPositionSize Maximum size of the position in USD.
     */
    struct Strategy {
        address vault;
        uint256 minPositionSize;
        uint256 maxPositionSize;
    }

    /**
     * @dev Defines parameters required for opening a new position.
     * @param strategyId Identifier for the strategy.
     * @param collToken Address of the collateral token (e.g., USDC).
     * @param collAmount Amount of user's collateral to deposit.
     * @param borrowToken Address of the token to borrow.
     * @param borrowAmount Amount to borrow from the bank.
     * @param farmingPoolId Identifier for the farming pool.
     */
    struct OpenPosParam {
        uint256 strategyId;
        address collToken;
        uint256 collAmount;
        address borrowToken;
        uint256 borrowAmount;
        uint256 farmingPoolId;
    }

    /**
     * @dev Defines parameters required for closing a position.
     * @param strategyId Identifier for the strategy to close.
     * @param collToken Address of the isolated collateral token.
     * @param borrowToken Address of the token representing the debt.
     * @param amountRepay Amount of debt to repay.
     * @param amountPosRemove Amount of position to withdraw.
     * @param amountShareWithdraw Amount of isolated collateral tokens to withdraw.
     * @param amountOutMin Minimum amount to receive after the operation (used to handle slippage).
     * @param amountToSwap Collateral amount to swap to repay debt for negative PnL
     * @param swapData Paraswap sawp data to swap collateral to borrow token
     */
    struct ClosePosParam {
        uint256 strategyId;
        address collToken;
        address borrowToken;
        uint256 amountRepay;
        uint256 amountPosRemove;
        uint256 amountShareWithdraw;
        uint256 amountOutMin;
        uint256 amountToSwap;
        bytes swapData;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// Reference to the bank contract interface.
    IBank internal _bank;
    /// Reference to the WERC20 contract interface.
    IWERC20 internal _werc20;
    /// Address of the Wrapped Ether contract.
    address internal _weth;
    /// @dev paraswap AugustusSwapper Address
    address internal _augustusSwapper;
    /// @dev paraswap TokenTransferProxy Address
    address internal _tokenTransferProxy;
    /// @dev strategyId => vault
    Strategy[] internal _strategies;
    /// @dev Mapping from strategy ID to collateral token and its maximum Loan-To-Value ratio.
    /// Note: LTV is in base 1e4 to provide precision.
    mapping(uint256 => mapping(address => uint256)) internal _maxLTV;
    /// @dev ETH address
    address internal constant _ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice This event is emitted when a new strategy is added.
     * @param strategyId Unique identifier for the strategy.
     * @param vault Address of the vault where assets are held.
     * @param minPosSize Minimum size of the position in USD.
     * @param maxPosSize Maximum size of the position in USD.
     */
    event StrategyAdded(uint256 strategyId, address vault, uint256 minPosSize, uint256 maxPosSize);

    /**
     * @notice This event is emitted when a strategy's min/max position size is updated.
     * @param strategyId Unique identifier for the strategy.
     * @param minPosSize Minimum size of the position in USD.
     * @param maxPosSize Maximum size of the position in USD.
     */
    event StrategyPosSizeUpdated(uint256 strategyId, uint256 minPosSize, uint256 maxPosSize);

    /**
     * @notice This event is emitted when a strategy's collateral max LTV is updated.
     * @param strategyId Unique identifier for the strategy.
     * @param collaterals Array of collateral token addresses.
     * @param maxLTVs Array of maximum LTVs corresponding to the collaterals. (base 1e4)
     */
    event CollateralsMaxLTVSet(uint256 strategyId, address[] collaterals, uint256[] maxLTVs);

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Modifier to ensure the provided strategyId exists within the strategies array.
     * @param strategyId The ID of the strategy to validate.
     */
    modifier existingStrategy(uint256 strategyId) {
        if (strategyId >= _strategies.length) {
            revert Errors.STRATEGY_NOT_EXIST(address(this), strategyId);
        }
        _;
    }

    /**
     * @dev Modifier to ensure the provided collateral address exists within the given strategy.
     * @param strategyId The ID of the strategy to validate.
     * @param col Address of the collateral token.
     */
    modifier existingCollateral(uint256 strategyId, address col) {
        if (_maxLTV[strategyId][col] == 0) {
            revert Errors.COLLATERAL_NOT_EXIST(strategyId, col);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
    /* solhint-disable func-name-mixedcase */
    /**
     * @notice Initializes the contract and sets the deployer as the initial owner.
     * @param bank The address of the bank contract.
     * @param werc20 The address of the wrapped ERC20 contract.
     * @param weth The address of the wrapped Ether token.
     * @param augustusSwapper Address of the paraswap AugustusSwapper.
     * @param tokenTransferProxy Address of the paraswap TokenTransferProxy.
     */
    function __BasicSpell_init(
        IBank bank,
        address werc20,
        address weth,
        address augustusSwapper,
        address tokenTransferProxy
    ) internal onlyInitializing {
        if (address(bank) == address(0) || address(werc20) == address(0) || address(weth) == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        __Ownable_init();

        _bank = bank;
        _werc20 = IWERC20(werc20);
        _weth = weth;
        _augustusSwapper = augustusSwapper;
        _tokenTransferProxy = tokenTransferProxy;

        IWERC20(werc20).setApprovalForAll(address(bank), true);
    }

    /* solhint-enable func-name-mixedcase */

    /**
     * @notice Adds a new strategy to the list of available strategies.
     * @dev Internal function that appends to the strategies array.
     * @dev Emit {StrategyAdded} event.
     * @param vault The address of the vault associated with this strategy.
     * @param minPosSize The minimum position size (USD value) for this strategy. Value is based on 1e18.
     * @param maxPosSize The maximum position size (USD value) for this strategy. Value is based on 1e18.
     */
    function _addStrategy(address vault, uint256 minPosSize, uint256 maxPosSize) internal {
        if (vault == address(0)) revert Errors.ZERO_ADDRESS();
        if (maxPosSize == 0) revert Errors.ZERO_AMOUNT();
        if (minPosSize >= maxPosSize) revert Errors.INVALID_POS_SIZE();

        _strategies.push(Strategy({ vault: vault, minPositionSize: minPosSize, maxPositionSize: maxPosSize }));

        emit StrategyAdded(_strategies.length - 1, vault, minPosSize, maxPosSize);
    }

    /**
     * @notice Update the position sizes for a specific strategy.
     * @dev This function validates the inputs, updates the strategy's position sizes, and emits an event.
     * @param strategyId ID of the strategy to be updated.
     * @param minPosSize New minimum position size for the strategy.
     * @param maxPosSize New maximum position size for the strategy.
     */
    function setPosSize(
        uint256 strategyId,
        uint256 minPosSize,
        uint256 maxPosSize
    ) external existingStrategy(strategyId) onlyOwner {
        if (maxPosSize == 0) revert Errors.ZERO_AMOUNT();
        if (minPosSize >= maxPosSize) revert Errors.INVALID_POS_SIZE();

        _strategies[strategyId].minPositionSize = minPosSize;
        _strategies[strategyId].maxPositionSize = maxPosSize;

        emit StrategyPosSizeUpdated(strategyId, minPosSize, maxPosSize);
    }

    /**
     * @notice Set maximum Loan-To-Value (LTV) ratios for collaterals in a given strategy.
     * @dev This function validates the input arrays, sets the maxLTVs for each collateral, and emits an event.
     * @param strategyId ID of the strategy for which the maxLTVs are being set.
     * @param collaterals Array of addresses for each collateral token.
     * @param maxLTVs Array of maxLTV values corresponding to each collateral token.
     */
    function setCollateralsMaxLTVs(
        uint256 strategyId,
        address[] memory collaterals,
        uint256[] memory maxLTVs
    ) external existingStrategy(strategyId) onlyOwner {
        if (collaterals.length != maxLTVs.length || collaterals.length == 0) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }

        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (collaterals[i] == address(0)) revert Errors.ZERO_ADDRESS();
            if (maxLTVs[i] == 0) revert Errors.ZERO_AMOUNT();
            _maxLTV[strategyId][collaterals[i]] = maxLTVs[i];
        }

        emit CollateralsMaxLTVSet(strategyId, collaterals, maxLTVs);
    }

    /**
     * @notice Internal function to validate if the current position adheres to the maxLTV of the strategy.
     * @dev If the debtValue of the position is greater than permissible, the transaction will revert.
     * @param strategyId Strategy ID to validate against.
     */
    function _validateMaxLTV(uint256 strategyId) internal {
        IBank bank = getBank();

        uint256 positionId = bank.POSITION_ID();
        IBank.Position memory pos = bank.getPositionInfo(positionId);
        uint256 debtValue = bank.getDebtValue(positionId);
        uint256 uValue = bank.getIsolatedCollateralValue(positionId);

        if (debtValue > (uValue * getMaxLTV(strategyId, pos.underlyingToken)) / Constants.DENOMINATOR) {
            revert Errors.EXCEED_MAX_LTV();
        }
    }

    /**
     * @notice Internal function to validate if the current position size is within the strategy's bounds.
     * @param strategyId Strategy ID to validate against.
     */
    function _validatePosSize(uint256 strategyId) internal {
        IBank bank = getBank();
        Strategy memory strategy = _strategies[strategyId];
        IBank.Position memory pos = bank.getCurrentPositionInfo();

        /// Get previous position size
        uint256 prevPosSize;
        if (pos.collToken != address(0)) {
            prevPosSize = bank.getOracle().getWrappedTokenValue(pos.collToken, pos.collId, pos.collateralSize);
        }

        /// Get newly added position size
        uint256 addedPosSize;
        IERC20 lpToken = IERC20(strategy.vault);
        uint256 lpBalance = lpToken.balanceOf(address(this));
        uint256 lpPrice = bank.getOracle().getPrice(address(lpToken));

        addedPosSize = (lpPrice * lpBalance) / 10 ** IERC20MetadataUpgradeable(address(lpToken)).decimals();

        // Check if position size is within bounds
        if (prevPosSize + addedPosSize > strategy.maxPositionSize) {
            revert Errors.EXCEED_MAX_POS_SIZE(strategyId);
        }
        if (prevPosSize + addedPosSize < strategy.minPositionSize) {
            revert Errors.EXCEED_MIN_POS_SIZE(strategyId);
        }
    }

    /**
     * @notice Internal function to refund the specified tokens to the current executor of the bank.
     * @param token Address of the token to refund.
     */
    function _doRefund(address token) internal {
        uint256 balance = IERC20(token).universalBalanceOf(address(this));
        if (balance > 0) {
            IERC20(token).universalTransfer(_bank.EXECUTOR(), balance);
        }
    }

    /**
     * @notice Internal function to cut a fee from the rewards.
     * @param token Address of the reward token.
     * @return left Amount remaining after the fee cut.
     */
    function _doCutRewardsFee(address token) internal returns (uint256 left) {
        uint256 rewardsBalance = IERC20(token).balanceOf(address(this));
        if (rewardsBalance > 0) {
            IBank bank = getBank();
            IERC20(token).universalApprove(address(bank.getFeeManager()), rewardsBalance);
            left = bank.getFeeManager().doCutRewardsFee(token, rewardsBalance);
        }
    }

    /**
     * @notice Internal function to cut the reward fee and refund the remaining rewards to the current bank executor.
     * @param token Address of the reward token.
     */
    function _doRefundRewards(address token) internal {
        _doCutRewardsFee(token);
        _doRefund(token);
    }

    /**
     * @notice Internall function Deposit specified collateral into the bank.
     * @dev Only deposits the collateral if the amount specified is greater than zero.
     * @param token Address of the isolated collateral token to be deposited.
     * @param amount Amount of tokens to be deposited.
     */
    function _doLend(address token, uint256 amount) internal {
        if (amount > 0) {
            _bank.lend(token, amount);
        }
    }

    /**
     * @notice Internal function Withdraw specified collateral from the bank.
     * @dev Only withdraws the collateral if the amount specified is greater than zero.
     * @param token Address of the isolated collateral token to be withdrawn.
     * @param amount Amount of tokens to be withdrawn.
     */
    function _doWithdraw(address token, uint256 amount) internal {
        if (amount > 0) {
            _bank.withdrawLend(token, amount);
        }
    }

    /**
     * @notice Internal function Withdraw specified collateral from the bank.
     * @dev Only withdraws the collateral if the amount specified is greater than zero.
     * @param collToken Address of the isolated collateral token to be withdrawn.
     * @param amount Amount of tokens to be withdrawn.
     * @param swapData Paraswap calldata
     */
    function _swapCollToDebt(address collToken, uint256 amount, bytes calldata swapData) internal {
        if (amount > 0 && swapData.length != 0) {
            PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, collToken, amount, swapData);
        }
    }

    /**
     * @notice Internal function Borrow specified tokens from the bank for the current executor.
     * @dev The borrowing happens only if the specified amount is greater than zero.
     * @param token Address of the token to be borrowed.
     * @param amount Amount of tokens to borrow.
     * @return borrowedAmount Actual amount of tokens borrowed.
     */
    function _doBorrow(address token, uint256 amount) internal returns (uint256 borrowedAmount) {
        if (amount > 0) {
            bool isETH = IERC20(token).isETH();

            IBank bank = getBank();
            address weth = getWETH();

            if (isETH) {
                borrowedAmount = bank.borrow(weth, amount);
                IWETH(weth).withdraw(borrowedAmount);
            } else {
                borrowedAmount = bank.borrow(token, amount);
            }
        }
    }

    /**
     * @notice Internall function Repay specified tokens to the bank for the current executor.
     * @dev Ensures approval of tokens to the bank and repays them.
     *      Only repays if the specified amount is greater than zero.
     * @param token Address of the token to be repaid to the bank.
     * @param amount Amount of tokens to repay.
     */
    function _doRepay(address token, uint256 amount) internal {
        if (amount > 0) {
            address t;
            bool isETH = IERC20(token).isETH();

            address weth = getWETH();

            if (isETH) {
                IWETH(weth).deposit{ value: amount }();
                t = weth;
            } else {
                t = token;
            }

            IBank bank = getBank();
            IERC20(t).universalApprove(address(bank), amount);
            bank.repay(t, amount);
        }
    }

    /**
     * @notice Internal function Deposit collateral tokens into the bank.
     * @dev Ensures approval of tokens to the werc20 contract, mints them,
     *      and then deposits them as collateral in the bank.
     *      Only deposits if the specified amount is greater than zero.
     * @param token Address of the collateral token to be deposited.
     * @param amount Amount of collateral tokens to deposit.
     */
    function _doPutCollateral(address token, uint256 amount) internal {
        if (amount > 0) {
            IWERC20 werc20 = getWrappedERC20();
            IERC20(token).universalApprove(address(werc20), amount);
            werc20.mint(token, amount);
            _bank.putCollateral(address(werc20), uint256(uint160(token)), amount);
        }
    }

    /**
     * @notice Internal function Withdraw collateral tokens from the bank.
     * @dev Burns the withdrawn tokens from werc20 contract after retrieval.
     *      Only withdraws if the specified amount is greater than zero.
     * @param token Address of the collateral token to be withdrawn.
     * @param amount Amount of collateral tokens to withdraw.
     */
    function _doTakeCollateral(address token, uint256 amount) internal {
        if (amount > 0) {
            amount = _bank.takeCollateral(amount);
            _werc20.burn(token, amount);
        }
    }

    /**
     * @notice Increase isolated collateral to support the position
     * @param token Isolated collateral token address
     * @param amount Amount of token to deposit and increase position
     */
    function increasePosition(address token, uint256 amount) external {
        /// 1. Deposit isolated collaterals on Blueberry Money Market
        _doLend(token, amount);
    }

    /**
     * @dev Reduce the isolated collateral of a position.
     * @param strategyId The ID of the strategy being used.
     * @param collToken Address of the isolated collateral token.
     * @param collShareAmount Amount of isolated collateral to reduce.
     */
    function reducePosition(uint256 strategyId, address collToken, uint256 collShareAmount) external {
        // Validate strategy id
        IBank.Position memory pos = _bank.getCurrentPositionInfo();
        address unwrappedCollToken = IERC20Wrapper(pos.collToken).getUnderlyingToken(pos.collId);
        if (_strategies[strategyId].vault != unwrappedCollToken) {
            revert Errors.INCORRECT_STRATEGY_ID(strategyId);
        }

        _doWithdraw(collToken, collShareAmount);
        _doRefund(collToken);
        _validateMaxLTV(strategyId);
    }

    /// @notice Fetch the bank contract address.
    function getBank() public view returns (IBank) {
        return _bank;
    }

    /// @notice Fetch the WERC20 contract address.
    function getWrappedERC20() public view returns (IWERC20) {
        return _werc20;
    }

    /// @notice Fetch the WETH contract address.
    function getWETH() public view returns (address) {
        return _weth;
    }

    /// @notice Fetch the AugustusSwapper contract address.
    function getAugustusSwapper() external view returns (address) {
        return _augustusSwapper;
    }

    /// @notice Fetch the TokenTransferProxy contract address.
    function getTokenTransferProxy() external view returns (address) {
        return _tokenTransferProxy;
    }

    /**
     * @notice Fetch the strategy by its strategyId.
     * @param strategyId The ID of the strategy to fetch.
     * @return Strategy struct containing the vault address, min/max position sizes.
     */
    function getStrategy(uint256 strategyId) external view returns (Strategy memory) {
        return _strategies[strategyId];
    }

    /**
     * @notice Fetch the maximum Loan-To-Value (LTV) ratio for a given collateral token.
     * @param strategyId The ID of the strategy to fetch the LTV for.
     * @param collateral The address of the collateral token.
     * @return The maximum LTV ratio for the given collateral token.
     */
    function getMaxLTV(uint256 strategyId, address collateral) public view returns (uint256) {
        return _maxLTV[strategyId][collateral];
    }

    /// @dev Fallback function.
    receive() external payable {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     *      variables without shifting down storage in the inheritance chain.
     *      See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}
