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

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { BBMath } from "./libraries/BBMath.sol";
import { UniversalERC20, IERC20 } from "./libraries/UniversalERC20.sol";

import { ERC1155NaiveReceiver } from "./utils/ERC1155NaiveReceiver.sol";
import "./utils/BlueberryConst.sol" as Constants;
import "./utils/BlueberryErrors.sol" as Errors;

import { IBank } from "./interfaces/IBank.sol";
import { IBErc20 } from "./interfaces/money-market/IBErc20.sol";
import { ICoreOracle } from "./interfaces/ICoreOracle.sol";
import { IERC20Wrapper } from "./interfaces/IERC20Wrapper.sol";
import { IFeeManager } from "./interfaces/IFeeManager.sol";
import { IHardVault } from "./interfaces/IHardVault.sol";
import { IProtocolConfig } from "./interfaces/IProtocolConfig.sol";
import { ISoftVault } from "./interfaces/ISoftVault.sol";

/**
 * @title BlueberryBank
 * @author BlueberryProtocol
 * @notice Blueberry Bank is the main contract that stores user's positions and track the borrowing of tokens
 */
contract BlueberryBank is IBank, Ownable2StepUpgradeable, ERC1155NaiveReceiver {
    using BBMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UniversalERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private constant _NO_ID = type(uint256).max;
    address private constant _NO_ADDRESS = address(1);

    /* solhint-disable var-name-mixedcase */
    uint256 private _GENERAL_LOCK; /// @dev TEMPORARY: re-entrancy lock guard.
    uint256 private _IN_EXEC_LOCK; /// @dev TEMPORARY: exec lock guard.
    uint256 private _POSITION_ID; /// @dev TEMPORARY: position ID currently under execution.
    address private _SPELL; /// @dev TEMPORARY: spell currently under execution.
    /* solhint-enable var-name-mixedcase */

    IProtocolConfig private _config; /// @dev The protocol _config address.
    ICoreOracle private _oracle; /// @dev The main _oracle address.

    uint256 internal _nextPositionId; /// @dev Next available position ID, starting from 1 (see initialize).
    uint256 internal _bankStatus; /// @dev Each bit stores certain bank status, e.g. borrow allowed, repay allowed
    uint256 internal _repayResumedTimestamp; /// @dev Timestamp that repay is allowed or resumed

    address[] internal _allBanks; /// @dev The list of all listed banks.
    mapping(address => Bank) internal _banks; /// @dev Mapping from token to bank data.
    mapping(address => bool) internal _bTokenInBank; /// @dev Mapping from bToken to its existence in bank.
    mapping(uint256 => Position) internal _positions; /// @dev Mapping from position ID to position data.

    mapping(address => bool) private _whitelistedTokens; /// @dev Mapping from token to whitelist status
    mapping(address => bool) private _whitelistedWrappedTokens; /// @dev Mapping from token to whitelist status
    mapping(address => bool) private _whitelistedSpells; /// @dev Mapping from spell to whitelist status

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Ensure that the token is already whitelisted
    modifier onlyWhitelistedToken(address token) {
        if (!_whitelistedTokens[token]) revert Errors.TOKEN_NOT_WHITELISTED(token);
        _;
    }

    /// @dev Ensure that the wrapped ERC1155 is already whitelisted
    modifier onlyWhitelistedERC1155(address token) {
        if (!_whitelistedWrappedTokens[token]) revert Errors.TOKEN_NOT_WHITELISTED(token);
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
        if (_POSITION_ID == _NO_ID) revert Errors.NOT_IN_EXEC();
        if (_SPELL != msg.sender) revert Errors.NOT_FROM_SPELL(msg.sender);
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

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
    /**
     * @notice Initializes the Blueberry Bank contract.
     * @param oracle The address of the Core Oracle contract.
     * @param config The address of the config contract.
     * @param owner The address of the owner.
     */
    function initialize(ICoreOracle oracle, IProtocolConfig config, address owner) external initializer {
        __Ownable2Step_init();
        _transferOwnership(owner);
        if (address(oracle) == address(0) || address(config) == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        _GENERAL_LOCK = _NOT_ENTERED;
        _IN_EXEC_LOCK = _NOT_ENTERED;
        _POSITION_ID = _NO_ID;
        _SPELL = _NO_ADDRESS;

        _config = config;
        _oracle = oracle;

        _nextPositionId = 1;
        _bankStatus = 15; // 0x1111: allow borrow, repay, lend, withdrawLend as default

        emit SetOracle(address(oracle));
    }

    /// @inheritdoc IBank
    function liquidate(
        uint256 positionId,
        address debtToken,
        uint256 amountCall
    ) external override lock poke(debtToken) {
        /// Ensures repayments are allowed at the moment of calling this function.
        if (!isRepayAllowed()) revert Errors.REPAY_NOT_ALLOWED();
        /// Ensures a non-zero repayment amount is specified.
        if (amountCall == 0) revert Errors.ZERO_AMOUNT();
        /// Ensures the position is liquidatable.
        if (!isLiquidatable(positionId)) revert Errors.NOT_LIQUIDATABLE(positionId);

        /// Retrieve the position and associated bank data.
        Position storage pos = _positions[positionId];
        Bank memory bank = _banks[pos.underlyingToken];
        /// Ensure the position has valid collateral.
        if (pos.collToken == address(0)) revert Errors.BAD_COLLATERAL(positionId);

        /// Revert liquidation if the repayment hasn't been warmed up
        /// following the last state where repayments were paused.
        if (block.timestamp < _repayResumedTimestamp + Constants.LIQUIDATION_REPAY_WARM_UP_PERIOD) {
            revert Errors.REPAY_ALLOW_NOT_WARMED_UP();
        }

        /// Repay the debt and get details of repayment.
        uint256 oldShare = pos.debtShare;
        (uint256 amountPaid, uint256 share) = _repay(positionId, debtToken, amountCall);

        /// Calculate the size of collateral and underlying vault share that the liquidator will get.
        uint256 liqSize = (pos.collateralSize * share) / oldShare;
        uint256 uVaultShare = (pos.underlyingVaultShare * share) / oldShare;

        /// Adjust the position's debt and collateral after liquidation.
        pos.collateralSize -= liqSize;
        pos.underlyingVaultShare -= uVaultShare;

        /// Transfer the liquidated collateral (Wrapped LP Tokens) to the liquidator.
        IERC1155Upgradeable(pos.collToken).safeTransferFrom(address(this), msg.sender, pos.collId, liqSize, "");
        /// Transfer underlying collaterals(vault share tokens) to liquidator
        if (_isSoftVault(pos.underlyingToken)) {
            IERC20Upgradeable(bank.softVault).safeTransfer(msg.sender, uVaultShare);
        } else {
            IERC1155Upgradeable(bank.hardVault).safeTransferFrom(
                address(this),
                msg.sender,
                uint256(uint160(pos.underlyingToken)),
                uVaultShare,
                ""
            );
        }

        /// Emit an event capturing details of the liquidation process.
        emit Liquidate(positionId, msg.sender, debtToken, amountPaid, share, liqSize, uVaultShare);
    }

    /// @inheritdoc IBank
    function execute(uint256 positionId, address spell, bytes memory data) external lock returns (uint256) {
        if (!_whitelistedSpells[spell]) revert Errors.SPELL_NOT_WHITELISTED(spell);
        if (positionId == 0) {
            positionId = _nextPositionId++;
            _positions[positionId].owner = msg.sender;
        } else {
            if (positionId >= _nextPositionId) revert Errors.BAD_POSITION(positionId);
            if (msg.sender != _positions[positionId].owner) revert Errors.NOT_FROM_OWNER(positionId, msg.sender);
        }
        _POSITION_ID = positionId;
        _SPELL = spell;

        (bool ok, bytes memory returndata) = spell.call(data);
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

        accrue(_positions[positionId].underlyingToken);
        if (isLiquidatable(positionId)) revert Errors.INSUFFICIENT_COLLATERAL();

        _POSITION_ID = _NO_ID;
        _SPELL = _NO_ADDRESS;

        emit Execute(positionId, msg.sender);

        return positionId;
    }

    /// @inheritdoc IBank
    function lend(address token, uint256 amount) external override inExec poke(token) onlyWhitelistedToken(token) {
        if (!isLendAllowed()) revert Errors.LEND_NOT_ALLOWED();

        Position storage pos = _positions[_POSITION_ID];
        Bank storage bank = _banks[token];
        if (pos.underlyingToken != address(0)) {
            /// already have isolated collateral, allow same isolated collateral
            if (pos.underlyingToken != token) revert Errors.INCORRECT_UNDERLYING(token);
        } else {
            pos.underlyingToken = token;
        }

        IFeeManager feeManager = getFeeManager();

        IERC20Upgradeable(token).safeTransferFrom(pos.owner, address(this), amount);
        IERC20(token).universalApprove(address(feeManager), amount);
        amount = feeManager.doCutDepositFee(token, amount);

        if (_isSoftVault(token)) {
            IERC20(token).universalApprove(bank.softVault, amount);
            pos.underlyingVaultShare += ISoftVault(bank.softVault).deposit(amount);
        } else {
            IERC20(token).universalApprove(bank.hardVault, amount);
            pos.underlyingVaultShare += IHardVault(bank.hardVault).deposit(token, amount);
        }

        emit Lend(_POSITION_ID, msg.sender, token, amount);
    }

    /// @inheritdoc IBank
    function withdrawLend(address token, uint256 shareAmount) external override inExec poke(token) {
        if (!isWithdrawLendAllowed()) revert Errors.WITHDRAW_LEND_NOT_ALLOWED();
        Position storage pos = _positions[_POSITION_ID];
        Bank memory bank = _banks[token];
        if (token != pos.underlyingToken) revert Errors.INVALID_UTOKEN(token);
        if (shareAmount == type(uint256).max) {
            shareAmount = pos.underlyingVaultShare;
        }
        uint256 wAmount;
        if (_isSoftVault(token)) {
            IERC20(bank.softVault).universalApprove(bank.softVault, shareAmount);
            wAmount = ISoftVault(bank.softVault).withdraw(shareAmount);
        } else {
            wAmount = IHardVault(bank.hardVault).withdraw(token, shareAmount);
        }

        IFeeManager feeManager = getFeeManager();

        pos.underlyingVaultShare -= shareAmount;
        IERC20(token).universalApprove(address(feeManager), wAmount);
        wAmount = feeManager.doCutWithdrawFee(token, wAmount);
        IERC20Upgradeable(token).safeTransfer(msg.sender, wAmount);
        emit WithdrawLend(_POSITION_ID, msg.sender, token, wAmount);
    }

    /// @inheritdoc IBank
    function borrow(
        address token,
        uint256 amount
    ) external override inExec poke(token) onlyWhitelistedToken(token) returns (uint256 borrowedAmount) {
        if (!isBorrowAllowed()) revert Errors.BORROW_NOT_ALLOWED();
        Bank storage bank = _banks[token];
        Position storage pos = _positions[_POSITION_ID];
        if (pos.debtToken != address(0)) {
            /// already have some debts, allow same debt token
            if (pos.debtToken != token) revert Errors.INCORRECT_DEBT(token);
        } else {
            pos.debtToken = token;
        }

        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = _borrowBalanceStored(token);
        uint256 share = totalShare == 0 ? amount : (amount * totalShare).divCeil(totalDebt);
        if (share == 0) revert Errors.BORROW_ZERO_SHARE(amount);
        bank.totalShare += share;
        pos.debtShare += share;

        borrowedAmount = _doBorrow(token, amount);
        IERC20Upgradeable(token).safeTransfer(msg.sender, borrowedAmount);

        emit Borrow(_POSITION_ID, msg.sender, token, amount, share);
    }

    /// @inheritdoc IBank
    function repay(address token, uint256 amountCall) external override inExec poke(token) onlyWhitelistedToken(token) {
        if (!isRepayAllowed()) revert Errors.REPAY_NOT_ALLOWED();
        (uint256 amount, uint256 share) = _repay(_POSITION_ID, token, amountCall);
        emit Repay(_POSITION_ID, msg.sender, token, amount, share);
    }

    /// @inheritdoc IBank
    function putCollateral(
        address collToken,
        uint256 collId,
        uint256 amountCall
    ) external override inExec onlyWhitelistedERC1155(collToken) {
        Position storage pos = _positions[_POSITION_ID];
        if (pos.collToken != collToken || pos.collId != collId) {
            if (!_oracle.isWrappedTokenSupported(collToken, collId)) {
                revert Errors.ORACLE_NOT_SUPPORT_WTOKEN(collToken);
            }

            if (pos.collateralSize > 0) revert Errors.DIFF_COL_EXIST(pos.collToken);

            pos.collToken = collToken;
            pos.collId = collId;
        }
        uint256 amount = _doERC1155TransferIn(collToken, collId, amountCall);
        pos.collateralSize += amount;
        emit PutCollateral(_POSITION_ID, pos.owner, msg.sender, collToken, collId, amount);
    }

    /// @inheritdoc IBank
    function takeCollateral(uint256 amount) external override inExec returns (uint256) {
        Position storage pos = _positions[_POSITION_ID];

        if (amount == type(uint256).max) {
            amount = pos.collateralSize;
        }

        pos.collateralSize -= amount;
        IERC1155Upgradeable(pos.collToken).safeTransferFrom(address(this), msg.sender, pos.collId, amount, "");

        emit TakeCollateral(_POSITION_ID, msg.sender, pos.collToken, pos.collId, amount);
        return amount;
    }

    /// @inheritdoc IBank
    function currentPositionDebt(
        uint256 positionId
    ) external override poke(_positions[positionId].debtToken) returns (uint256) {
        return getPositionDebt(positionId);
    }

    /// @inheritdoc IBank
    function accrue(address token) public override {
        Bank storage bank = _banks[token];
        if (!bank.isListed) revert Errors.BANK_NOT_LISTED(token);
        IBErc20(bank.bToken).borrowBalanceCurrent(address(this));
    }

    /// @inheritdoc IBank
    function accrueAll(address[] memory tokens) external {
        for (uint256 i = 0; i < tokens.length; ++i) {
            accrue(tokens[i]);
        }
    }

    function whitelistSpells(address[] calldata spells, bool[] calldata statuses) external onlyOwner {
        if (spells.length != statuses.length) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }
        for (uint256 i = 0; i < spells.length; ++i) {
            if (spells[i] == address(0)) {
                revert Errors.ZERO_ADDRESS();
            }
            _whitelistedSpells[spells[i]] = statuses[i];
        }
    }

    function whitelistTokens(address[] calldata tokens, bool[] calldata statuses) external onlyOwner {
        if (tokens.length != statuses.length) {
            revert Errors.INPUT_ARRAY_MISMATCH();
        }
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (statuses[i] && !_oracle.isTokenSupported(tokens[i])) revert Errors.ORACLE_NOT_SUPPORT(tokens[i]);
            _whitelistedTokens[tokens[i]] = statuses[i];
            emit SetWhitelistToken(tokens[i], statuses[i]);
        }
    }

    function whitelistERC1155(address[] memory tokens, bool ok) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) revert Errors.ZERO_ADDRESS();
            _whitelistedWrappedTokens[token] = ok;
            emit SetWhitelistERC1155(token, ok);
        }
    }

    function addBank(
        address token,
        address softVault,
        address hardVault,
        uint256 liqThreshold
    ) external onlyOwner onlyWhitelistedToken(token) {
        if (softVault == address(0) || hardVault == address(0)) revert Errors.ZERO_ADDRESS();
        if (liqThreshold > Constants.DENOMINATOR) revert Errors.LIQ_THRESHOLD_TOO_HIGH(liqThreshold);
        if (liqThreshold < Constants.MIN_LIQ_THRESHOLD) revert Errors.LIQ_THRESHOLD_TOO_LOW(liqThreshold);

        Bank storage bank = _banks[token];
        address bToken = address(ISoftVault(softVault).getBToken());

        if (_bTokenInBank[bToken]) revert Errors.BTOKEN_ALREADY_ADDED();
        if (bank.isListed) revert Errors.BANK_ALREADY_LISTED();

        uint256 _allBanksLength = _allBanks.length;

        if (_allBanksLength >= 256) revert Errors.BANK_LIMIT();

        _bTokenInBank[bToken] = true;
        bank.isListed = true;
        bank.index = uint8(_allBanksLength);
        bank.bToken = bToken;
        bank.softVault = softVault;
        bank.hardVault = hardVault;
        bank.liqThreshold = liqThreshold;

        IHardVault(hardVault).setApprovalForAll(hardVault, true);
        _allBanks.push(token);

        emit AddBank(token, bToken, softVault, hardVault);
    }

    function modifyBank(
        uint8 bankIndex,
        address token,
        address softVault,
        address hardVault,
        uint256 liqThreshold
    ) external onlyOwner onlyWhitelistedToken(token) {
        if (softVault == address(0) || hardVault == address(0)) revert Errors.ZERO_ADDRESS();
        if (liqThreshold > Constants.DENOMINATOR) revert Errors.LIQ_THRESHOLD_TOO_HIGH(liqThreshold);
        if (liqThreshold < Constants.MIN_LIQ_THRESHOLD) revert Errors.LIQ_THRESHOLD_TOO_LOW(liqThreshold);
        if (bankIndex >= _allBanks.length) revert Errors.BANK_NOT_EXIST(bankIndex);

        address bankToken = _allBanks[bankIndex];
        Bank storage bank = _banks[bankToken];
        address bToken = address(ISoftVault(softVault).getBToken());

        bank.bToken = bToken;
        bank.softVault = softVault;
        bank.hardVault = hardVault;
        bank.liqThreshold = liqThreshold;

        IHardVault(hardVault).setApprovalForAll(hardVault, true);

        emit ModifyBank(token, bToken, softVault, hardVault);
    }

    function setBankStatus(uint256 bankStatus) external onlyOwner {
        bool repayAllowedStatusBefore = isRepayAllowed();
        _bankStatus = bankStatus;
        bool repayAllowedStatusAfter = isRepayAllowed();

        /// If the repayAllowed status changes from "off" to "on", update the timestamp.
        if (!repayAllowedStatusBefore && repayAllowedStatusAfter) {
            _repayResumedTimestamp = block.timestamp;
        }
    }

    /// @inheritdoc IBank
    function isBorrowAllowed() public view override returns (bool) {
        return (_bankStatus & 0x01) > 0;
    }

    /// @inheritdoc IBank
    function isRepayAllowed() public view override returns (bool) {
        return (_bankStatus & 0x02) > 0;
    }

    /// @inheritdoc IBank
    function isLendAllowed() public view override returns (bool) {
        return (_bankStatus & 0x04) > 0;
    }

    /// @inheritdoc IBank
    function isWithdrawLendAllowed() public view override returns (bool) {
        return (_bankStatus & 0x08) > 0;
    }

    /// @inheritdoc IBank
    function getFeeManager() public view override returns (IFeeManager) {
        return _config.getFeeManager();
    }

    /// @inheritdoc IBank
    function getBankStatus() external view returns (uint256) {
        return _bankStatus;
    }

    /// @inheritdoc IBank
    function getRepayResumedTimestamp() external view returns (uint256) {
        return _repayResumedTimestamp;
    }

    /// @inheritdoc IBank
    function isTokenWhitelisted(address token) external view returns (bool) {
        return _whitelistedTokens[token];
    }

    /// @inheritdoc IBank
    function isWrappedTokenWhitelisted(address token) external view returns (bool) {
        return _whitelistedWrappedTokens[token];
    }

    /// @inheritdoc IBank
    function isSpellWhitelisted(address spell) external view returns (bool) {
        return _whitelistedSpells[spell];
    }

    /// @inheritdoc IBank
    function getNextPositionId() external view override returns (uint256) {
        return _nextPositionId;
    }

    /// @inheritdoc IBank
    function getConfig() external view override returns (IProtocolConfig) {
        return _config;
    }

    /// @inheritdoc IBank
    function getOracle() external view override returns (ICoreOracle) {
        return _oracle;
    }

    /// @inheritdoc IBank
    function getAllBanks() external view override returns (address[] memory) {
        return _allBanks;
    }

    /// @inheritdoc IBank
    function getPositionDebt(uint256 positionId) public view override returns (uint256 debt) {
        Position memory pos = _positions[positionId];
        Bank memory bank = _banks[pos.debtToken];
        if (pos.debtShare == 0 || bank.totalShare == 0) {
            return 0;
        }
        debt = (pos.debtShare * _borrowBalanceStored(pos.debtToken)).divCeil(bank.totalShare);
    }

    /// @inheritdoc IBank
    function getBankInfo(address token) external view override returns (Bank memory bank) {
        bank = _banks[token];
    }

    /// @inheritdoc IBank
    function getPositionInfo(uint256 positionId) external view override returns (Position memory) {
        return _positions[positionId];
    }

    /// @inheritdoc IBank
    function getCurrentPositionInfo() external view override returns (Position memory) {
        if (_POSITION_ID == _NO_ID) revert Errors.BAD_POSITION(_POSITION_ID);
        return _positions[_POSITION_ID];
    }

    /// @inheritdoc IBank
    function getPositionValue(uint256 positionId) public view override returns (uint256 positionValue) {
        Position memory pos = _positions[positionId];
        if (pos.collateralSize == 0) {
            return 0;
        } else {
            if (pos.collToken == address(0)) revert Errors.BAD_COLLATERAL(positionId);
            uint256 collValue = _oracle.getWrappedTokenValue(pos.collToken, pos.collId, pos.collateralSize);

            uint256 rewardsValue;
            (address[] memory tokens, uint256[] memory rewards) = IERC20Wrapper(pos.collToken).pendingRewards(
                pos.collId,
                pos.collateralSize
            );

            for (uint256 i; i < tokens.length; ++i) {
                if (_oracle.isTokenSupported(tokens[i])) {
                    rewardsValue += _oracle.getTokenValue(tokens[i], rewards[i]);
                }
            }

            return collValue + rewardsValue;
        }
    }

    /// @inheritdoc IBank
    function getDebtValue(uint256 positionId) public view override returns (uint256 debtValue) {
        Position memory pos = _positions[positionId];
        uint256 debt = getPositionDebt(positionId);
        debtValue = _oracle.getTokenValue(pos.debtToken, debt);
    }

    /// @inheritdoc IBank
    function getIsolatedCollateralValue(uint256 positionId) public view override returns (uint256 icollValue) {
        Position memory pos = _positions[positionId];
        /// NOTE: exchangeRateStored has 18 decimals.
        uint256 underlyingAmount;
        if (_isSoftVault(pos.underlyingToken)) {
            underlyingAmount =
                (IBErc20(_banks[pos.underlyingToken].bToken).exchangeRateStored() * pos.underlyingVaultShare) /
                Constants.PRICE_PRECISION;
        } else {
            underlyingAmount = pos.underlyingVaultShare;
        }
        icollValue = _oracle.getTokenValue(pos.underlyingToken, underlyingAmount);
    }

    /// @inheritdoc IBank
    function getPositionRisk(uint256 positionId) public view override returns (uint256 risk) {
        uint256 pv = getPositionValue(positionId);
        uint256 ov = getDebtValue(positionId);
        uint256 cv = getIsolatedCollateralValue(positionId);

        if (
            (cv == 0 && pv == 0 && ov == 0) || pv >= ov /// Closed position or Overcollateralized position
        ) {
            risk = 0;
        } else if (cv == 0) {
            /// Sth bad happened to isolated underlying token
            risk = Constants.DENOMINATOR;
        } else {
            risk = ((ov - pv) * Constants.DENOMINATOR) / cv;
        }
    }

    /// @inheritdoc IBank
    function isLiquidatable(uint256 positionId) public view override returns (bool) {
        return getPositionRisk(positionId) >= _banks[_positions[positionId].underlyingToken].liqThreshold;
    }

    /**
     * @notice Internal function that handles the logic for repaying tokens.
     * @param positionId The position ID which determines the debt to be repaid.
     * @param token The bank token used to repay the debt.
     * @param amountCall The amount specified by the caller to repay by calling `transferFrom`, or -1 for debt size.
     * @return Returns the actual repaid amount and the reduced debt share.
     */
    function _repay(uint256 positionId, address token, uint256 amountCall) internal returns (uint256, uint256) {
        Bank storage bank = _banks[token];
        Position storage pos = _positions[positionId];

        if (pos.debtToken != token) revert Errors.INCORRECT_DEBT(token);

        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = _borrowBalanceStored(token);
        uint256 oldShare = pos.debtShare;
        uint256 oldDebt = (oldShare * totalDebt).divCeil(totalShare);

        if (amountCall > oldDebt) {
            amountCall = oldDebt;
        }

        amountCall = _doERC20TransferIn(token, amountCall);
        uint256 paid = _doRepay(token, amountCall);

        if (paid > oldDebt) revert Errors.REPAY_EXCEEDS_DEBT(paid, oldDebt); /// prevent share overflow attack

        uint256 lessShare = paid == oldDebt ? oldShare : (paid * totalShare) / totalDebt;
        bank.totalShare -= lessShare;
        pos.debtShare -= lessShare;

        return (paid, lessShare);
    }

    /**
     * @dev Internal function to return the current borrow balance of the given token.
     * @param token The token address to query for borrow balance.
     */
    function _borrowBalanceStored(address token) internal view returns (uint256) {
        return IBErc20(_banks[token].bToken).borrowBalanceStored(address(this));
    }

    /**
     * @notice Internal function that handles the borrowing logic.
     * @dev Borrows the specified amount of tokens and returns the actual borrowed amount.
     * NOTE: Caller must ensure that bToken interest was already accrued up to this block.
     * @param token The token to borrow.
     * @param amountCall The amount of tokens to be borrowed.
     * @return borrowAmount The actual amount borrowed.
     */
    function _doBorrow(address token, uint256 amountCall) internal returns (uint256 borrowAmount) {
        address bToken = _banks[token].bToken;

        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        if (IBErc20(bToken).borrow(amountCall) != 0) revert Errors.BORROW_FAILED(amountCall);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        borrowAmount = uBalanceAfter - uBalanceBefore;
    }

    /**
     * @dev Internal function to handle repayment to the bank. Returns the actual repaid amount.
     * @param token The token used for the repayment.
     * @param amountCall The specified amount for the repay action.
     * NOTE: The caller should ensure that the bToken's interest is updated up to the current block.
     */
    function _doRepay(address token, uint256 amountCall) internal returns (uint256 repaidAmount) {
        address bToken = _banks[token].bToken;

        IERC20(token).universalApprove(bToken, amountCall);
        uint256 beforeDebt = _borrowBalanceStored(token);

        if (IBErc20(bToken).repayBorrow(amountCall) != 0) {
            revert Errors.REPAY_FAILED(amountCall);
        }

        uint256 newDebt = _borrowBalanceStored(token);
        repaidAmount = beforeDebt - newDebt;
    }

    /**
     * @dev Internal function to handle the transfer of ERC20 tokens into the contract.
     * @param token The ERC20 token to perform transferFrom action.
     * @param amountCall The amount use in the transferFrom call.
     * @return The actual received amount.
     */
    function _doERC20TransferIn(address token, uint256 amountCall) internal returns (uint256) {
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(address(this));
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amountCall);
        uint256 balanceAfter = IERC20Upgradeable(token).balanceOf(address(this));

        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Internal function to handle the transfer of ERC1155 tokens into the contract.
     * @param token The ERC1155 token contract address.
     * @param id The specific token ID to be transferred within the ERC1155 contract.
     * @param amountCall The expected amount of the specific token ID to be transferred.
     * @return The amount of tokens received.
     */
    function _doERC1155TransferIn(address token, uint256 id, uint256 amountCall) internal returns (uint256) {
        uint256 balanceBefore = IERC1155Upgradeable(token).balanceOf(address(this), id);
        IERC1155Upgradeable(token).safeTransferFrom(msg.sender, address(this), id, amountCall, "");
        uint256 balanceAfter = IERC1155Upgradeable(token).balanceOf(address(this), id);

        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Internal function to check if the given vault token is a soft vault or hard vault.
     * @param token The underlying token of the vault to be checked.
     * @return True if it's a Soft Vault, False if it's a Hard Vault.
     */
    function _isSoftVault(address token) internal view returns (bool) {
        return address(ISoftVault(_banks[token].softVault).getUnderlyingToken()) == token;
    }

    /* solhint-disable func-name-mixedcase */
    /// @inheritdoc IBank
    function EXECUTOR() external view returns (address) {
        uint256 positionId = _POSITION_ID;
        if (positionId == _NO_ID) {
            revert Errors.NOT_UNDER_EXECUTION();
        }
        return _positions[positionId].owner;
    }

    /// @inheritdoc IBank
    function POSITION_ID() external view returns (uint256) {
        return _POSITION_ID;
    }

    /// @inheritdoc IBank
    function SPELL() external view returns (address) {
        return _SPELL;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     *      variables without shifting down storage in the inheritance chain.
     *      See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[30] private __gap;
    /* solhint-enable func-name-mixedcase */
}
