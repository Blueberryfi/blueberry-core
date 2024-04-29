// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/**
 * @title IBasicSpell
 * @notice Interface for the Basic Spell contract.
 */
interface IBasicSpell {
    /**
     * @dev Defines strategies for Blueberry Protocol.
     * @param vault Address of the vault where assets are held.
     * @param minIsolatedCollateral Minimum size of isolated collateral in USD.
     * @param maxPositionSize Maximum size of the position in USD.
     */
    struct Strategy {
        address vault;
        uint256 minIsolatedCollateral;
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

    /**
     * @notice This event is emitted when a new strategy is added.
     * @param strategyId Unique identifier for the strategy.
     * @param vault Address of the vault where assets are held.
     * @param minCollSize Minimum size of the isolated collateral in USD.
     * @param maxPosSize Maximum size of the position in USD.
     */
    event StrategyAdded(uint256 strategyId, address vault, uint256 minCollSize, uint256 maxPosSize);

    /**
     * @notice This event is emitted when a strategy's min/max position size is updated.
     * @param strategyId Unique identifier for the strategy.
     * @param minCollSize Minimum size of the isolated collateral in USD.
     * @param maxPosSize Maximum size of the position in USD.
     */
    event StrategyPosSizeUpdated(uint256 strategyId, uint256 minCollSize, uint256 maxPosSize);

    /**
     * @notice This event is emitted when a strategy's collateral max LTV is updated.
     * @param strategyId Unique identifier for the strategy.
     * @param collaterals Array of collateral token addresses.
     * @param maxLTVs Array of maximum LTVs corresponding to the collaterals. (base 1e4)
     */
    event CollateralsMaxLTVSet(uint256 strategyId, address[] collaterals, uint256[] maxLTVs);

    /**
     * @notice Update the position sizes for a specific strategy.
     * @dev This function validates the inputs, updates the strategy's position sizes, and emits an event.
     * @param strategyId ID of the strategy to be updated.
     * @param minCollSize New minimum size of the isolated collateral for the strategy.
     * @param maxPosSize New maximum position size for the strategy.
     */
    function setPosSize(uint256 strategyId, uint256 minCollSize, uint256 maxPosSize) external;

    /**
     * @notice Set maximum Loan-To-Value (LTV) ratios for collaterals in a given strategy.
     * @dev This function validates the input arrays, sets the maxLTVs for each collateral, and emits an event.
     * @param strategyId ID of the strategy for which the maxLTVs are being set.
     * @param collaterals Array of addresses for each collateral token.
     * @param maxLTVs Array of maxLTV values corresponding to each collateral token.
     */
    function setCollateralsMaxLTVs(uint256 strategyId, address[] memory collaterals, uint256[] memory maxLTVs) external;
}
