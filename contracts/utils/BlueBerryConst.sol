// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

uint256 constant DENOMINATOR = 10000;

uint256 constant MIN_LIQ_THRESHOLD = 8000; // min liquidation threshold, 80%

uint256 constant PRICE_PRECISION = 1e18;

uint256 constant MAX_PRICE_DEVIATION = 1000; // max price deviation, 10%

uint32 constant MIN_TIME_GAP = 1 hours;

uint32 constant MAX_TIME_GAP = 2 days;

uint256 constant MAX_FEE_RATE = 2000; // max fee: 20%

uint256 constant MAX_WITHDRAW_VAULT_FEE_WINDOW = 60 days;

uint32 constant MAX_DELAY_ON_SWAP = 2 hours;

uint32 constant SEQUENCE_GRACE_PERIOD_TIME = 3600;

uint256 constant CHAINLINK_PRICE_FEED_PRECISION = 1e8;

uint256 constant LIQUIDATION_REPAY_WARM_UP_PERIOD = 4 hours;
