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
 * @notice This contract contains the error messages for Blueberry Protocol.
 */
pragma solidity 0.8.22;

/// @dev Common denominator for percentage-based calculations.
uint256 constant DENOMINATOR = 10000;

/// @dev Minimum threshold for liquidity operations, represented as a fraction of the DENOMINATOR.
uint256 constant MIN_LIQ_THRESHOLD = 8000; // represent 80%

/// @dev Precision factor to maintain price accuracy.
uint256 constant PRICE_PRECISION = 1e18;

/// @dev Maximum allowed price deviation, represented as a fraction of the DENOMINATOR.
uint256 constant MAX_PRICE_DEVIATION = 1000; // represent 10%

/// @dev Minimum time interval for specific time-dependent operations.
uint32 constant MIN_TIME_GAP = 3 minutes;

/// @dev Maximum time interval for specific time-dependent operations.
uint32 constant MAX_TIME_GAP = 2 days;

/// @dev Maximum allowed fee rate, represented as a fraction of the DENOMINATOR.
uint256 constant MAX_FEE_RATE = 2000; // represent 20%

/// @dev Maximum allowed time for vault withdrawal fee calculations.
uint256 constant MAX_WITHDRAW_VAULT_FEE_WINDOW = 60 days;

/// @dev Maximum delay permitted for swap operations.
uint32 constant MAX_DELAY_ON_SWAP = 2 hours;

/// @dev Allowed grace period time for sequencer operations.
uint32 constant SEQUENCER_GRACE_PERIOD_TIME = 3600;

/// @dev Precision factor for Chainlink price feed values.
uint256 constant CHAINLINK_PRICE_FEED_PRECISION = 1e8;

/// @dev Warm-up period before a liquidation repayment can be initiated.
uint256 constant LIQUIDATION_REPAY_WARM_UP_PERIOD = 4 hours;
