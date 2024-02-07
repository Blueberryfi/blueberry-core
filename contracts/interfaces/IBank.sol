// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import { IProtocolConfig } from "./IProtocolConfig.sol";
import { IFeeManager } from "./IFeeManager.sol";
import { ICoreOracle } from "./ICoreOracle.sol";

/**
 * @title IBank
 * @notice Interface for the bank operations, including lending, borrowing, and management of collateral positions.
 */
interface IBank {
    /*//////////////////////////////////////////////////////////////////////////
                                       STRUCTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Represents the configuration and current state of a bank.
    struct Bank {
        bool isListed; /// @dev Indicates if this bank is active.
        uint8 index; /// @dev Index for reverse lookups.
        address hardVault; /// @dev Address of the hard vault.
        address softVault; /// @dev Address of the soft vault.
        address bToken; /// @dev Address of the bToken associated with the bank.
        uint256 totalShare; /// @dev Total shares of debt across all open positions.
        uint256 liqThreshold; /// @dev Liquidation threshold (e.g., 85% for volatile tokens,
        /// 90% for stablecoins). Base: 1e4
    }

    /// @notice Represents a position in the bank, including both debt and collateral.
    struct Position {
        address owner; /// @dev Address of the position's owner.
        address collToken; /// @dev Address of the ERC1155 token used as collateral.
        address underlyingToken; /// @dev Address of the isolated underlying collateral token.
        address debtToken; /// @dev Address of the debt token.
        uint256 underlyingVaultShare; /// @dev Amount of vault share for isolated underlying collateral.
        uint256 collId; /// @dev Token ID of the ERC1155 collateral.
        uint256 collateralSize; /// @dev Amount of wrapped token used as collateral.
        uint256 debtShare; /// @dev Debt share of the given debt token for the bank.
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new bank is added by the owner.
    event AddBank(
        address token, /// @dev The primary token associated with the bank.
        address bToken, /// @dev The corresponding bToken for the bank.
        address softVault, /// @dev Address of the soft vault.
        address hardVault /// @dev Address of the hard vault.
    );

    /// @notice Emitted when a bank is modified by the owner.
    event ModifyBank(
        address token, /// @dev The primary token associated with the bank.
        address bToken, /// @dev The corresponding bToken for the bank.
        address softVault, /// @dev Address of the soft vault.
        address hardVault /// @dev Address of the hard vault.
    );

    /// @notice Emitted when the oracle's address is updated by the owner.
    event SetOracle(address oracle); /// New address of the oracle.

    /// @notice Emitted when a Wrapped ERC1155 token is whitelisted or removed by the owner.
    event SetWhitelistERC1155(
        address indexed token, /// Address of the Wrapped ERC1155 token.
        bool isWhitelisted /// True if whitelisted, false otherwise.
    );

    /// @notice Emitted when a token is whitelisted or removed by the owner.
    event SetWhitelistToken(
        address indexed token, /// Address of the token.
        bool isWhitelisted /// True if whitelisted, false otherwise.
    );

    /// @notice Emitted when tokens are lent to the bank.
    event Lend(
        uint256 positionId, /// Position ID associated with the lending.
        address caller, /// Address of the spell caller.
        address token, /// Address of the lent token.
        uint256 amount /// Amount of tokens lent.
    );

    /// @notice Emitted when lent tokens are withdrawn from the bank.
    event WithdrawLend(
        uint256 positionId, /// Position ID associated with the withdrawal.
        address caller, /// Address of the spell caller.
        address token, ///Address of the token being withdrawn.
        uint256 amount /// Amount of tokens withdrawn.
    );

    /// @notice Emitted when a user borrows tokens from a bank.
    event Borrow(
        uint256 positionId, /// Position ID associated with the borrowing.
        address caller, /// Address of the spell caller that initiates the borrowing.
        address token, /// Token being borrowed.
        uint256 amount, /// Amount of tokens borrowed.
        uint256 share /// Debt share associated with the borrowed amount.
    );

    /// @notice Emitted when a user repays borrowed tokens to a bank.
    event Repay(
        uint256 positionId, /// Position ID associated with the repayment.
        address caller, /// Address of the spell caller initiating the repayment.
        address token, /// Token being repaid.
        uint256 amount, /// Amount of tokens repaid.
        uint256 share /// Debt share associated with the repaid amount.
    );

    /// @notice Emitted when a user adds tokens as collateral.
    event PutCollateral(
        uint256 positionId, /// Position ID associated with the collateral.
        address owner, /// Owner of the collateral position.
        address caller, /// Address of the spell caller adding the collateral.
        address token, /// Token used as collateral.
        uint256 id, /// ID of the wrapped token.
        uint256 amount /// Amount of tokens put as collateral.
    );

    /// @notice Emitted when a user retrieves tokens from their collateral.
    event TakeCollateral(
        uint256 positionId, /// Position ID associated with the collateral.
        address caller, /// Address of the spell caller retrieving the collateral.
        address token, /// Token taken from the collateral.
        uint256 id, /// ID of the wrapped token.
        uint256 amount /// Amount of tokens taken from collateral.
    );

    /// @notice Emitted when a position is liquidated.
    event Liquidate(
        uint256 positionId, /// Position ID being liquidated.
        address liquidator, /// Address of the user performing the liquidation.
        address debtToken, /// Debt token associated with the position.
        uint256 amount, /// Amount used for liquidation.
        uint256 share, /// Debt share associated with the liquidation.
        uint256 positionSize, /// Size of the position being liquidated.
        uint256 underlyingVaultSize /// Vault size underlying the liquidated position.
    );

    /// @notice Emitted when a position is executed.
    event Execute(
        uint256 positionId, /// Position ID being executed.
        address owner /// Owner of the position.
    );

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the next available position ID.
     * @return Next position ID.
     */
    function getNextPositionId() external view returns (uint256);

