pragma solidity 0.5.16;

import "./BToken.sol";
import "./ComptrollerInterfaceExtension.sol";
import "./ERC3156FlashLenderInterface.sol";
import "./ERC3156FlashBorrowerInterface.sol";

/**
 * @title Blueberry's BCollateralCapErc20 Contract
 * @notice BTokens which wrap an EIP-20 underlying with collateral cap
 * @author Blueberry
 */
contract BCollateralCapErc20 is BToken, BCollateralCapErc20Interface {
    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param comptroller_ The address of the Comptroller
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) public {
        // BToken initialize does the bulk of the work
        super.initialize(comptroller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_);

        // Set underlying and sanity check it
        underlying = underlying_;
        EIP20Interface(underlying).totalSupply();
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives bTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint256 mintAmount) external returns (uint256) {
        (uint256 err, ) = _mintInternal(mintAmount, false);
        require(err == 0, "mint failed");
    }

    /**
     * @notice Sender redeems bTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of bTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint256 redeemTokens) external returns (uint256) {
        require(_redeemInternal(redeemTokens, false) == 0, "redeem failed");
    }

    /**
     * @notice Sender redeems bTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256) {
        require(_redeemUnderlyingInternal(redeemAmount, false) == 0, "redeem underlying failed");
    }

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function borrow(uint256 borrowAmount) external returns (uint256) {
        require(_borrowInternal(borrowAmount, false) == 0, "borrow failed");
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrow(uint256 repayAmount) external returns (uint256) {
        (uint256 err, ) = _repayBorrowInternal(repayAmount, false);
        require(err == 0, "repay failed");
    }

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256) {
        (uint256 err, ) = _repayBorrowBehalfInternal(borrower, repayAmount, false);
        require(err == 0, "repay behalf failed");
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this bToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param bTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        BTokenInterface bTokenCollateral
    ) external returns (uint256) {
        (uint256 err, ) = _liquidateBorrowInternal(borrower, repayAmount, bTokenCollateral, false);
        require(err == 0, "liquidate borrow failed");
    }

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount fo underlying token to add as reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function addReserves(uint256 addAmount) external returns (uint256) {
        require(_addReservesInternal(addAmount, false) == 0, "add reserves failed");
    }

    /**
     * @notice Set the given collateral cap for the market.
     * @param newCollateralCap New collateral cap for this market. A value of 0 corresponds to no cap.
     */
    function setCollateralCap(uint256 newCollateralCap) external {
        require(msg.sender == admin, "admin only");

        collateralCap = newCollateralCap;
        emit NewCollateralCap(address(this), newCollateralCap);
    }

    /**
     * @notice Absorb excess cash into reserves.
     */
    function gulp() external nonReentrant {
        uint256 cashOnChain = _getCashOnChain();
        uint256 cashPrior = _getCashPrior();

        uint256 excessCash = _sub(cashOnChain, cashPrior);
        totalReserves = _add(totalReserves, excessCash);
        internalCash = cashOnChain;
    }

    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256) {
        uint256 amount = 0;
        if (
            token == underlying &&
            ComptrollerInterfaceExtension(address(comptroller)).flashloanAllowed(address(this), address(0), amount, "")
        ) {
            amount = _getCashPrior();
        }
        return amount;
    }

    /**
     * @notice Get the flash loan fees
     * @param token The loan currency. Must match the address of this contract's underlying.
     * @param amount amount of token to borrow
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        require(token == underlying, "unsupported currency");
        require(
            ComptrollerInterfaceExtension(address(comptroller)).flashloanAllowed(address(this), address(0), amount, ""),
            "flashloan is paused"
        );
        return _flashFee(token, amount);
    }

    /**
     * @notice Flash loan funds to a given account.
     * @param receiver The receiver address for the funds
     * @param token The loan currency. Must match the address of this contract's underlying.
     * @param amount The amount of the funds to be loaned
     * @param data The other data
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function flashLoan(
        ERC3156FlashBorrowerInterface receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        require(amount > 0, "invalid flashloan amount");
        require(token == underlying, "unsupported currency");
        accrueInterest();
        require(
            ComptrollerInterfaceExtension(address(comptroller)).flashloanAllowed(
                address(this),
                address(receiver),
                amount,
                data
            ),
            "flashloan is paused"
        );
        uint256 cashOnChainBefore = _getCashOnChain();
        uint256 cashBefore = _getCashPrior();
        require(cashBefore >= amount, "insufficient cash");

        // 1. calculate fee, 1 bips = 1/10000
        uint256 totalFee = _flashFee(token, amount);

        // 2. transfer fund to receiver
        _doTransferOut(address(uint160(address(receiver))), amount, false);

        // 3. update totalBorrows
        totalBorrows = _add(totalBorrows, amount);

        // 4. execute receiver's callback function
        require(
            receiver.onFlashLoan(msg.sender, underlying, amount, totalFee, data) ==
                keccak256("ERC3156FlashBorrowerInterface.onFlashLoan"),
            "IERC3156: Callback failed"
        );

        // 5. take amount + fee from receiver, then check balance
        uint256 repaymentAmount = _add(amount, totalFee);
        _doTransferIn(address(receiver), repaymentAmount, false);

        uint256 cashOnChainAfter = _getCashOnChain();

        require(cashOnChainAfter == _add(cashOnChainBefore, totalFee), "inconsistent balance");

        // 6. update reserves and internal cash and totalBorrows
        uint256 reservesFee = _mulScalarTruncate(Exp({ mantissa: reserveFactorMantissa }), totalFee);
        totalReserves = _add(totalReserves, reservesFee);
        internalCash = _add(cashBefore, totalFee);
        totalBorrows = _sub(totalBorrows, amount);

        emit Flashloan(address(receiver), amount, totalFee, reservesFee);
        return true;
    }

    /* solhint-disable no-unused-vars */
    /**
     * @notice Get the flash loan fees
     * @param token The loan currency. Must match the address of this contract's underlying.
     * @param amount amount of token to borrow
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(address token, uint256 amount) internal pure returns (uint256) {
        return _div(_mul(amount, FLASH_LOAN_FEE_BPS), 10000);
    }
    /* solhint-enable no-unused-vars */

    /**
     * @notice Register account collateral tokens if there is space.
     * @param account The account to register
     * @dev This function could only be called by comptroller.
     * @return The actual registered amount of collateral
     */
    function registerCollateral(address account) external returns (uint256) {
        // Make sure accountCollateralTokens of `account` is initialized.
        _initializeAccountCollateralTokens(account);

        require(msg.sender == address(comptroller), "comptroller only");

        uint256 amount = _sub(_accountTokens[account], accountCollateralTokens[account]);
        return _increaseUserCollateralInternal(account, amount);
    }

    /**
     * @notice Unregister account collateral tokens if the account still has enough collateral.
     * @dev This function could only be called by comptroller.
     * @param account The account to unregister
     */
    function unregisterCollateral(address account) external {
        // Make sure accountCollateralTokens of `account` is initialized.
        _initializeAccountCollateralTokens(account);

        require(msg.sender == address(comptroller), "comptroller only");
        require(comptroller.redeemAllowed(address(this), account, accountCollateralTokens[account]) == 0, "rejected");

        _decreaseUserCollateralInternal(account, accountCollateralTokens[account]);
    }

    /*** Safe Token ***/

    /**
     * @notice Gets internal balance of this contract in terms of the underlying.
     *  It excludes balance from direct transfer.
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function _getCashPrior() internal view returns (uint256) {
        return internalCash;
    }

    /**
     * @notice Gets total balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function _getCashOnChain() internal view returns (uint256) {
        EIP20Interface token = EIP20Interface(underlying);
        return token.balanceOf(address(this));
    }

    /**
     * @notice Initialize the account's collateral tokens. This function should be called in
     *      the beginning of every function that accesses accountCollateralTokens or accountTokens.
     * @param account The account of accountCollateralTokens that needs to be updated
     */
    function _initializeAccountCollateralTokens(address account) internal {
        /* solhint-disable max-line-length */
        /**
         * If isCollateralTokenInit is false, it means accountCollateralTokens was not initialized yet.
         * This case will only happen once and must be the very beginning. accountCollateralTokens is a new structure and its
         * initial value should be equal to accountTokens if user has entered the market. However, it's almost impossible to
         * check every user's value when the implementation becomes active. Therefore, it must rely on every action which will
         * access accountTokens to call this function to check if accountCollateralTokens needed to be initialized.
         */
        /* solhint-enable max-line-length */
        if (!isCollateralTokenInit[account]) {
            if (ComptrollerInterfaceExtension(address(comptroller)).checkMembership(account, BToken(this))) {
                accountCollateralTokens[account] = _accountTokens[account];
                totalCollateralTokens = _add(totalCollateralTokens, _accountTokens[account]);

                emit UserCollateralChanged(account, accountCollateralTokens[account]);
            }
            isCollateralTokenInit[account] = true;
        }
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and reverts in that case.
     *      This will revert due to insufficient balance or insufficient allowance.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *      See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function __doTransferIn(address from, uint256 amount, bool isNative) internal returns (uint256) {
        isNative; // unused

        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        uint256 balanceBefore = EIP20Interface(underlying).balanceOf(address(this));
        token.transferFrom(from, address(this), amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "transfer failed");

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = EIP20Interface(underlying).balanceOf(address(this));
        uint256 transferredIn = _sub(balanceAfter, balanceBefore);
        internalCash = _add(internalCash, transferredIn);
        return transferredIn;
    }

    /**
     * @dev Similar to EIP20 transfer, except it handles a False success from `transfer` and returns an explanatory
     *      error code rather than reverting. If caller has not called checked protocol's balance,
     *      this may revert due to insufficient cash held in this contract. If caller has checked
     *      protocol's balance prior to this call, and verified
     *      it is >= amount, this should not revert in normal conditions.
     *
     *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
     *      See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
     */
    function _doTransferOut(address payable to, uint256 amount, bool isNative) internal {
        isNative; // unused

        EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
        token.transfer(to, amount);

        bool success;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a complaint ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, "transfer failed");
        internalCash = _sub(internalCash, amount);
    }

    /**
     * @notice Get the amount of collateral tokens user would consume.
     * @param amountTokens The amount of tokens that user would like to redeem, transfer, or seize
     * @param account The account address
     * @return The amount of collateral tokens to be consumed
     */
    function _getCollateralTokens(uint256 amountTokens, address account) internal view returns (uint256) {
        /**
         * For every user, accountTokens must be greater than or equal to accountCollateralTokens.
         * The buffer between the two values will be transferred first.
         * bufferTokens = accountTokens[account] - accountCollateralTokens[account]
         * collateralTokens = tokens - bufferTokens
         */
        uint256 bufferTokens = _sub(_accountTokens[account], accountCollateralTokens[account]);
        uint256 collateralTokens = 0;
        if (amountTokens > bufferTokens) {
            collateralTokens = amountTokens - bufferTokens;
        }
        return collateralTokens;
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function _transferTokens(address spender, address src, address dst, uint256 tokens) internal returns (uint256) {
        // Make sure accountCollateralTokens of `src` and `dst` are initialized.
        _initializeAccountCollateralTokens(src);
        _initializeAccountCollateralTokens(dst);

        uint256 collateralTokens = _getCollateralTokens(tokens, src);

        /**
         * Since bufferTokens are not collateralized and can be transferred freely, we only check with comptroller
         * whether collateralized tokens can be transferred.
         */
        require(comptroller.transferAllowed(address(this), src, dst, collateralTokens) == 0, "rejected");

        /* Do not allow self-transfers */
        require(src != dst, "bad input");

        /* Get the allowance, infinite for the account owner */
        uint256 startingAllowance = 0;
        if (spender == src) {
            startingAllowance = uint256(-1);
        } else {
            startingAllowance = _transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        _accountTokens[src] = _sub(_accountTokens[src], tokens);
        _accountTokens[dst] = _add(_accountTokens[dst], tokens);
        if (collateralTokens > 0) {
            accountCollateralTokens[src] = _sub(accountCollateralTokens[src], collateralTokens);
            accountCollateralTokens[dst] = _add(accountCollateralTokens[dst], collateralTokens);

            emit UserCollateralChanged(src, accountCollateralTokens[src]);
            emit UserCollateralChanged(dst, accountCollateralTokens[dst]);
        }

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != uint256(-1)) {
            _transferAllowances[src][spender] = _sub(startingAllowance, tokens);
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);

        comptroller.transferVerify(address(this), src, dst, tokens);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Get the account's bToken balances
     * @param account The address of the account
     */
    function _getBTokenBalanceInternal(address account) internal view returns (uint256) {
        if (isCollateralTokenInit[account]) {
            return accountCollateralTokens[account];
        } else {
            /**
             * If the value of accountCollateralTokens was not initialized, we should return the value of accountTokens.
             */
            return _accountTokens[account];
        }
    }

    /**
     * @notice Increase user's collateral. Increase as much as we can.
     * @param account The address of the account
     * @param amount The amount of collateral user wants to increase
     * @return The actual increased amount of collateral
     */
    function _increaseUserCollateralInternal(address account, uint256 amount) internal returns (uint256) {
        uint256 totalCollateralTokensNew = _add(totalCollateralTokens, amount);
        if (collateralCap == 0 || (collateralCap != 0 && totalCollateralTokensNew <= collateralCap)) {
            // 1. If collateral cap is not set,
            // 2. If collateral cap is set but has enough space for this user,
            // give all the user needs.
            totalCollateralTokens = totalCollateralTokensNew;
            accountCollateralTokens[account] = _add(accountCollateralTokens[account], amount);

            emit UserCollateralChanged(account, accountCollateralTokens[account]);
            return amount;
        } else if (collateralCap > totalCollateralTokens) {
            // If the collateral cap is set but the remaining cap is not enough for this user,
            // give the remaining parts to the user.
            uint256 gap = _sub(collateralCap, totalCollateralTokens);
            totalCollateralTokens = _add(totalCollateralTokens, gap);
            accountCollateralTokens[account] = _add(accountCollateralTokens[account], gap);

            emit UserCollateralChanged(account, accountCollateralTokens[account]);
            return gap;
        }
        return 0;
    }

    /**
     * @notice Decrease user's collateral. Reject if the amount can't be fully decrease.
     * @param account The address of the account
     * @param amount The amount of collateral user wants to decrease
     */
    function _decreaseUserCollateralInternal(address account, uint256 amount) internal {
        /*
         * Return if amount is zero.
         * Put behind `redeemAllowed` for accruing potential COMP rewards.
         */
        if (amount == 0) {
            return;
        }

        totalCollateralTokens = _sub(totalCollateralTokens, amount);
        accountCollateralTokens[account] = _sub(accountCollateralTokens[account], amount);

        emit UserCollateralChanged(account, accountCollateralTokens[account]);
    }

    struct MintLocalVars {
        uint256 exchangeRateMantissa;
        uint256 mintTokens;
        uint256 actualMintAmount;
    }

    /**
     * @notice User supplies assets into the market and receives bTokens in exchange
     * @dev Assumes interest has already been accrued up to the current block
     * @param minter The address of the account which is supplying the assets
     * @param mintAmount The amount of the underlying asset to supply
     * @param isNative The amount is in native or not
     * @return (uint, uint) An error code (0=success, otherwise a failure, see ErrorReporter.sol),
     *     and the actual mint amount.
     */
    function _mintFresh(address minter, uint256 mintAmount, bool isNative) internal returns (uint256, uint256) {
        // Make sure accountCollateralTokens of `minter` is initialized.
        _initializeAccountCollateralTokens(minter);

        /* Fail if mint not allowed */
        require(comptroller.mintAllowed(address(this), minter, mintAmount) == 0, "rejected");

        /*
         * Return if mintAmount is zero.
         * Put behind `mintAllowed` for accruing potential COMP rewards.
         */
        if (mintAmount == 0) {
            return (uint256(Error.NO_ERROR), 0);
        }

        /* Verify market's block number equals current block number */
        require(accrualBlockNumber == _getBlockNumber(), "market is stale");

        MintLocalVars memory vars;

        vars.exchangeRateMantissa = _exchangeRateStoredInternal();

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call `_doTransferIn` for the minter and the mintAmount.
         *  Note: The bToken must handle variations between ERC-20 and ETH underlying.
         *  `_doTransferIn` reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the bToken holds an additional `actualMintAmount`
         *  of cash.
         */
        vars.actualMintAmount = _doTransferIn(minter, mintAmount, isNative);

        /*
         * We get the current exchange rate and calculate the number of bTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */
        vars.mintTokens = _divScalarByExpTruncate(vars.actualMintAmount, Exp({ mantissa: vars.exchangeRateMantissa }));

        /*
         * We calculate the new total supply of bTokens and minter token balance, checking for overflow:
         *  totalSupply = totalSupply + mintTokens
         *  accountTokens[minter] = accountTokens[minter] + mintTokens
         */
        totalSupply = _add(totalSupply, vars.mintTokens);
        _accountTokens[minter] = _add(_accountTokens[minter], vars.mintTokens);

        /*
         * We only allocate collateral tokens if the minter has entered the market.
         */
        if (ComptrollerInterfaceExtension(address(comptroller)).checkMembership(minter, BToken(this))) {
            _increaseUserCollateralInternal(minter, vars.mintTokens);
        }

        /* We emit a Mint event, and a Transfer event */
        emit Mint(minter, vars.actualMintAmount, vars.mintTokens);
        emit Transfer(address(this), minter, vars.mintTokens);

        /* We call the defense hook */
        comptroller.mintVerify(address(this), minter, vars.actualMintAmount, vars.mintTokens);

        return (uint256(Error.NO_ERROR), vars.actualMintAmount);
    }

    struct RedeemLocalVars {
        uint256 exchangeRateMantissa;
        uint256 redeemTokens;
        uint256 redeemAmount;
        uint256 collateralTokens;
    }

    /**
     * @notice User redeems bTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current block.
     *     Only one of redeemTokensIn or redeemAmountIn may be non-zero and
     *     it would do nothing if both are zero.
     * @param redeemer The address of the account which is redeeming the tokens
     * @param redeemTokensIn The number of bTokens to redeem into underlying
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming bTokens
     * @param isNative The amount is in native or not
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _redeemFresh(
        address payable redeemer,
        uint256 redeemTokensIn,
        uint256 redeemAmountIn,
        bool isNative
    ) internal returns (uint256) {
        // Make sure accountCollateralTokens of `redeemer` is initialized.
        _initializeAccountCollateralTokens(redeemer);

        require(redeemTokensIn == 0 || redeemAmountIn == 0, "bad input");

        RedeemLocalVars memory vars;

        /* exchangeRate = invoke Exchange Rate Stored() */
        vars.exchangeRateMantissa = _exchangeRateStoredInternal();

        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            vars.redeemTokens = redeemTokensIn;
            vars.redeemAmount = _mulScalarTruncate(Exp({ mantissa: vars.exchangeRateMantissa }), redeemTokensIn);
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */
            vars.redeemTokens = _divScalarByExpTruncate(redeemAmountIn, Exp({ mantissa: vars.exchangeRateMantissa }));
            vars.redeemAmount = redeemAmountIn;
        }

        vars.collateralTokens = _getCollateralTokens(vars.redeemTokens, redeemer);

        /* redeemAllowed might check more than user's liquidity. */
        require(comptroller.redeemAllowed(address(this), redeemer, vars.collateralTokens) == 0, "rejected");

        /* Verify market's block number equals current block number */
        require(accrualBlockNumber == _getBlockNumber(), "market is stale");

        /* Reverts if protocol has insufficient cash */
        require(_getCashPrior() >= vars.redeemAmount, "insufficient cash");

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We calculate the new total supply and redeemer balance, checking for underflow:
         *  totalSupplyNew = totalSupply - redeemTokens
         *  accountTokensNew = accountTokens[redeemer] - redeemTokens
         */
        totalSupply = _sub(totalSupply, vars.redeemTokens);
        _accountTokens[redeemer] = _sub(_accountTokens[redeemer], vars.redeemTokens);

        /*
         * We only deallocate collateral tokens if the redeemer needs to redeem them.
         */
        _decreaseUserCollateralInternal(redeemer, vars.collateralTokens);

        /*
         * We invoke doTransferOut for the redeemer and the redeemAmount.
         *  Note: The bToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the bToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        _doTransferOut(redeemer, vars.redeemAmount, isNative);

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), vars.redeemTokens);
        emit Redeem(redeemer, vars.redeemAmount, vars.redeemTokens);

        /* We call the defense hook */
        comptroller.redeemVerify(address(this), redeemer, vars.redeemAmount, vars.redeemTokens);

        return uint256(Error.NO_ERROR);
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another BToken.
     *  Its absolutely critical to use msg.sender as the seizer bToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed bToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of bTokens to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _seizeInternal(
        address seizerToken,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) internal returns (uint256) {
        // Make sure accountCollateralTokens of `liquidator` and `borrower` are initialized.
        _initializeAccountCollateralTokens(liquidator);
        _initializeAccountCollateralTokens(borrower);

        uint256 collateralTokens = _getCollateralTokens(seizeTokens, borrower);

        /* Fail if seize not allowed */
        require(
            comptroller.seizeAllowed(address(this), seizerToken, liquidator, borrower, collateralTokens) == 0,
            "rejected"
        );

        /* Fail if borrower = liquidator */
        require(borrower != liquidator, "invalid account pair");

        /*
         * We calculate the new borrower and liquidator token balances and token collateral balances,
         *     failing on underflow/overflow:
         *  accountTokens[borrower] = accountTokens[borrower] - seizeTokens
         *  accountTokens[liquidator] = accountTokens[liquidator] + seizeTokens
         *  accountCollateralTokens[borrower] = accountCollateralTokens[borrower] - collateralTokens
         *  accountCollateralTokens[liquidator] = accountCollateralTokens[liquidator] + collateralTokens
         */
        _accountTokens[borrower] = _sub(_accountTokens[borrower], seizeTokens);
        _accountTokens[liquidator] = _add(_accountTokens[liquidator], seizeTokens);
        if (collateralTokens > 0) {
            accountCollateralTokens[borrower] = _sub(accountCollateralTokens[borrower], collateralTokens);
            accountCollateralTokens[liquidator] = _add(accountCollateralTokens[liquidator], collateralTokens);

            emit UserCollateralChanged(borrower, accountCollateralTokens[borrower]);
            emit UserCollateralChanged(liquidator, accountCollateralTokens[liquidator]);
        }

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, seizeTokens);

        /* We call the defense hook */
        comptroller.seizeVerify(address(this), seizerToken, liquidator, borrower, seizeTokens);

        return uint256(Error.NO_ERROR);
    }
}
