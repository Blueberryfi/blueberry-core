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

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./utils/BlueBerryConst.sol" as Constants;
import "./utils/BlueBerryErrors.sol" as Errors;
import "./utils/EnsureApprove.sol";
import "./utils/ERC1155NaiveReceiver.sol";
import "./interfaces/IBank.sol";
import "./interfaces/ICoreOracle.sol";
import "./interfaces/ISoftVault.sol";
import "./interfaces/IHardVault.sol";
import "./interfaces/compound/ICErc20.sol";
import "./libraries/BBMath.sol";

 /// @title BlueberryBank
 /// @author BlueberryProtocol
 /// @notice Blueberry Bank is the main contract that stores user's positions and track the borrowing of tokens
contract BlueBerryBank is
    OwnableUpgradeable,
    ERC1155NaiveReceiver,
    IBank,
    EnsureApprove
{
    using BBMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// Constants for internal usage.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private constant _NO_ID = type(uint256).max;
    address private constant _NO_ADDRESS = address(1);

    /// Temporary variables used across functions.
    uint256 public _GENERAL_LOCK;      // TEMPORARY: re-entrancy lock guard.
    uint256 public _IN_EXEC_LOCK;      // TEMPORARY: exec lock guard.
    uint256 public POSITION_ID;        // TEMPORARY: position ID currently under execution.
    address public SPELL;              // TEMPORARY: spell currently under execution.

    /// Configurations and oracle addresses.
    IProtocolConfig public config;     /// @dev The protocol config address.
    ICoreOracle public oracle;         /// @dev The main oracle address.

    /// State variables for position and bank.
    uint256 public nextPositionId;        /// Next available position ID, starting from 1 (see initialize).
    uint256 public bankStatus;            /// Each bit stores certain bank status, e.g. borrow allowed, repay allowed
    uint256 public repayResumedTimestamp; /// Timestamp that repay is allowed or resumed

    /// Collections of banks and positions.
    address[] public allBanks;                     /// The list of all listed banks.
    mapping(address => Bank) public banks;         /// Mapping from token to bank data.
    mapping(address => bool) public bTokenInBank;  /// Mapping from bToken to its existence in bank.
    mapping(uint256 => Position) public positions; /// Mapping from position ID to position data.

    /// Flags and whitelists
    bool public allowContractCalls; // The boolean status whether to allow call from contract (false = onlyEOA)
    mapping(address => bool) public whitelistedTokens;        /// Mapping from token to whitelist status
    mapping(address => bool) public whitelistedWrappedTokens; /// Mapping from token to whitelist status
    mapping(address => bool) public whitelistedSpells;        /// Mapping from spell to whitelist status
    mapping(address => bool) public whitelistedContracts;     /// Mapping from user to whitelist status

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Ensure that the function is called from EOA
    /// when allowContractCalls is set to false and caller is not whitelisted
    modifier onlyEOAEx() {
        if (!allowContractCalls && !whitelistedContracts[msg.sender]) {
            if (AddressUpgradeable.isContract(msg.sender))
                revert Errors.NOT_EOA(msg.sender);
        }
        _;
    }

    /// @dev Ensure that the token is already whitelisted
    modifier onlyWhitelistedToken(address token) {
        if (!whitelistedTokens[token])
            revert Errors.TOKEN_NOT_WHITELISTED(token);
        _;
    }

    /// @dev Ensure that the wrapped ERC1155 is already whitelisted
    modifier onlyWhitelistedERC1155(address token) {
        if (!whitelistedWrappedTokens[token])
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

    /// @dev Initialize the bank smart contract, using msg.sender as the first governor.
    /// @dev Emits a {SetOracle} event.
    /// @param oracle_ The oracle smart contract address.
    /// @param config_ The Protocol config address
    function initialize(
        ICoreOracle oracle_,
        IProtocolConfig config_
    ) external initializer {
        __Ownable_init();
        if (address(oracle_) == address(0) || address(config_) == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }
        _GENERAL_LOCK = _NOT_ENTERED;
        _IN_EXEC_LOCK = _NOT_ENTERED;
        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;

        config = config_;
        oracle = oracle_;

        nextPositionId = 1;
        bankStatus = 15; // 0x1111: allow borrow, repay, lend, withdrawLend as default

        emit SetOracle(address(oracle_));
    }

    /// @notice Fetches the executor of the current position.
    /// @dev An executor is the owner of the current position.
    /// @return Address of the executor.
    function EXECUTOR() external view override returns (address) {
        uint256 positionId = POSITION_ID;
        if (positionId == _NO_ID) {
            revert Errors.NOT_UNDER_EXECUTION();
        }
        return positions[positionId].owner;
    }

    /// @dev Toggles the allowance of contract calls.
    /// @param ok If true, contract calls are allowed. Otherwise, only EOA calls are allowed.
    function setAllowContractCalls(bool ok) external onlyOwner {
        allowContractCalls = ok;
    }

    /// @dev Sets whitelist statuses for various contracts.
    /// @param contracts List of contract addresses.
    /// @param statuses Corresponding list of whitelist statuses to set.
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

    /// @dev Set the whitelist status for specific spells.
    /// @param spells Array of spell addresses to change their whitelist status.
    /// @param statuses Array of boolean values indicating the desired whitelist status for each spell.
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

    /// @dev Set the whitelist status for specific tokens.
    /// @param tokens Array of token addresses to change their whitelist status.
    /// @param statuses Array of boolean values indicating the desired whitelist status for each token.
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
            emit SetWhitelistToken(tokens[idx], statuses[idx]);
        }
    }

    /// @dev Set the whitelist status for specific wrapped tokens (ERC1155).
    /// @param tokens Array of wrapped token addresses to set their whitelist status.
    /// @param ok Boolean indicating the desired whitelist status for the provided tokens.
    function whitelistERC1155(
        address[] memory tokens,
        bool ok
    ) external onlyOwner {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            address token = tokens[idx];
            if (token == address(0)) revert Errors.ZERO_ADDRESS();
            whitelistedWrappedTokens[token] = ok;
            emit SetWhitelistERC1155(token, ok);
        }
    }

    /// @dev Add a new bank entity with associated vaults.
    /// @dev Emits a {AddBank} event.
    /// @param token Address of the underlying token for the bank.
    /// @param softVault Address of the softVault.
    /// @param hardVault Address of the hardVault.
    /// @param liqThreshold Liquidation threshold.
    function addBank(
        address token,
        address softVault,
        address hardVault,
        uint256 liqThreshold
    ) external onlyOwner onlyWhitelistedToken(token) {
        if (softVault == address(0) || hardVault == address(0))
            revert Errors.ZERO_ADDRESS();
        if (liqThreshold > Constants.DENOMINATOR)
            revert Errors.LIQ_THRESHOLD_TOO_HIGH(liqThreshold);
        if (liqThreshold < Constants.MIN_LIQ_THRESHOLD)
            revert Errors.LIQ_THRESHOLD_TOO_LOW(liqThreshold);

        Bank storage bank = banks[token];
        address bToken = address(ISoftVault(softVault).bToken());

        if (bTokenInBank[bToken]) revert Errors.BTOKEN_ALREADY_ADDED();
        if (bank.isListed) revert Errors.BANK_ALREADY_LISTED();
        if (allBanks.length >= 256) revert Errors.BANK_LIMIT();

        bTokenInBank[bToken] = true;
        bank.isListed = true;
        bank.index = uint8(allBanks.length);
        bank.bToken = bToken;
        bank.softVault = softVault;
        bank.hardVault = hardVault;
        bank.liqThreshold = liqThreshold;

        IHardVault(hardVault).setApprovalForAll(hardVault, true);
        allBanks.push(token);

        emit AddBank(token, bToken, softVault, hardVault);
    }

    /// @dev Update the bank's operational status flags.
    /// @param _bankStatus The new status flags for the bank.
    function setBankStatus(uint256 _bankStatus) external onlyOwner {
        bool repayAllowedStatusBefore = isRepayAllowed();
        bankStatus = _bankStatus;
        bool repayAllowedStatusAfter = isRepayAllowed();

        /// If the repayAllowed status changes from "off" to "on", update the timestamp.
        if (!repayAllowedStatusBefore && repayAllowedStatusAfter) {
            repayResumedTimestamp = block.timestamp;
        }
    }

    /// @dev Determine if borrowing is currently allowed based on the bank's status flags.
    /// @notice Check the last bit of bankStatus.
    /// @return A boolean indicating whether borrowing is permitted.
    function isBorrowAllowed() public view returns (bool) {
        return (bankStatus & 0x01) > 0;
    }

    /// @dev Determine if repayments are currently allowed based on the bank's status flags.
    /// @notice Check the second-to-last bit of bankStatus.
    /// @return A boolean indicating whether repayments are permitted.
    function isRepayAllowed() public view returns (bool) {
        return (bankStatus & 0x02) > 0;
    }

    /// @dev Determine if lending is currently allowed based on the bank's status flags.
    /// @notice Check the third-to-last bit of bankStatus.
    /// @return A boolean indicating whether lending is permitted.
    function isLendAllowed() public view returns (bool) {
        return (bankStatus & 0x04) > 0;
    }

    /// @dev Determine if withdrawing from lending is currently allowed based on the bank's status flags.
    /// @notice Check the fourth-to-last bit of bankStatus.
    /// @return A boolean indicating whether withdrawing from lending is permitted.
    function isWithdrawLendAllowed() public view returns (bool) {
        return (bankStatus & 0x08) > 0;
    }

    /// @dev Get the current FeeManager interface from the configuration.
    /// @return An interface representing the current FeeManager.
    function feeManager() public view returns (IFeeManager) {
        return config.feeManager();
    }

    /// @dev Trigger interest accrual for a specific bank.
    /// @param token The address of the underlying token to trigger the interest accrual.
    function accrue(address token) public override {
        Bank storage bank = banks[token];
        if (!bank.isListed) revert Errors.BANK_NOT_LISTED(token);
        ICErc20(bank.bToken).borrowBalanceCurrent(address(this));
    }

    /// @dev Convenient function to trigger interest accrual for multiple banks.
    /// @param tokens An array of token addresses to trigger interest accrual for.
    function accrueAll(address[] memory tokens) external {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            accrue(tokens[idx]);
        }
    }

    /// @dev Internal function to return the current borrow balance of the given token.
    /// @param token The token address to query for borrow balance.
    function _borrowBalanceStored(
        address token
    ) internal view returns (uint256) {
        return ICErc20(banks[token].bToken).borrowBalanceStored(address(this));
    }

    /// @dev Trigger interest accrual and return the current debt balance for a specific position.
    /// @param positionId The ID of the position to query for the debt balance.
    /// The current debt balance for the specified position.
    function currentPositionDebt(
        uint256 positionId
    )
        external
        override
        poke(positions[positionId].debtToken)
        returns (uint256)
    {
        return getPositionDebt(positionId);
    }

    /// @notice Retrieve the debt of a given position, considering the stored debt interest.
    /// @dev Should call accrue first to obtain the current debt.
    /// @param positionId The ID of the position to query.
    function getPositionDebt(
        uint256 positionId
    ) public view returns (uint256 debt) {
        Position memory pos = positions[positionId];
        Bank memory bank = banks[pos.debtToken];
        if (pos.debtShare == 0 || bank.totalShare == 0) {
            return 0;
        }
        debt = (pos.debtShare * _borrowBalanceStored(pos.debtToken)).divCeil(
            bank.totalShare
        );
    }

    /// @dev Retrieve information about a specific bank.
    /// @param token The token address to query for bank information.
    /// @return isListed Whether the bank is listed or not.
    /// @return bToken The address of the bToken associated with the bank.
    /// @return totalShare The total shares in the bank.
    function getBankInfo(
        address token
    )
        external
        view
        override
        returns (bool isListed, address bToken, uint256 totalShare)
    {
        Bank memory bank = banks[token];
        return (bank.isListed, bank.bToken, bank.totalShare);
    }

    /// @dev Fetches details about a specific position using its ID.
    /// @param positionId Unique identifier of the position.
    /// @return Position object containing all details about the position.
    function getPositionInfo(
        uint256 positionId
    ) external view override returns (Position memory) {
        return positions[positionId];
    }

    /// @dev Fetches details about the current active position.
    /// @notice This function assumes the presence of an active position and will revert if there's none.
    /// @return Position object containing all details about the current position.
    function getCurrentPositionInfo()
        external
        view
        override
        returns (Position memory)
    {
        if (POSITION_ID == _NO_ID) revert Errors.BAD_POSITION(POSITION_ID);
        return positions[POSITION_ID];
    }

    /// @dev Computes the total USD value of the collateral of a given position.
    /// @notice The returned value includes both the collateral and any pending rewards.
    /// @param positionId ID of the position to compute the value for.
    /// @return positionValue Total USD value of the collateral and pending rewards.
    function getPositionValue(
        uint256 positionId
    ) public override returns (uint256 positionValue) {
        Position memory pos = positions[positionId];
        if (pos.collateralSize == 0) {
            return 0;
        } else {
            if (pos.collToken == address(0))
                revert Errors.BAD_COLLATERAL(positionId);
            uint256 collValue = oracle.getWrappedTokenValue(
                pos.collToken,
                pos.collId,
                pos.collateralSize
            );

            uint rewardsValue;
            (address[] memory tokens, uint256[] memory rewards) = IERC20Wrapper(
                pos.collToken
            ).pendingRewards(pos.collId, pos.collateralSize);
            for (uint256 i; i < tokens.length; i++) {
                if (oracle.isTokenSupported(tokens[i])) {
                    rewardsValue += oracle.getTokenValue(tokens[i], rewards[i]);
                }
            }

            return collValue + rewardsValue;
        }
    }

    /// @dev Computes the total USD value of the debt of a given position.
    /// @notice Ensure to call `accrue` beforehand to account for any interest changes.
    /// @param positionId ID of the position to compute the debt value for.
    /// @return debtValue Total USD value of the position's debt.
    function getDebtValue(
        uint256 positionId
    ) public override returns (uint256 debtValue) {
        Position memory pos = positions[positionId];
        uint256 debt = getPositionDebt(positionId);
        debtValue = oracle.getTokenValue(pos.debtToken, debt);
    }

    /// @dev Computes the USD value of the isolated collateral for a given position.
    /// @notice Ensure to call `accrue` beforehand to get the most recent value.
    /// @param positionId ID of the position to compute the isolated collateral value for.
    /// @return icollValue USD value of the isolated collateral.
    function getIsolatedCollateralValue(
        uint256 positionId
    ) public override returns (uint256 icollValue) {
        Position memory pos = positions[positionId];
        /// NOTE: exchangeRateStored has 18 decimals.
        uint256 underlyingAmount;
        if (_isSoftVault(pos.underlyingToken)) {
            underlyingAmount =
                (ICErc20(banks[pos.debtToken].bToken).exchangeRateStored() *
                    pos.underlyingVaultShare) /
                Constants.PRICE_PRECISION;
        } else {
            underlyingAmount = pos.underlyingVaultShare;
        }
        icollValue = oracle.getTokenValue(
            pos.underlyingToken,
            underlyingAmount
        );
    }

    /// @dev Computes the risk ratio of a specified position.
    /// @notice A higher risk ratio implies greater risk associated with the position.
    ///         when:  riskRatio = (ov - pv) / cv
    ///         where: riskRatio = (debt - positionValue) / isolatedCollateralValue
    /// @param positionId ID of the position to assess risk for.
    /// @return risk The risk ratio of the position (based on a scale of 1e4).
    function getPositionRisk(uint256 positionId) public returns (uint256 risk) {
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

    /// @dev Determines if a given position can be liquidated based on its risk ratio.
    /// @param positionId ID of the position to check.
    /// @return True if the position can be liquidated; otherwise, false.
    function isLiquidatable(uint256 positionId) public returns (bool) {
        return
            getPositionRisk(positionId) >=
            banks[positions[positionId].underlyingToken].liqThreshold;
    }

    /// @dev Liquidates a position by repaying its debt and taking the collateral.
    /// @dev Emits a {Liquidate} event.
    /// @notice Liquidation can only be triggered if the position is deemed liquidatable 
    ///         and other conditions are met.
    /// @param positionId The unique identifier of the position to liquidate.
    /// @param debtToken The token in which the debt is denominated.
    /// @param amountCall The amount of debt to be repaid when calling transferFrom.
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
        if (!isLiquidatable(positionId))
            revert Errors.NOT_LIQUIDATABLE(positionId);

        /// Retrieve the position and associated bank data.
        Position storage pos = positions[positionId];
        Bank memory bank = banks[pos.underlyingToken];
        /// Ensure the position has valid collateral.
        if (pos.collToken == address(0))
            revert Errors.BAD_COLLATERAL(positionId);

        /// Revert liquidation if the repayment hasn't been warmed up 
        /// following the last state where repayments were paused.
        if (
            block.timestamp <
            repayResumedTimestamp + Constants.LIQUIDATION_REPAY_WARM_UP_PERIOD
        ) revert Errors.REPAY_ALLOW_NOT_WARMED_UP();

        /// Repay the debt and get details of repayment.
        uint256 oldShare = pos.debtShare;
        (uint256 amountPaid, uint256 share) = _repay(
            positionId,
            debtToken,
            amountCall
        );

        /// Calculate the size of collateral and underlying vault share that the liquidator will get.
        uint256 liqSize = (pos.collateralSize * share) / oldShare;
        uint256 uVaultShare = (pos.underlyingVaultShare * share) / oldShare;

        /// Adjust the position's debt and collateral after liquidation.
        pos.collateralSize -= liqSize;
        pos.underlyingVaultShare -= uVaultShare;

        /// Transfer the liquidated collateral (Wrapped LP Tokens) to the liquidator.
        IERC1155Upgradeable(pos.collToken).safeTransferFrom(
            address(this),
            msg.sender,
            pos.collId,
            liqSize,
            ""
        );
        /// Transfer underlying collaterals(vault share tokens) to liquidator
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

        /// Emit an event capturing details of the liquidation process.
        emit Liquidate(
            positionId,
            msg.sender,
            debtToken,
            amountPaid,
            share,
            liqSize,
            uVaultShare
        );
    }

    /// @dev Executes a specific action on a position.
    /// @dev Emit an {Execute} event.
    /// @notice This can be used for various operations like adjusting collateral, repaying debt, etc.
    /// @param positionId Unique identifier of the position, or zero for a new position.
    /// @param spell Address of the contract ("spell") that contains the logic for the action to be executed.
    /// @param data Data payload to pass to the spell for execution.
    function execute(
        uint256 positionId,
        address spell,
        bytes memory data
    ) external lock onlyEOAEx returns (uint256) {
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

        (bool ok, bytes memory returndata) = SPELL.call(data);
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

    /// @dev Lend tokens to the bank as isolated collateral.
    /// @dev Emit a {Lend} event.
    /// @notice The tokens lent will be used as collateral in the bank and might earn interest or other rewards.
    /// @param token The address of the token to lend.
    /// @param amount The number of tokens to lend.
    function lend(
        address token,
        uint256 amount
    ) external override inExec poke(token) onlyWhitelistedToken(token) {
        if (!isLendAllowed()) revert Errors.LEND_NOT_ALLOWED();

        Position storage pos = positions[POSITION_ID];
        Bank storage bank = banks[token];
        if (pos.underlyingToken != address(0)) {
            /// already have isolated collateral, allow same isolated collateral
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
        _ensureApprove(token, address(feeManager()), amount);
        amount = feeManager().doCutDepositFee(token, amount);

        if (_isSoftVault(token)) {
            _ensureApprove(token, bank.softVault, amount);
            pos.underlyingVaultShare += ISoftVault(bank.softVault).deposit(
                amount
            );
        } else {
            _ensureApprove(token, bank.hardVault, amount);
            pos.underlyingVaultShare += IHardVault(bank.hardVault).deposit(
                token,
                amount
            );
        }

        emit Lend(POSITION_ID, msg.sender, token, amount);
    }

    /// @dev Withdraw isolated collateral tokens previously lent to the bank.
    /// @dev Emit a {WithdrawLend} event.
    /// @notice This will reduce the isolated collateral and might also reduce the position's overall health.
    /// @param token The address of the isolated collateral token to withdraw.
    /// @param shareAmount The number of vault share tokens to withdraw.
    function withdrawLend(
        address token,
        uint256 shareAmount
    ) external override inExec poke(token) {
        if (!isWithdrawLendAllowed()) revert Errors.WITHDRAW_LEND_NOT_ALLOWED();
        Position storage pos = positions[POSITION_ID];
        Bank memory bank = banks[token];
        if (token != pos.underlyingToken) revert Errors.INVALID_UTOKEN(token);
        if (shareAmount == type(uint256).max) {
            shareAmount = pos.underlyingVaultShare;
        }

        uint256 wAmount;
        if (_isSoftVault(token)) {
            _ensureApprove(bank.softVault, bank.softVault, shareAmount);
            wAmount = ISoftVault(bank.softVault).withdraw(shareAmount);
        } else {
            wAmount = IHardVault(bank.hardVault).withdraw(token, shareAmount);
        }

        pos.underlyingVaultShare -= shareAmount;

        _ensureApprove(token, address(feeManager()), wAmount);
        wAmount = feeManager().doCutWithdrawFee(token, wAmount);

        IERC20Upgradeable(token).safeTransfer(msg.sender, wAmount);

        emit WithdrawLend(POSITION_ID, msg.sender, token, wAmount);
    }

    /// @notice Allows users to borrow tokens from the specified bank.
    /// @dev This function must only be called from a spell while under execution.
    /// @dev Emit a {Borrow} event.
    /// @param token The token to borrow from the bank.
    /// @param amount The amount of tokens the user wishes to borrow.
    /// @return borrowedAmount Returns the actual amount borrowed from the bank.
    function borrow(
        address token,
        uint256 amount
    )
        external
        override
        inExec
        poke(token)
        onlyWhitelistedToken(token)
        returns (uint256 borrowedAmount)
    {
        if (!isBorrowAllowed()) revert Errors.BORROW_NOT_ALLOWED();
        Bank storage bank = banks[token];
        Position storage pos = positions[POSITION_ID];
        if (pos.debtToken != address(0)) {
            /// already have some debts, allow same debt token
            if (pos.debtToken != token) revert Errors.INCORRECT_DEBT(token);
        } else {
            pos.debtToken = token;
        }

        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = _borrowBalanceStored(token);
        uint256 share = totalShare == 0
            ? amount
            : (amount * totalShare).divCeil(totalDebt);
        if (share == 0) revert Errors.BORROW_ZERO_SHARE(amount);
        bank.totalShare += share;
        pos.debtShare += share;

        borrowedAmount = _doBorrow(token, amount);
        IERC20Upgradeable(token).safeTransfer(msg.sender, borrowedAmount);

        emit Borrow(POSITION_ID, msg.sender, token, amount, share);
    }

    /// @notice Allows users to repay their borrowed tokens to the bank.
    /// @dev This function must only be called while under execution.
    /// @dev Emit a {Repay} event.
    /// @param token The token to repay to the bank.
    /// @param amountCall The amount of tokens to be repaid.
    function repay(
        address token,
        uint256 amountCall
    ) external override inExec poke(token) onlyWhitelistedToken(token) {
        if (!isRepayAllowed()) revert Errors.REPAY_NOT_ALLOWED();
        (uint256 amount, uint256 share) = _repay(
            POSITION_ID,
            token,
            amountCall
        );
        emit Repay(POSITION_ID, msg.sender, token, amount, share);
    }

    /// @notice Internal function that handles the logic for repaying tokens.
    /// @param positionId The position ID which determines the debt to be repaid.
    /// @param token The bank token used to repay the debt.
    /// @param amountCall The amount specified by the caller to repay by calling `transferFrom`, or -1 for debt size.
    /// @return Returns the actual repaid amount and the reduced debt share.
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
        if (amountCall > oldDebt) {
            amountCall = oldDebt;
        }
        amountCall = _doERC20TransferIn(token, amountCall);
        uint256 paid = _doRepay(token, amountCall);
        if (paid > oldDebt) revert Errors.REPAY_EXCEEDS_DEBT(paid, oldDebt); /// prevent share overflow attack
        uint256 lessShare = paid == oldDebt
            ? oldShare
            : (paid * totalShare) / totalDebt;
        bank.totalShare -= lessShare;
        pos.debtShare -= lessShare;
        return (paid, lessShare);
    }

    /// @notice Allows users to provide additional collateral.
    /// @dev Must only be called during execution.
    /// @param collToken The ERC1155 token wrapped for collateral (i.e., Wrapped token of LP).
    /// @param collId The token ID for collateral (i.e., uint256 format of LP address).
    /// @param amountCall The amount of tokens to add as collateral.
    function putCollateral(
        address collToken,
        uint256 collId,
        uint256 amountCall
    ) external override inExec onlyWhitelistedERC1155(collToken) {
        Position storage pos = positions[POSITION_ID];
        if (pos.collToken != collToken || pos.collId != collId) {
            if (!oracle.isWrappedTokenSupported(collToken, collId))
                revert Errors.ORACLE_NOT_SUPPORT_WTOKEN(collToken);
            if (pos.collateralSize > 0)
                revert Errors.DIFF_COL_EXIST(pos.collToken);
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

    /// @notice Allows users to withdraw a portion of their collateral.
    /// @dev Must only be called during execution.
    /// @param amount The amount of tokens to be withdrawn as collateral.
    /// @return Returns the amount of collateral withdrawn.
    function takeCollateral(
        uint256 amount
    ) external override inExec returns (uint256) {
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

    /// @notice Internal function that handles the borrowing logic.
    /// @dev Borrows the specified amount of tokens and returns the actual borrowed amount.
    /// NOTE: Caller must ensure that bToken interest was already accrued up to this block.
    /// @param token The token to borrow.
    /// @param amountCall The amount of tokens to be borrowed.
    /// @return borrowAmount The actual amount borrowed.
    function _doBorrow(
        address token,
        uint256 amountCall
    ) internal returns (uint256 borrowAmount) {
        address bToken = banks[token].bToken;

        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        if (ICErc20(bToken).borrow(amountCall) != 0)
            revert Errors.BORROW_FAILED(amountCall);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        borrowAmount = uBalanceAfter - uBalanceBefore;
    }

    /// @dev Internal function to handle repayment to the bank. Returns the actual repaid amount.
    /// @param token The token used for the repayment.
    /// @param amountCall The specified amount for the repay action.
    /// NOTE: The caller should ensure that the bToken's interest is updated up to the current block.
    function _doRepay(
        address token,
        uint256 amountCall
    ) internal returns (uint256 repaidAmount) {
        address bToken = banks[token].bToken;
        _ensureApprove(token, bToken, amountCall);
        uint256 beforeDebt = _borrowBalanceStored(token);
        if (ICErc20(bToken).repayBorrow(amountCall) != 0)
            revert Errors.REPAY_FAILED(amountCall);
        uint256 newDebt = _borrowBalanceStored(token);
        repaidAmount = beforeDebt - newDebt;
    }

    /// @dev Internal function to handle the transfer of ERC20 tokens into the contract. 
    /// @param token The ERC20 token to perform transferFrom action.
    /// @param amountCall The amount use in the transferFrom call.
    /// @return The actual recieved amount.
    function _doERC20TransferIn(
        address token,
        uint256 amountCall
    ) internal returns (uint256) {
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

    /// @dev Internal function to handle the transfer of ERC1155 tokens into the contract.
    /// @param token The ERC1155 token contract address.
    /// @param id The specific token ID to be transferred within the ERC1155 contract.
    /// @param amountCall The expected amount of the specific token ID to be transferred.
    /// @return The amount of tokens received.
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

    /// @dev Return if the given vault token is soft vault or hard vault
    /// @param token The underlying token of the vault to be checked.
    /// @return bool True if it's a Soft Vault, False if it's a Hard Vault.
    function _isSoftVault(address token) internal view returns (bool) {
        return address(ISoftVault(banks[token].softVault).uToken()) == token;
    }
}