    /// @notice Provides the protocol configuration settings.
    function getConfig() external view returns (IProtocolConfig);

    /// @notice Provides the current oracle responsible for price feeds.
    function getOracle() external view returns (ICoreOracle);

    /// @notice Provides all banks in the Blueberry Bank.
    function getAllBanks() external view returns (address[] memory);

    /**
     * @dev Get the current FeeManager interface from the configuration.
     * @return An interface representing the current FeeManager.
     */
    function getFeeManager() external view returns (IFeeManager);

    /**
     * @notice Returns whitelist status of a given token.
     * @param token Address of the token.
     */
    function isTokenWhitelisted(address token) external view returns (bool);

    /**
     * @notice Returns whitelist status of a given wrapped token.
     * @param token Address of the wrapped token.
     */
    function isWrappedTokenWhitelisted(address token) external view returns (bool);

    /**
     * @notice Returns whitelist status of a given spell.
     * @param spell Address of the spell.
     */
    function isSpellWhitelisted(address spell) external view returns (bool);

    /**
     * @dev Determine if lending is currently allowed based on the bank's status flags.
     * @notice Check the third-to-last bit of _bankStatus.
     * @return A boolean indicating whether lending is permitted.
     */
    function isLendAllowed() external view returns (bool);

    /**
     * @dev Determine if withdrawing from lending is currently allowed based on the bank's status flags.
     * @notice Check the fourth-to-last bit of _bankStatus.
     * @return A boolean indicating whether withdrawing from lending is permitted.
     */
    function isWithdrawLendAllowed() external view returns (bool);

    /**
     * @dev Determine if repayments are currently allowed based on the bank's status flags.
     * @notice Check the second-to-last bit of _bankStatus.
     * @return A boolean indicating whether repayments are permitted.
     */
    function isRepayAllowed() external view returns (bool);

    /**
     * @dev Determine if borrowing is currently allowed based on the bank's status flags.
     * @notice Check the last bit of _bankStatus.
     * @return A boolean indicating whether borrowing is permitted.
     */
    function isBorrowAllowed() external view returns (bool);

    /// @notice Fetches details of a bank given its token.
    function getBankInfo(address token) external view returns (Bank memory bank);

    /**
     * @notice Gets the status of the bank
     * @return The status of the bank
     * @dev 1: Borrow is allowed
     *      2: Repay is allowed
     *      4: Lend is allowed
     *      8: WithdrawLend is allowed
     */
    function getBankStatus() external view returns (uint256);

    /**
     * @dev Computes the total USD value of the debt of a given position.
     * @notice Ensure to call `accrue` beforehand to account for any interest changes.
     * @param positionId ID of the position to compute the debt value for.
     * @return debtValue Total USD value of the position's debt.
     */
    function getDebtValue(uint256 positionId) external view returns (uint256 debtValue);

    /**
     * @notice Gets the repay resumed timestamp of the bank
     * @return The timestamp when repay is resumed
     */
    function getRepayResumedTimestamp() external view returns (uint256);

    /**
     * @dev Computes the risk ratio of a specified position.
     * @notice A higher risk ratio implies greater risk associated with the position.
     * @dev    when:  riskRatio = (ov - pv) / cv
     *         where: riskRatio = (debt - positionValue) / isolatedCollateralValue
     * @param positionId ID of the position to assess risk for.
     * @return risk The risk ratio of the position (based on a scale of 1e4).
     */
    function getPositionRisk(uint256 positionId) external view returns (uint256 risk);

    /**
     * @notice Retrieve the debt of a given position, considering the stored debt interest.
     * @dev Should call accrue first to obtain the current debt.
     * @param positionId The ID of the position to query.
     */
    function getPositionDebt(uint256 positionId) external view returns (uint256 debt);

    /**
     * @notice Determines if a given position can be liquidated based on its risk ratio.
     * @param positionId ID of the position to check.
     * @return True if the position can be liquidated; otherwise, false.
     */
    function isLiquidatable(uint256 positionId) external view returns (bool);

    /**
     * @notice Computes the total USD value of the collateral of a given position.
     * @dev The returned value includes both the collateral and any pending rewards.
     * @param positionId ID of the position to compute the value for.
     * @return positionValue Total USD value of the collateral and pending rewards.
     */
    function getPositionValue(uint256 positionId) external view returns (uint256);

