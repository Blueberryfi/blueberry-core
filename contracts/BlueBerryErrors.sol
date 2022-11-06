// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

// Common Errors
error ZERO_ADDRESS();
error INPUT_ARRAY_MISMATCH();

// Bank Errors
error FEE_TOO_HIGH(uint256 feeBps);
error NOT_UNDER_EXECUTION();
error BANK_NOT_LISTED();

// Oracle Errors
error TOO_LONG_DELAY(uint256 delayTime);
error NO_MAX_DELAY(address token);
error PRICE_OUTDATED(address token);
error NO_SYM_MAPPING(address token);

error OUT_OF_DEVIATION_CAP(uint256 deviation);
error EXCEED_SOURCE_LEN(uint256 length);
error NO_PRIMARY_SOURCE(address token);
error NO_VALID_SOURCE(address token);
error EXCEED_DEVIATION();

error PRICE_FAILED(address token);
error LIQ_THRESHOLD_TOO_HIGH(uint256 threshold);
