// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./utils/BlueBerryConst.sol" as Constants;
import "./utils/BlueBerryErrors.sol" as Errors;
import "./utils/ERC1155NaiveReceiver.sol";
import "./interfaces/IBank.sol";
import "./interfaces/ICoreOracle.sol";
import "./interfaces/ISoftVault.sol";
import "./interfaces/IHardVault.sol";
import "./interfaces/compound/ICErc20.sol";
import "./libraries/BBMath.sol";

contract BlueBerryBank is OwnableUpgradeable, ERC1155NaiveReceiver, IBank {
    using BBMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private constant _NO_ID = type(uint256).max;
    address private constant _NO_ADDRESS = address(1);

    uint256 public _GENERAL_LOCK; // TEMPORARY: re-entrancy lock guard.
    uint256 public _IN_EXEC_LOCK; // TEMPORARY: exec lock guard.
    uint256 public POSITION_ID; // TEMPORARY: position ID currently under execution.
    address public SPELL; // TEMPORARY: spell currently under execution.

    IProtocolConfig public config;
    ICoreOracle public oracle; // The oracle address for determining prices.
    IFeeManager public feeManager;

    uint256 public nextPositionId; // Next available position ID, starting from 1 (see initialize).
    uint256 public bankStatus; // Each bit stores certain bank status, e.g. borrow allowed, repay allowed

    address[] public allBanks; // The list of all listed banks.
    mapping(address => Bank) public banks; // Mapping from token to bank data.
    mapping(address => bool) public cTokenInBank; // Mapping from cToken to its existence in bank.
    mapping(uint256 => Position) public positions; // Mapping from position ID to position data.

    bool public allowContractCalls; // The boolean status whether to allow call from contract (false = onlyEOA)
    mapping(address => bool) public whitelistedTokens; // Mapping from token to whitelist status
    mapping(address => bool) public whitelistedSpells; // Mapping from spell to whitelist status
    mapping(address => bool) public whitelistedContracts; // Mapping from user to whitelist status

    /// @dev Ensure that the function is called from EOA
    /// when allowContractCalls is set to false and caller is not whitelisted
    modifier onlyEOAEx() {
        if (!allowContractCalls && !whitelistedContracts[msg.sender]) {
            if (msg.sender != tx.origin) revert Errors.NOT_EOA(msg.sender);
        }
        _;
    }

    /// @dev Ensure that the token is already whitelisted
    modifier onlyWhitelistedToken(address token) {
        if (!whitelistedTokens[token])
            revert Errors.TOKEN_NOT_WHITELISTED(token);
        _;
    }

    /// @dev Reentrancy lock guard.
    modifier lock() {
        if (_GENERAL_LOCK != _NOT_ENTERED) revert Errors.LOCKED();
        _GENERAL_LOCK = _ENTERED;
        _;
        _GENERAL_LOCK = _NOT_ENTERED;
    }

    /// @dev Ensure that the function is called from within the execution scope.
    modifier inExec() {
        if (POSITION_ID == _NO_ID) revert Errors.NOT_IN_EXEC();
        if (SPELL != msg.sender) revert Errors.NOT_FROM_SPELL(msg.sender);
        if (_IN_EXEC_LOCK != _NOT_ENTERED) revert Errors.LOCKED();
        _IN_EXEC_LOCK = _ENTERED;
        _;
        _IN_EXEC_LOCK = _NOT_ENTERED;
    }

    /// @dev Ensure that the interest rate of the given token is accrued.
    modifier poke(address token) {
        accrue(token);
        _;
    }

    /// @dev Initialize the bank smart contract, using msg.sender as the first governor.
    /// @param oracle_ The oracle smart contract address.
    /// @param config_ The Protocol config address
    /// @param feeManager_ The Fee manager address
    function initialize(
        ICoreOracle oracle_,
        IProtocolConfig config_,
        IFeeManager feeManager_
    ) external initializer {
        __Ownable_init();
        if (
            address(oracle_) == address(0) ||
            address(config_) == address(0) ||
            address(feeManager_) == address(0)
        ) {
            revert Errors.ZERO_ADDRESS();
        }
        _GENERAL_LOCK = _NOT_ENTERED;
        _IN_EXEC_LOCK = _NOT_ENTERED;
        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;

        config = config_;
        oracle = oracle_;
        feeManager = feeManager_;

        nextPositionId = 1;
        bankStatus = 7; // allow borrow, lend, repay

        emit SetOracle(address(oracle_));
    }

    /// @dev Return the current executor (the owner of the current position).
    function EXECUTOR() external view override returns (address) {
        uint256 positionId = POSITION_ID;
        if (positionId == _NO_ID) {
            revert Errors.NOT_UNDER_EXECUTION();
        }
        return positions[positionId].owner;
    }

    /// @dev Set allowContractCalls
    /// @param ok The status to set allowContractCalls to (false = onlyEOA)
    function setAllowContractCalls(bool ok) external onlyOwner {
        allowContractCalls = ok;
    }

    /// @notice Set whitelist user status
    /// @param contracts list of users to change status
    /// @param statuses list of statuses to change to
    function whitelistContracts(
        address[] calldata contracts,
        bool[] calldata statuses
    ) external onlyOwner {
        if (contracts.length != statuses.length) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }
        for (uint256 idx = 0; idx < contracts.length; idx++) {
            if (contracts[idx] == address(0)) {
                revert Errors.ZERO_ADDRESS();
            }
            whitelistedContracts[contracts[idx]] = statuses[idx];
        }
    }

    /// @dev Set whitelist spell status
    /// @param spells list of spells to change status
    /// @param statuses list of statuses to change to
    function whitelistSpells(
        address[] calldata spells,
        bool[] calldata statuses
    ) external onlyOwner {
        if (spells.length != statuses.length) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }
        for (uint256 idx = 0; idx < spells.length; idx++) {
            if (spells[idx] == address(0)) {
                revert Errors.ZERO_ADDRESS();
            }
            whitelistedSpells[spells[idx]] = statuses[idx];
        }
    }

    /// @dev Set whitelist token status
    /// @param tokens list of tokens to change status
    /// @param statuses list of statuses to change to
    function whitelistTokens(
        address[] calldata tokens,
        bool[] calldata statuses
    ) external onlyOwner {
        if (tokens.length != statuses.length) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (statuses[idx] && !oracle.isTokenSupported(tokens[idx]))
                revert Errors.ORACLE_NOT_SUPPORT(tokens[idx]);
            whitelistedTokens[tokens[idx]] = statuses[idx];
        }
    }

    /**
     * @dev Add a new bank to the ecosystem.
     * @param token The underlying token for the bank.
     * @param softVault The address of softVault.
     * @param hardVault The address of hardVault.
     */
    function addBank(
        address token,
        address softVault,
        address hardVault
    ) external onlyOwner onlyWhitelistedToken(token) {
        if (
            token == address(0) ||
            softVault == address(0) ||
            hardVault == address(0)
        ) revert Errors.ZERO_ADDRESS();

        Bank storage bank = banks[token];
        address cToken = address(ISoftVault(softVault).cToken());

        if (cTokenInBank[cToken]) revert Errors.CTOKEN_ALREADY_ADDED();
        if (bank.isListed) revert Errors.BANK_ALREADY_LISTED();
        if (allBanks.length >= 256) revert Errors.BANK_LIMIT();

        cTokenInBank[cToken] = true;
        bank.isListed = true;
        bank.index = uint8(allBanks.length);
        bank.cToken = cToken;
        bank.softVault = softVault;
        bank.hardVault = hardVault;

        IHardVault(hardVault).setApprovalForAll(hardVault, true);
        allBanks.push(token);

        emit AddBank(token, cToken, softVault, hardVault);
    }

    /// @dev Set bank status
    /// @param _bankStatus new bank status to change to
    function setBankStatus(uint256 _bankStatus) external onlyOwner {
        bankStatus = _bankStatus;
    }

    /// @dev Bank borrow status allowed or not
    /// @notice check last bit of bankStatus
    function isBorrowAllowed() public view returns (bool) {
        return (bankStatus & 0x01) > 0;
    }

    /// @dev Bank repay status allowed or not
    /// @notice Check second-to-last bit of bankStatus
    function isRepayAllowed() public view returns (bool) {
        return (bankStatus & 0x02) > 0;
    }

    /// @dev Bank borrow status allowed or not
    /// @notice check last bit of bankStatus
    function isLendAllowed() public view returns (bool) {
        return (bankStatus & 0x04) > 0;
    }

    /// @dev Trigger interest accrual for the given bank.
    /// @param token The underlying token to trigger the interest accrual.
    function accrue(address token) public override {
        Bank storage bank = banks[token];
        if (!bank.isListed) revert Errors.BANK_NOT_LISTED(token);
        ICErc20(bank.cToken).borrowBalanceCurrent(address(this));
    }

    /// @dev Convenient function to trigger interest accrual for a list of banks.
    /// @param tokens The list of banks to trigger interest accrual.
    function accrueAll(address[] memory tokens) external {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            accrue(tokens[idx]);
        }
    }

    function _borrowBalanceStored(address token)
        internal
        view
        returns (uint256)
    {
        return ICErc20(banks[token].cToken).borrowBalanceStored(address(this));
    }

    /// @dev Trigger interest accrual and return the current borrow balance.
    /// @param positionId The position to query for borrow balance.
    function currentPositionDebt(uint256 positionId)
        external
        override
        poke(positions[positionId].debtToken)
        returns (uint256)
    {
        return getPositionDebt(positionId);
    }

    /// @dev Return the debt of given position.
    /// @param positionId position id to get debts of
    function getPositionDebt(uint256 positionId)
        public
        view
        returns (uint256 debt)
    {
        Position memory pos = positions[positionId];
        Bank memory bank = banks[pos.debtToken];
        if (pos.debtShare == 0 || bank.totalShare == 0) {
            return 0;
        }
        debt = (pos.debtShare * _borrowBalanceStored(pos.debtToken)).divCeil(
            bank.totalShare
        );
    }

    /// @dev Return bank information for the given token.
    /// @param token The token address to query for bank information.
    function getBankInfo(address token)
        external
        view
        override
        returns (
            bool isListed,
            address cToken,
            uint256 totalShare
        )
    {
        Bank storage bank = banks[token];
        return (bank.isListed, bank.cToken, bank.totalShare);
    }

    function getPositionInfo(uint256 positionId)
        external
        view
        override
        returns (Position memory)
    {
        return positions[positionId];
    }

    /// @dev Return current position information
    function getCurrentPositionInfo()
        external
        view
        override
        returns (Position memory)
    {
        if (POSITION_ID == _NO_ID) revert Errors.BAD_POSITION(POSITION_ID);
        return positions[POSITION_ID];
    }

    /**
     * @dev Return the USD value of total collateral of the given position.
     * @param positionId The position ID to query for the collateral value.
     */
    function getPositionValue(uint256 positionId)
        public
        view
        override
        returns (uint256)
    {
        Position storage pos = positions[positionId];
        uint256 size = pos.collateralSize;
        if (size == 0) {
            return 0;
        } else {
            if (pos.collToken == address(0))
                revert Errors.BAD_COLLATERAL(positionId);
            return oracle.getPositionValue(pos.collToken, pos.collId, size);
        }
    }

    /// @dev Return the USD value total debt of the given position
    /// @param positionId The position ID to query for the debt value.
    function getDebtValue(uint256 positionId)
        public
        view
        override
        returns (uint256 debtValue)
    {
        Position memory pos = positions[positionId];
        uint256 debt = getPositionDebt(positionId);
        debtValue = oracle.getTokenValue(pos.debtToken, debt);
    }

    function getPositionRisk(uint256 positionId)
        public
        view
        returns (uint256 risk)
    {
        Position storage pos = positions[positionId];
        uint256 pv = getPositionValue(positionId);
        uint256 ov = getDebtValue(positionId);
        uint256 cv = oracle.getTokenValue(
            pos.underlyingToken,
            pos.underlyingAmount
        );

        if (cv == 0) risk = 0;
        else if (pv >= ov) risk = 0;
        else {
            risk = ((ov - pv) * Constants.DENOMINATOR) / cv;
        }
    }

    function isLiquidatable(uint256 positionId)
        public
        view
        returns (bool liquidatable)
    {
        Position storage pos = positions[positionId];
        uint256 risk = getPositionRisk(positionId);
        liquidatable = risk >= oracle.getLiqThreshold(pos.underlyingToken);
    }

    /// @dev Liquidate a position. Pay debt for its owner and take the collateral.
    /// @param positionId The position ID to liquidate.
    /// @param debtToken The debt token to repay.
    /// @param amountCall The amount to repay when doing transferFrom call.
    function liquidate(
        uint256 positionId,
        address debtToken,
        uint256 amountCall
    ) external override lock poke(debtToken) {
        if (amountCall == 0) revert Errors.ZERO_AMOUNT();
        if (!isLiquidatable(positionId))
            revert Errors.NOT_LIQUIDATABLE(positionId);

        Position storage pos = positions[positionId];
        Bank memory bank = banks[pos.underlyingToken];
        if (pos.collToken == address(0))
            revert Errors.BAD_COLLATERAL(positionId);

        uint256 oldShare = pos.debtShare;
        (uint256 amountPaid, uint256 share) = _repay(
            positionId,
            debtToken,
            amountCall
        );

        uint256 liqSize = (pos.collateralSize * share) / oldShare;
        uint256 uTokenSize = (pos.underlyingAmount * share) / oldShare;
        uint256 uVaultShare = (pos.underlyingVaultShare * share) / oldShare;

        pos.collateralSize -= liqSize;
        pos.underlyingAmount -= uTokenSize;
        pos.underlyingVaultShare -= uVaultShare;

        // Transfer position (Wrapped LP Tokens) to liquidator
        IERC1155Upgradeable(pos.collToken).safeTransferFrom(
            address(this),
            msg.sender,
            pos.collId,
            liqSize,
            ""
        );
        // Transfer underlying collaterals(vault share tokens) to liquidator
        if (_isSoftVault(pos.underlyingToken)) {
            IERC20Upgradeable(bank.softVault).safeTransfer(
                msg.sender,
                uVaultShare
            );
        } else {
            IERC1155Upgradeable(bank.hardVault).safeTransferFrom(
                address(this),
                msg.sender,
                uint256(uint160(pos.underlyingToken)),
                uVaultShare,
                ""
            );
        }

        emit Liquidate(
            positionId,
            msg.sender,
            debtToken,
            amountPaid,
            share,
            liqSize,
            uTokenSize
        );
    }

    /// @dev Execute the action with the supplied data.
    /// @param positionId The position ID to execute the action, or zero for new position.
    /// @param spell The target spell to invoke the execution.
    /// @param data Extra data to pass to the target for the execution.
    function execute(
        uint256 positionId,
        address spell,
        bytes memory data
    ) external payable lock onlyEOAEx returns (uint256) {
        if (!whitelistedSpells[spell])
            revert Errors.SPELL_NOT_WHITELISTED(spell);
        if (positionId == 0) {
            positionId = nextPositionId++;
            positions[positionId].owner = msg.sender;
        } else {
            if (positionId >= nextPositionId)
                revert Errors.BAD_POSITION(positionId);
            if (msg.sender != positions[positionId].owner)
                revert Errors.NOT_FROM_OWNER(positionId, msg.sender);
        }
        POSITION_ID = positionId;
        SPELL = spell;

        (bool ok, bytes memory returndata) = SPELL.call{value: msg.value}(data);
        if (!ok) {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert("bad cast call");
            }
        }

        if (isLiquidatable(positionId)) revert Errors.INSUFFICIENT_COLLATERAL();

        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;

        emit Execute(positionId, msg.sender);

        return positionId;
    }

    /**
     * @dev Lend tokens to bank as isolated collateral. Must only be called while under execution.
     * @param token The token to deposit on bank as isolated collateral
     * @param amount The amount of tokens to lend.
     */
    function lend(address token, uint256 amount)
        external
        override
        inExec
        poke(token)
        onlyWhitelistedToken(token)
    {
        if (!isLendAllowed()) revert Errors.LEND_NOT_ALLOWED();

        Position storage pos = positions[POSITION_ID];
        Bank storage bank = banks[token];
        if (pos.underlyingToken != address(0)) {
            // already have isolated collateral, allow same isolated collateral
            if (pos.underlyingToken != token)
                revert Errors.INCORRECT_UNDERLYING(token);
        } else {
            pos.underlyingToken = token;
        }

        IERC20Upgradeable(token).safeTransferFrom(
            pos.owner,
            address(this),
            amount
        );
        IERC20Upgradeable(token).approve(address(feeManager), amount);
        amount = feeManager.doCutDepositFee(token, amount);
        pos.underlyingAmount += amount;
        bank.totalLend += amount;

        if (_isSoftVault(token)) {
            IERC20Upgradeable(token).approve(bank.softVault, amount);
            pos.underlyingVaultShare += ISoftVault(bank.softVault).deposit(
                amount
            );
        } else {
            IERC20Upgradeable(token).approve(bank.hardVault, amount);
            pos.underlyingVaultShare += IHardVault(bank.hardVault).deposit(
                token,
                amount
            );
        }

        emit Lend(POSITION_ID, msg.sender, token, amount);
    }

    /**
     * @dev Withdraw isolated collateral tokens lent to bank. Must only be called from spell while under execution.
     * @param token Isolated collateral token address
     * @param shareAmount The amount of vaule share token to withdraw.
     */
    function withdrawLend(address token, uint256 shareAmount)
        external
        override
        inExec
        poke(token)
    {
        Position storage pos = positions[POSITION_ID];
        Bank storage bank = banks[token];
        if (token != pos.underlyingToken) revert Errors.INVALID_UTOKEN(token);
        if (shareAmount == type(uint256).max) {
            shareAmount = pos.underlyingVaultShare;
        }

        uint256 wAmount;
        if (_isSoftVault(token)) {
            ISoftVault(bank.softVault).approve(bank.softVault, shareAmount);
            wAmount = ISoftVault(bank.softVault).withdraw(shareAmount);
        } else {
            wAmount = IHardVault(bank.hardVault).withdraw(token, shareAmount);
        }

        wAmount = wAmount > pos.underlyingAmount
            ? pos.underlyingAmount
            : wAmount;

        pos.underlyingVaultShare -= shareAmount;
        pos.underlyingAmount -= wAmount;
        bank.totalLend -= wAmount;

        IERC20Upgradeable(token).approve(address(feeManager), wAmount);
        wAmount = feeManager.doCutWithdrawFee(token, wAmount);

        IERC20Upgradeable(token).safeTransfer(msg.sender, wAmount);
    }

    /// @dev Borrow tokens from given bank. Must only be called from spell while under execution.
    /// @param token The token to borrow from the bank.
    /// @param amount The amount of tokens to borrow.
    function borrow(address token, uint256 amount)
        external
        override
        inExec
        poke(token)
        onlyWhitelistedToken(token)
    {
        if (!isBorrowAllowed()) revert Errors.BORROW_NOT_ALLOWED();
        Bank storage bank = banks[token];
        Position storage pos = positions[POSITION_ID];
        if (pos.debtToken != address(0)) {
            // already have some debts, allow same debt token
            if (pos.debtToken != token) revert Errors.INCORRECT_DEBT(token);
        } else {
            pos.debtToken = token;
        }

        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = _borrowBalanceStored(token);
        uint256 share = totalShare == 0
            ? amount
            : (amount * totalShare).divCeil(totalDebt);
        bank.totalShare += share;
        pos.debtShare += share;
        IERC20Upgradeable(token).safeTransfer(
            msg.sender,
            _doBorrow(token, amount)
        );
        emit Borrow(POSITION_ID, msg.sender, token, amount, share);
    }

    /// @dev Repay tokens to the bank. Must only be called while under execution.
    /// @param token The token to repay to the bank.
    /// @param amountCall The amount of tokens to repay via transferFrom.
    function repay(address token, uint256 amountCall)
        external
        override
        inExec
        poke(token)
        onlyWhitelistedToken(token)
    {
        if (!isRepayAllowed()) revert Errors.REPAY_NOT_ALLOWED();
        (uint256 amount, uint256 share) = _repay(
            POSITION_ID,
            token,
            amountCall
        );
        emit Repay(POSITION_ID, msg.sender, token, amount, share);
    }

    /// @dev Perform repay action. Return the amount actually taken and the debt share reduced.
    /// @param positionId The position ID to repay the debt.
    /// @param token The bank token to pay the debt.
    /// @param amountCall The amount to repay by calling transferFrom, or -1 for debt size.
    function _repay(
        uint256 positionId,
        address token,
        uint256 amountCall
    ) internal returns (uint256, uint256) {
        Bank storage bank = banks[token];
        Position storage pos = positions[positionId];
        if (pos.debtToken != token) revert Errors.INCORRECT_DEBT(token);
        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = _borrowBalanceStored(token);
        uint256 oldShare = pos.debtShare;
        uint256 oldDebt = (oldShare * totalDebt).divCeil(totalShare);
        if (amountCall == type(uint256).max) {
            amountCall = oldDebt;
        }
        amountCall = _doERC20TransferIn(token, amountCall);
        uint256 paid = _doRepay(token, amountCall);
        if (paid > oldDebt) revert Errors.REPAY_EXCEEDS_DEBT(paid, oldDebt); // prevent share overflow attack
        uint256 lessShare = paid == oldDebt
            ? oldShare
            : (paid * totalShare) / totalDebt;
        bank.totalShare -= lessShare;
        pos.debtShare -= lessShare;
        return (paid, lessShare);
    }

    /// @dev Put more collateral for users. Must only be called during execution.
    /// @param collToken The ERC1155 token wrapped for collateral. (Wrapped token of LP)
    /// @param collId The token id to collateral. (Uint256 format of LP address)
    /// @param amountCall The amount of tokens to put via transferFrom.
    function putCollateral(
        address collToken,
        uint256 collId,
        uint256 amountCall
    ) external override inExec {
        Position storage pos = positions[POSITION_ID];
        if (pos.collToken != collToken || pos.collId != collId) {
            if (!oracle.isWrappedTokenSupported(collToken, collId))
                revert Errors.ORACLE_NOT_SUPPORT_WTOKEN(collToken);
            if (pos.collateralSize > 0)
                revert Errors.ANOTHER_COL_EXIST(pos.collToken);
            pos.collToken = collToken;
            pos.collId = collId;
        }
        uint256 amount = _doERC1155TransferIn(collToken, collId, amountCall);
        pos.collateralSize += amount;
        emit PutCollateral(
            POSITION_ID,
            pos.owner,
            msg.sender,
            collToken,
            collId,
            amount
        );
    }

    /// @dev Take some collateral back. Must only be called during execution.
    /// @param amount The amount of tokens to take back via transfer.
    function takeCollateral(uint256 amount)
        external
        override
        inExec
        returns (uint256)
    {
        Position storage pos = positions[POSITION_ID];
        if (amount == type(uint256).max) {
            amount = pos.collateralSize;
        }
        pos.collateralSize -= amount;
        IERC1155Upgradeable(pos.collToken).safeTransferFrom(
            address(this),
            msg.sender,
            pos.collId,
            amount,
            ""
        );
        emit TakeCollateral(
            POSITION_ID,
            msg.sender,
            pos.collToken,
            pos.collId,
            amount
        );

        return amount;
    }

    /**
     * @dev Internal function to perform borrow from the bank and return the amount received.
     * @param token The token to perform borrow action.
     * @param amountCall The amount use in the transferFrom call.
     * NOTE: Caller must ensure that cToken interest was already accrued up to this block.
     */
    function _doBorrow(address token, uint256 amountCall)
        internal
        returns (uint256 borrowAmount)
    {
        Bank storage bank = banks[token]; // assume the input is already sanity checked.

        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        if (ICErc20(bank.cToken).borrow(amountCall) != 0)
            revert Errors.BORROW_FAILED(amountCall);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        borrowAmount = uBalanceAfter - uBalanceBefore;
    }

    /**
     * @dev Internal function to perform repay to the bank and return the amount actually repaid.
     * @param token The token to perform repay action.
     * @param amountCall The amount to use in the repay call.
     * NOTE: Caller must ensure that cToken interest was already accrued up to this block.
     */
    function _doRepay(address token, uint256 amountCall)
        internal
        returns (uint256 repaidAmount)
    {
        Bank storage bank = banks[token]; // assume the input is already sanity checked.
        IERC20Upgradeable(token).approve(bank.cToken, amountCall);
        uint256 beforeDebt = _borrowBalanceStored(token);
        if (ICErc20(bank.cToken).repayBorrow(amountCall) != 0)
            revert Errors.REPAY_FAILED(amountCall);
        uint256 newDebt = _borrowBalanceStored(token);
        repaidAmount = beforeDebt - newDebt;
    }

    /// @dev Internal function to perform ERC20 transfer in and return amount actually received.
    /// @param token The token to perform transferFrom action.
    /// @param amountCall The amount use in the transferFrom call.
    function _doERC20TransferIn(address token, uint256 amountCall)
        internal
        returns (uint256)
    {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(
            address(this)
        );
        IERC20Upgradeable(token).safeTransferFrom(
            msg.sender,
            address(this),
            amountCall
        );
        uint256 balanceAfter = IERC20Upgradeable(token).balanceOf(
            address(this)
        );
        return balanceAfter - balanceBefore;
    }

    /// @dev Internal function to perform ERC1155 transfer in and return amount actually received.
    /// @param token The token to perform transferFrom action.
    /// @param id The id to perform transferFrom action.
    /// @param amountCall The amount use in the transferFrom call.
    function _doERC1155TransferIn(
        address token,
        uint256 id,
        uint256 amountCall
    ) internal returns (uint256) {
        uint256 balanceBefore = IERC1155Upgradeable(token).balanceOf(
            address(this),
            id
        );
        IERC1155Upgradeable(token).safeTransferFrom(
            msg.sender,
            address(this),
            id,
            amountCall,
            ""
        );
        uint256 balanceAfter = IERC1155Upgradeable(token).balanceOf(
            address(this),
            id
        );
        return balanceAfter - balanceBefore;
    }

    function _isSoftVault(address token) internal view returns (bool) {
        Bank storage bank = banks[token];
        return address(ISoftVault(bank.softVault).uToken()) == token;
    }
}