    /**
     * @notice Computes the isolated collateral value for a particular position.
     * @dev Should call accrue first to get current debt.
     * @param positionId The unique ID of the position.
     * @return icollValue The value of the isolated collateral in USD.
     */
    function getIsolatedCollateralValue(uint256 positionId) external view returns (uint256 icollValue);

    /**
     * @notice Provides comprehensive details about a position using its ID.
     * @param positionId The unique ID of the position.
     * @return A Position struct containing details of the position.
     */
    function getPositionInfo(uint256 positionId) external view returns (Position memory);

    /**
     * @notice Fetches information about the currently active position.
     * @return A Position struct with details of the current position.
     */
    function getCurrentPositionInfo() external view returns (Position memory);

    /**
     * @notice Triggers interest accumulation and fetches the updated borrow balance.
     * @param positionId The unique ID of the position.
     * @return The updated debt balance after accruing interest.
     */
    function currentPositionDebt(uint256 positionId) external returns (uint256);

    /**
     * @dev Lend tokens to the bank as isolated collateral.
     * @dev Emit a {Lend} event.
     * @notice The tokens lent will be used as collateral in the bank and might earn interest or other rewards.
     * @param token The address of the token to lend.
     * @param amount The number of tokens to lend.
     */
    function lend(address token, uint256 amount) external;

    /**
     * @dev Withdraw isolated collateral tokens previously lent to the bank.
     * @dev Emit a {WithdrawLend} event.
     * @notice This will reduce the isolated collateral and might also reduce the position's overall health.
     * @param token The address of the isolated collateral token to withdraw.
     * @param shareAmount The number of vault share tokens to withdraw.
     */
    function withdrawLend(address token, uint256 shareAmount) external;

    /**
     * @notice Allows users to borrow tokens from the specified bank.
     * @dev This function must only be called from a spell while under execution.
     * @dev Emit a {Borrow} event.
     * @param token The token to borrow from the bank.
     * @param amount The amount of tokens the user wishes to borrow.
     * @return borrowedAmount Returns the actual amount borrowed from the bank.
     */
    function borrow(address token, uint256 amount) external returns (uint256);

    /**
     * @dev Executes a specific action on a position.
     * @dev Emit an {Execute} event.
     * @notice This can be used for various operations like adjusting collateral, repaying debt, etc.
     * @param positionId Unique identifier of the position, or zero for a new position.
     * @param spell Address of the contract ("spell") that contains the logic for the action to be executed.
     * @param data Data payload to pass to the spell for execution.
     */
    function execute(uint256 positionId, address spell, bytes memory data) external returns (uint256);

    /**
     * @notice Allows users to repay their borrowed tokens to the bank.
     * @dev This function must only be called while under execution.
     * @dev Emit a {Repay} event.
     * @param token The token to repay to the bank.
     * @param amountCall The amount of tokens to be repaid.
     */
    function repay(address token, uint256 amountCall) external;

    /**
     * @notice Allows users to provide additional collateral.
     * @dev Must only be called during execution.
     * @param collToken The ERC1155 token wrapped for collateral (i.e., Wrapped token of LP).
     * @param collId The token ID for collateral (i.e., uint256 format of LP address).
     * @param amountCall The amount of tokens to add as collateral.
     */
    function putCollateral(address collToken, uint256 collId, uint256 amountCall) external;

    /**
     * @notice Allows users to withdraw a portion of their collateral.
     * @dev Must only be called during execution.
     * @param amount The amount of tokens to be withdrawn as collateral.
     * @return Returns the amount of collateral withdrawn.
     */
    function takeCollateral(uint256 amount) external returns (uint256);

    /**
     * @dev Liquidates a position by repaying its debt and taking the collateral.
     * @dev Emit a {Liquidate} event.
     * @notice Liquidation can only be triggered if the position is deemed liquidatable
     *         and other conditions are met.
     * @param positionId The unique identifier of the position to liquidate.
     * @param debtToken The token in which the debt is denominated.
     * @param amountCall The amount of debt to be repaid when calling transferFrom.
     */
    function liquidate(uint256 positionId, address debtToken, uint256 amountCall) external;

    /**
     * @notice Accrues interest for a given token.
     * @param token Address of the token to accrue interest for.
     */
    function accrue(address token) external;

    /**
     * @notice Accrues interest for a given list of tokens.
     * @param tokens An array of token addresses to accrue interest for.
     */
    function accrueAll(address[] memory tokens) external;

    /* solhint-disable func-name-mixedcase */

    /**
     * @notice Returns the current executor's address, which is the owner of the current position.
     * @return Address of the current executor.
     */
    function EXECUTOR() external view returns (address);

    /**
     * @notice Returns the ID of the currently executed position.
     * @return Current position ID.
     */
    function POSITION_ID() external view returns (uint256);

    /**
     * @notice Returns the address of the currently executed bank.
     * @return Current bank address.
     */
    function SPELL() external view returns (address);

    /* solhint-enable func-name-mixedcase */
}
