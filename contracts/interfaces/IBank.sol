// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./IProtocolConfig.sol";
import "./IFeeManager.sol";
import "./ICoreOracle.sol";

/// @title IBank
/// @notice Interface for the bank operations, including lending, borrowing, and management of collateral positions.
interface IBank {
    /*//////////////////////////////////////////////////////////////////////////
                                       STRUCTS
    //////////////////////////////////////////////////////////////////////////*/

    /// Represents the configuration and current state of a bank.
    struct Bank {
        bool isListed;             /// Indicates if this bank is active.
        uint8 index;               /// Index for reverse lookups.
        address hardVault;         /// Address of the hard vault.
        address softVault;         /// Address of the soft vault.
        address bToken;            /// Address of the bToken associated with the bank.
        uint256 totalShare;        /// Total shares of debt across all open positions.
        uint256 liqThreshold;      /// Liquidation threshold (e.g., 85% for volatile tokens, 
                                   /// 90% for stablecoins). Base: 1e4
    }

    /// Represents a position in the bank, including both debt and collateral.
    struct Position {
        address owner;                /// Address of the position's owner.
        address collToken;            /// Address of the ERC1155 token used as collateral.
        address underlyingToken;      /// Address of the isolated underlying collateral token.
        address debtToken;            /// Address of the debt token.
        uint256 underlyingVaultShare; /// Amount of vault share for isolated underlying collateral.
        uint256 collId;               /// Token ID of the ERC1155 collateral.
        uint256 collateralSize;       /// Amount of wrapped token used as collateral.
        uint256 debtShare;            /// Debt share of the given debt token for the bank.
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new bank is added by the owner.
    event AddBank(
        address token,        /// The primary token associated with the bank.
        address bToken,       /// The corresponding bToken for the bank.
        address softVault,    /// Address of the soft vault.
        address hardVault             /// Address of the hard vault.
    );

    /// @notice Emitted when the oracle's address is updated by the owner.
    event SetOracle(address oracle);  /// New address of the oracle.

    /// @notice Emitted when a Wrapped ERC1155 token is whitelisted or removed by the owner.
    event SetWhitelistERC1155(
        address indexed token,      /// Address of the Wrapped ERC1155 token.
        bool isWhitelisted          /// True if whitelisted, false otherwise.
    );

    /// @notice Emitted when a token is whitelisted or removed by the owner.
    event SetWhitelistToken(
        address indexed token,     /// Address of the token.
        bool isWhitelisted         /// True if whitelisted, false otherwise.
    );

    /// @notice Emitted when tokens are lent to the bank.
    event Lend(
        uint256 positionId,        /// Position ID associated with the lending.
        address caller,    /// Address of the spell caller.
        address token,     /// Address of the lent token.
        uint256 amount             /// Amount of tokens lent.
    );

    /// @notice Emitted when lent tokens are withdrawn from the bank.
    event WithdrawLend(
        uint256 positionId,        /// Position ID associated with the withdrawal.
        address caller,    /// Address of the spell caller.
        address token,     ///Address of the token being withdrawn.
        uint256 amount             /// Amount of tokens withdrawn.
    );

    /// @notice Emitted when a user borrows tokens from a bank.
    event Borrow(
        uint256 positionId,        /// Position ID associated with the borrowing.
        address caller,    /// Address of the spell caller that initiates the borrowing.
        address token,     /// Token being borrowed.
        uint256 amount,            /// Amount of tokens borrowed.
        uint256 share              /// Debt share associated with the borrowed amount.
    );

    /// @notice Emitted when a user repays borrowed tokens to a bank.
    event Repay(
        uint256 positionId,        /// Position ID associated with the repayment.
        address caller,    /// Address of the spell caller initiating the repayment.
        address token,     /// Token being repaid.
        uint256 amount,            /// Amount of tokens repaid.
        uint256 share              /// Debt share associated with the repaid amount.
    );

    /// @notice Emitted when a user adds tokens as collateral.
    event PutCollateral(
        uint256 positionId,        /// Position ID associated with the collateral.
        address owner,     /// Owner of the collateral position.
        address caller,    /// Address of the spell caller adding the collateral.
        address token,     /// Token used as collateral.
        uint256 id,                /// ID of the wrapped token.
        uint256 amount             /// Amount of tokens put as collateral.
    );

    /// @notice Emitted when a user retrieves tokens from their collateral.
    event TakeCollateral(
        uint256 positionId,        /// Position ID associated with the collateral.
        address caller,    /// Address of the spell caller retrieving the collateral.
        address token,     /// Token taken from the collateral.
        uint256 id,                /// ID of the wrapped token.
        uint256 amount             /// Amount of tokens taken from collateral.
    );

