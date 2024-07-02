// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
/**
 * @title BlueberryErrors
 * @author BlueberryProtocol
 * @notice containing all errors used in Blueberry protocol
 */
/// title BlueberryErrors
/// @notice containing all errors used in Blueberry protocol
pragma solidity 0.8.22;

/*//////////////////////////////////////////////////////////////////////////
                                COMMON ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when an action involves zero amount of tokens.
error ZERO_AMOUNT();

/// @notice Thrown when the address provided is the zero address.
error ZERO_ADDRESS();

/// @notice Thrown when the lengths of input arrays do not match.
error INPUT_ARRAY_MISMATCH();

/// @notice Thrown when the caller is not authorized to call the function.
error UNAUTHORIZED();

/*//////////////////////////////////////////////////////////////////////////
                                ORACLE ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when the delay time exceeds allowed limits.
error TOO_LONG_DELAY(uint256 delayTime);

/// @notice Thrown when there's no maximum delay set for a token.
error NO_MAX_DELAY(address token);

/// @notice Thrown when the price information for a token is outdated.
error PRICE_OUTDATED(address token);

/// @notice Thrown when the price obtained is negative.
error PRICE_NEGATIVE(address token);

/// @notice Thrown when the sequencer is offline
error SEQUENCER_DOWN(address sequencer);

/// @notice Thrown when the grace period for a sequencer is not over yet.
error SEQUENCER_GRACE_PERIOD_NOT_OVER(address sequencer);

/// @notice Thrown when the price deviation exceeds allowed limits.
error OUT_OF_DEVIATION_CAP(uint256 deviation);

/// @notice Thrown when the number of sources exceeds the allowed length.
error EXCEED_SOURCE_LEN(uint256 length);

/// @notice Thrown when no primary source is available for the token.
error NO_PRIMARY_SOURCE(address token);

/// @notice Thrown when no valid price source is available for the token.
error NO_VALID_SOURCE(address token);

/// @notice Thrown when the deviation value exceeds the threshold.
error EXCEED_DEVIATION();

/// @notice Thrown when the mean price is below the acceptable threshold.
error TOO_LOW_MEAN(uint256 mean);

/// @notice Thrown when no mean price is set for the token.
error NO_MEAN(address token);

/// @notice Thrown when no stable pool exists for the token.
error NO_STABLEPOOL(address token);

/// @notice Thrown when the price fetch process fails for a token.
error PRICE_FAILED(address token);

/// @notice Thrown when the liquidation threshold is set too high.
error LIQ_THRESHOLD_TOO_HIGH(uint256 threshold);

/// @notice Thrown when the liquidation threshold is set too low.
error LIQ_THRESHOLD_TOO_LOW(uint256 threshold);

/// @notice Thrown when the oracle doesn't support a specific token.
error ORACLE_NOT_SUPPORT(address token);

/// @notice Thrown when the oracle doesn't support a specific LP pair token.
error ORACLE_NOT_SUPPORT_LP(address lp);

/// @notice Thrown when the oracle doesn't support a specific wToken.
error ORACLE_NOT_SUPPORT_WTOKEN(address wToken);

/// @notice Thrown when there is no route to fetch data for the oracle
error NO_ORACLE_ROUTE(address token);

/// @notice Thrown when a value is out of an acceptable range.
error VALUE_OUT_OF_RANGE();

/// @notice Thrown when specified limits are incorrect.
error INCORRECT_LIMITS();

/// @notice Thrown when Curve LP is already registered.
error CRV_LP_ALREADY_REGISTERED(address lp);

/// @notice Thrown when a token and Balancer LP is already registered.
error TOKEN_BPT_ALREADY_REGISTERED(address token, address bpt);

/// @notice Thrown when a pool is subject to read-only reentrancy manipulation.
error REENTRANCY_RISK(address pool);

/// @notice Thrown when the incorrect duration is provided when registering a market.
error INCORRECT_DURATION(uint32 duration);

/*//////////////////////////////////////////////////////////////////////////
                            GENERAL SPELL ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when the caller isn't recognized as a bank.
error NOT_BANK(address caller);

/// @notice Thrown when the collateral doesn't exist for a strategy.
error COLLATERAL_NOT_EXIST(uint256 strategyId, address colToken);

/// @notice Thrown when the strategy ID doesn't correspond to an existing strategy.
error STRATEGY_NOT_EXIST(address spell, uint256 strategyId);

/// @notice Thrown when the position size exceeds maximum limits.
error EXCEED_MAX_POS_SIZE(uint256 strategyId);

/// @notice Thrown when the user has not deposited enough isolated collateral for a strategy.
error BELOW_MIN_ISOLATED_COLLATERAL(uint256 strategyId);

/// @notice Thrown when the loan-to-value ratio exceeds allowed maximum.
error EXCEED_MAX_LTV();

/// @notice Thrown when the strategy ID provided is incorrect.
error INCORRECT_STRATEGY_ID(uint256 strategyId);

/// @notice Thrown when the position size is invalid.
error INVALID_POS_SIZE();

/// @notice Thrown when an incorrect liquidity pool token is provided.
error INCORRECT_LP(address lpToken);

/// @notice Thrown when an incorrect pool ID is provided.
error INCORRECT_PID(uint256 pid);

/// @notice Thrown when an incorrect collateral token is provided.
error INCORRECT_COLTOKEN(address colToken);

/// @notice Thrown when an incorrect underlying token is provided.
error INCORRECT_UNDERLYING(address uToken);

/// @notice Thrown when an incorrect debt token is provided.
error INCORRECT_DEBT(address debtToken);

/// @notice Thrown when a swap fails.
error SWAP_FAILED(address swapToken);

/*//////////////////////////////////////////////////////////////////////////
                                VAULT ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when borrowing from the vault fails.