    /// @notice Emitted when a position is liquidated.
    event Liquidate(
        uint256 positionId,           /// Position ID being liquidated.
        address liquidator,   /// Address of the user performing the liquidation.
        address debtToken,    /// Debt token associated with the position.
        uint256 amount,               /// Amount used for liquidation.
        uint256 share,                /// Debt share associated with the liquidation.
        uint256 positionSize,         /// Size of the position being liquidated.
        uint256 underlyingVaultSize   /// Vault size underlying the liquidated position.
    );

    /// @notice Emitted when a position is executed.
    event Execute(
        uint256 positionId,        /// Position ID being executed.
        address owner      /// Owner of the position.
    );

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the ID of the currently executed position.
    /// @return Current position ID.
    function POSITION_ID() external view returns (uint256);

    /// @notice Returns the address of the currently executed spell.
    /// @return Current spell address.
    function SPELL() external view returns (address);

    /// @notice Returns the current executor's address, which is the owner of the current position.
    /// @return Address of the current executor.
    function EXECUTOR() external view returns (address);

    /// @notice Returns the next available position ID.
    /// @return Next position ID.
    function nextPositionId() external view returns (uint256);

    /// @notice Provides the protocol configuration settings.
    function config() external view returns (IProtocolConfig);

    /// @notice Retrieves the active fee manager.
    function feeManager() external view returns (IFeeManager);

    /// @notice Provides the current oracle responsible for price feeds.
    function oracle() external view returns (ICoreOracle);

    /// @notice Fetches details of a bank given its token.
    function getBankInfo(address token) external view returns (
        bool isListed,           /// Indicates if the bank is listed.
        address bToken,          /// Corresponding bToken of the bank.
        uint256 totalShare       /// Total shared debt across all positions in this bank.
    );
    
    /// @notice Computes the total debt value associated with a given position.
    /// @dev Should call accrue first to get current debt
    /// @param positionId The unique ID of the position.
    /// @return The total debt value in USD.
    function getDebtValue(uint256 positionId) external returns (uint256);

    /// @notice Determines the overall value of a specified position.
    /// @param positionId The unique ID of the position.
    /// @return The total value of the position in USD.
    function getPositionValue(uint256 positionId) external returns (uint256);

    /// @notice Computes the isolated collateral value for a particular position.
    /// @dev Should call accrue first to get current debt.
    /// @param positionId The unique ID of the position.
    /// @return icollValue The value of the isolated collateral in USD.
    function getIsolatedCollateralValue(
        uint256 positionId
    ) external returns (uint256 icollValue);

    /// @notice Provides comprehensive details about a position using its ID.
    /// @param positionId The unique ID of the position.
    /// @return A Position struct containing details of the position.
    function getPositionInfo(
        uint256 positionId
    ) external view returns (Position memory);

    /// @notice Fetches information about the currently active position.
    /// @return A Position struct with details of the current position.
    function getCurrentPositionInfo() external view returns (Position memory);

    /// @notice Triggers interest accumulation and fetches the updated borrow balance.
    /// @param positionId The unique ID of the position.
    /// @return The updated debt balance after accruing interest.
    function currentPositionDebt(uint256 positionId) external returns (uint256);

    /// @notice Deposits tokens into the bank as a lender.
    /// @param token The address of the token to deposit.
    /// @param amount The amount of tokens to deposit.
    function lend(address token, uint256 amount) external;

    /// @notice Redeems deposited tokens from the bank.
    /// @param token The address of the token to withdraw.
    /// @param amount The amount of tokens to redeem.
    function withdrawLend(address token, uint256 amount) external;

    /// @notice Borrows tokens against collateral from the bank.
    /// @param token The address of the token to borrow.
    /// @param amount The amount of tokens to borrow.
    /// @return The amount of tokens that are borrowed.
    function borrow(address token, uint256 amount) external returns (uint256);

    /// @notice Repays borrowed tokens to the bank.
    /// @param token The address of the token to repay.
    /// @param amountCall The amount of tokens to repay.
    function repay(address token, uint256 amountCall) external;

    /// @notice Increases the collateral backing a position.
    /// @param collToken Address of the collateral token.
    /// @param collId ID associated with the collateral type (if applicable).
    /// @param amountCall Amount of collateral tokens to deposit.
    function putCollateral(
        address collToken,
        uint256 collId,
        uint256 amountCall
    ) external;

    /// @notice Redeems a portion of the collateral backing a position.
    /// @param amount Amount of collateral tokens to redeem.
    /// @return The actual amount of collateral redeemed.
    function takeCollateral(uint256 amount) external returns (uint256);

    /// @notice Liquidate a specific position.
    /// @param positionId ID of the position to liquidate.
    /// @param debtToken Address of the debt token.
    /// @param amountCall Amount specified for the liquidation call.
    function liquidate(
        uint256 positionId,
        address debtToken,
        uint256 amountCall
    ) external;

    /// @notice Accrues interest for a given token.
    /// @param token Address of the token to accrue interest for.
    function accrue(address token) external;
}