error BORROW_FAILED(uint256 amount);

/// @notice Thrown when repaying to the vault fails.
error REPAY_FAILED(uint256 amount);

/// @notice Thrown when lending to the vault fails.
error LEND_FAILED(uint256 amount);

/// @notice Thrown when redeeming from the vault fails.
error REDEEM_FAILED(uint256 amount);

/*//////////////////////////////////////////////////////////////////////////
                                WRAPPER ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when a duplicate tokenId is added.
error DUPLICATE_TOKEN_ID(uint256 tokenId);

/// @notice Thrown when an invalid token ID is provided.
error INVALID_TOKEN_ID(uint256 tokenId);

/// @notice Thrown when an incorrect pool ID is provided.
error BAD_PID(uint256 pid);

/// @notice Thrown when a mismatch in reward per share is detected.
error BAD_REWARD_PER_SHARE(uint256 rewardPerShare);

/*//////////////////////////////////////////////////////////////////////////
                                BANK ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when a function is called without a required execution flag.
error NOT_UNDER_EXECUTION();

/// @notice Thrown when a transaction isn't initiated by the expected spell.
error NOT_FROM_SPELL(address from);

/// @notice Thrown when the sender is not the owner of a given position ID.
error NOT_FROM_OWNER(uint256 positionId, address sender);

/// @notice Thrown when a spell address isn't whitelisted.
error SPELL_NOT_WHITELISTED(address spell);

/// @notice Thrown when a token isn't whitelisted.
error TOKEN_NOT_WHITELISTED(address token);

/// @notice Thrown when a bank isn't listed for a given token.
error BANK_NOT_LISTED(address token);

/// @notice Thrown when a bank doesn't exist for an index.
error BANK_NOT_EXIST(uint8 index);

/// @notice Thrown when a bank is already listed for a given token.
error BANK_ALREADY_LISTED();

/// @notice Thrown when the bank limit is reached.
error BANK_LIMIT();

/// @notice Thrown when the BTOKEN is already added.
error BTOKEN_ALREADY_ADDED();

/// @notice Thrown when the lending action isn't allowed.
error LEND_NOT_ALLOWED();

/// @notice Thrown when the borrowing action isn't allowed.
error BORROW_NOT_ALLOWED();

/// @notice Thrown when the repaying action isn't allowed.
error REPAY_NOT_ALLOWED();

/// @notice Thrown when the redeeming action isn't allowed.
error WITHDRAW_LEND_NOT_ALLOWED();

/// @notice Thrown when certain actions are locked.
error LOCKED();

/// @notice Thrown when an action isn't executed.
error NOT_IN_EXEC();

/// @notice Thrown when the repayment allowance hasn't been warmed up.
error REPAY_ALLOW_NOT_WARMED_UP();

/// @notice Thrown when a different collateral type exists.
error DIFF_COL_EXIST(address collToken);

/// @notice Thrown when a position is not eligible for liquidation.
error NOT_LIQUIDATABLE(uint256 positionId);

/// @notice Thrown when a position is flagged as bad or invalid.
error BAD_POSITION(uint256 posId);

/// @notice Thrown when collateral for a specific position is flagged as bad or invalid.
error BAD_COLLATERAL(uint256 positionId);

/// @notice Thrown when there's insufficient collateral for an operation.
error INSUFFICIENT_COLLATERAL();

/// @notice Thrown when an attempted repayment exceeds the actual debt.
error REPAY_EXCEEDS_DEBT(uint256 repay, uint256 debt);

/// @notice Thrown when an invalid utility token is provided.
error INVALID_UTOKEN(address uToken);

/// @notice Thrown when a borrow operation results in zero shares.
error BORROW_ZERO_SHARE(uint256 borrowAmount);

/*//////////////////////////////////////////////////////////////////////////
                            CONFIGURATION ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when a certain ratio is too high for an operation.
error RATIO_TOO_HIGH(uint256 ratio);

/// @notice Thrown when an invalid fee distribution is detected.
error INVALID_FEE_DISTRIBUTION();

/// @notice Thrown when no treasury is set for fee distribution.
error NO_TREASURY_SET();

/// @notice Thrown when a fee window has already started.
error FEE_WINDOW_ALREADY_STARTED();

/// @notice Thrown when a fee window duration is too long.
error FEE_WINDOW_TOO_LONG(uint256 windowTime);

/*//////////////////////////////////////////////////////////////////////////
                                UTILITY ERRORS
//////////////////////////////////////////////////////////////////////////*/

/// @notice Thrown when an operation has surpassed its deadline.
error EXPIRED(uint256 deadline);
