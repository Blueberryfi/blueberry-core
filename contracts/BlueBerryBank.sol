// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "./utils/BlueBerryConst.sol";
import "./utils/BlueBerryErrors.sol";
import "./utils/ERC1155NaiveReceiver.sol";
import "./interfaces/IBank.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ISoftVault.sol";
import "./interfaces/IHardVault.sol";
import "./interfaces/compound/ICErc20.sol";
import "./interfaces/compound/IComptroller.sol";
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
    uint256 public override POSITION_ID; // TEMPORARY: position ID currently under execution.
    address public override SPELL; // TEMPORARY: spell currently under execution.

    IProtocolConfig public config;
    IOracle public oracle; // The oracle address for determining prices.
    uint256 public override nextPositionId; // Next available position ID, starting from 1 (see initialize).

    address[] public allBanks; // The list of all listed banks.
    mapping(address => Bank) public banks; // Mapping from token to bank data.
    mapping(address => bool) public cTokenInBank; // Mapping from cToken to its existence in bank.
    mapping(uint256 => Position) public positions; // Mapping from position ID to position data.

    bool public allowContractCalls; // The boolean status whether to allow call from contract (false = onlyEOA)
    mapping(address => bool) public whitelistedTokens; // Mapping from token to whitelist status
    mapping(address => bool) public whitelistedSpells; // Mapping from spell to whitelist status
    mapping(address => bool) public whitelistedContracts; // Mapping from user to whitelist status

    uint256 public bankStatus; // Each bit stores certain bank status, e.g. borrow allowed, repay allowed

    /// @dev Ensure that the function is called from EOA
    /// when allowContractCalls is set to false and caller is not whitelisted
    modifier onlyEOAEx() {
        if (!allowContractCalls && !whitelistedContracts[msg.sender]) {
            if (msg.sender != tx.origin) revert NOT_EOA(msg.sender);
        }
        _;
    }

    /// @dev Ensure that the token is already whitelisted
    modifier onlyWhitelistedToken(address token) {
        if (!whitelistedTokens[token]) revert TOKEN_NOT_WHITELISTED(token);
        _;
    }

    /// @dev Reentrancy lock guard.
    modifier lock() {
        if (_GENERAL_LOCK != _NOT_ENTERED) revert LOCKED();
        _GENERAL_LOCK = _ENTERED;
        _;
        _GENERAL_LOCK = _NOT_ENTERED;
    }

    /// @dev Ensure that the function is called from within the execution scope.
    modifier inExec() {
        if (POSITION_ID == _NO_ID) revert NOT_IN_EXEC();
        if (SPELL != msg.sender) revert NOT_FROM_SPELL(msg.sender);
        if (_IN_EXEC_LOCK != _NOT_ENTERED) revert LOCKED();
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
    /// @param _oracle The oracle smart contract address.
    /// @param _config The Protocol config address
    function initialize(IOracle _oracle, IProtocolConfig _config)
        external
        initializer
    {
        __Ownable_init();
        if (address(_oracle) == address(0) || address(_config) == address(0)) {
            revert ZERO_ADDRESS();
        }
        _GENERAL_LOCK = _NOT_ENTERED;
        _IN_EXEC_LOCK = _NOT_ENTERED;
        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;

        config = _config;
        oracle = _oracle;
        nextPositionId = 1;
        bankStatus = 7; // allow borrow, lend, repay

        emit SetOracle(address(_oracle));
    }

    /// @dev Return the current executor (the owner of the current position).
    function EXECUTOR() external view override returns (address) {
        uint256 positionId = POSITION_ID;
        if (positionId == _NO_ID) {
            revert NOT_UNDER_EXECUTION();
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
            revert INPUT_ARRAY_MISMATCH();
        }
        for (uint256 idx = 0; idx < contracts.length; idx++) {
            if (contracts[idx] == address(0)) {
                revert ZERO_ADDRESS();
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
            revert INPUT_ARRAY_MISMATCH();
        }
        for (uint256 idx = 0; idx < spells.length; idx++) {
            if (spells[idx] == address(0)) {
                revert ZERO_ADDRESS();
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
            revert INPUT_ARRAY_MISMATCH();
        }
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (statuses[idx] && !oracle.support(tokens[idx]))
                revert ORACLE_NOT_SUPPORT(tokens[idx]);
            whitelistedTokens[tokens[idx]] = statuses[idx];
        }
    }

    /**
     * @dev Add a new bank to the ecosystem.
     * @param token The underlying token for the bank.
     * @param cToken The address of the cToken smart contract.
     * @param softVault The address of softVault.
     * @param hardVault The address of hardVault.
     */
    function addBank(
        address token,
        address cToken,
        address softVault,
        address hardVault
    ) external onlyOwner onlyWhitelistedToken(token) {
        if (
            token == address(0) ||
            cToken == address(0) ||
            softVault == address(0) ||
            hardVault == address(0)
        ) revert ZERO_ADDRESS();
        Bank storage bank = banks[token];
        if (cTokenInBank[cToken]) revert CTOKEN_ALREADY_ADDED();
        if (bank.isListed) revert BANK_ALREADY_LISTED();
        if (allBanks.length >= 256) revert BANK_LIMIT();
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

    function enterMarkets(address comp, address[] memory markets)
        external
        onlyOwner
    {
        if (block.chainid == 1) revert ONLY_FOR_DEV();
        IComptroller(comp).enterMarkets(markets);
    }

    /**
     * @dev Update vault address of listed bank
     * @param token The underlying token of the bank
     * @param vault The address of new vault
     */
    function updateVault(
        address token,
        address vault,
        bool isSoft
    ) external onlyOwner {
        if (block.chainid == 1) revert ONLY_FOR_DEV();
        if (vault == address(0)) revert ZERO_ADDRESS();
        Bank storage bank = banks[token];
        if (!bank.isListed) revert BANK_NOT_LISTED(token);
        if (isSoft) {
            bank.softVault = vault;
        } else {
            bank.hardVault = vault;
        }
    }

    /**
     * @dev Update bToken address of listed bank
     * @param token The underlying token of the bank
     * @param cToken The address of new cToken
     */
    function updateCToken(address token, address cToken) external onlyOwner {
        if (block.chainid == 1) revert ONLY_FOR_DEV();
        if (cToken == address(0)) revert ZERO_ADDRESS();
        Bank storage bank = banks[token];
        if (!bank.isListed) revert BANK_NOT_LISTED(token);
        bank.cToken = cToken;
        cTokenInBank[cToken] = true;
    }

    /// @dev Set the oracle smart contract address.
    /// @param _oracle The new oracle smart contract address.
    function setOracle(IOracle _oracle) external onlyOwner {
        if (address(_oracle) == address(0)) revert ZERO_ADDRESS();

        // Check if new oracle supports already added banks
        for (uint256 i = 0; i < allBanks.length; i++) {
            if (!oracle.support(allBanks[i]))
                revert ORACLE_NOT_SUPPORT(allBanks[i]);
        }
        oracle = _oracle;
        emit SetOracle(address(_oracle));
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

    /// @dev Check whether the oracle supports the token
    /// @param token ERC-20 token to check for support
    function support(address token) external view override returns (bool) {
        return oracle.support(token);
    }

    /// @dev Trigger interest accrual for the given bank.
    /// @param token The underlying token to trigger the interest accrual.
    function accrue(address token) public override {
        Bank storage bank = banks[token];
        if (!bank.isListed) revert BANK_NOT_LISTED(token);
        bank.totalDebt = ICErc20(bank.cToken).borrowBalanceCurrent(
            address(this)
        );
    }

    /// @dev Convenient function to trigger interest accrual for a list of banks.
    /// @param tokens The list of banks to trigger interest accrual.
    function accrueAll(address[] memory tokens) external {
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            accrue(tokens[idx]);
        }
    }

    /// @dev Return the borrow balance for given position and token without triggering interest accrual.
    /// @param positionId The position to query for borrow balance.
    /// @param token The token to query for borrow balance.
    function borrowBalanceStored(uint256 positionId, address token)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalDebt = banks[token].totalDebt;
        uint256 totalShare = banks[token].totalShare;
        uint256 share = positions[positionId].debtShareOf[token];
        if (share == 0 || totalDebt == 0) {
            return 0;
        } else {
            return (share * totalDebt).divCeil(totalShare);
        }
    }

    /// @dev Trigger interest accrual and return the current borrow balance.
    /// @param positionId The position to query for borrow balance.
    /// @param token The token to query for borrow balance.
    function borrowBalanceCurrent(uint256 positionId, address token)
        external
        override
        poke(token)
        returns (uint256)
    {
        return borrowBalanceStored(positionId, token);
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
            uint256 totalDebt,
            uint256 totalShare
        )
    {
        Bank storage bank = banks[token];
        return (bank.isListed, bank.cToken, bank.totalDebt, bank.totalShare);
    }

    /// @dev Return position information for the given position id.
    /// @param positionId The position id to query for position information.
    function getPositionInfo(uint256 positionId)
        public
        view
        override
        returns (
            address owner,
            address underlyingToken,
            uint256 underlyingAmount,
            address collToken,
            uint256 collId,
            uint256 collateralSize,
            uint256 risk
        )
    {
        Position storage pos = positions[positionId];
        owner = pos.owner;
        underlyingToken = pos.underlyingToken;
        underlyingAmount = pos.underlyingAmount;
        collToken = pos.collToken;
        collId = pos.collId;
        collateralSize = pos.collateralSize;
        risk = getPositionRisk(positionId);
    }

    /// @dev Return current position information
    function getCurrentPositionInfo()
        external
        view
        override
        returns (
            address owner,
            address underlyingToken,
            uint256 underlyingAmount,
            address collToken,
            uint256 collId,
            uint256 collateralSize,
            uint256 risk
        )
    {
        if (POSITION_ID == _NO_ID) revert BAD_POSITION(POSITION_ID);
        return getPositionInfo(POSITION_ID);
    }

    /// @dev Return the debt share of the given bank token for the given position id.
    /// @param positionId position id to get debt of
    /// @param token ERC20 debt token to query
    function getPositionDebtShareOf(uint256 positionId, address token)
        external
        view
        returns (uint256)
    {
        return positions[positionId].debtShareOf[token];
    }

    /// @dev Return the list of all debts for the given position id.
    /// @param positionId position id to get debts of
    function getPositionDebts(uint256 positionId)
        external
        view
        returns (address[] memory tokens, uint256[] memory debts)
    {
        Position storage pos = positions[positionId];
        uint256 count = 0;
        uint256 bitMap = pos.debtMap;
        while (bitMap > 0) {
            if ((bitMap & 1) != 0) {
                count++;
            }
            bitMap >>= 1;
        }
        tokens = new address[](count);
        debts = new uint256[](count);
        bitMap = pos.debtMap;
        count = 0;
        uint256 idx = 0;
        while (bitMap > 0) {
            if ((bitMap & 1) != 0) {
                address token = allBanks[idx];
                Bank storage bank = banks[token];
                tokens[count] = token;
                debts[count] = (pos.debtShareOf[token] * bank.totalDebt)
                    .divCeil(bank.totalShare);
                count++;
            }
            idx++;
            bitMap >>= 1;
        }
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
            if (pos.collToken == address(0)) revert BAD_COLLATERAL(positionId);
            return oracle.getCollateralValue(pos.collToken, pos.collId, size);
        }
    }

    /// @dev Return the USD value total debt of the given position
    /// @param positionId The position ID to query for the debt value.
    function getDebtValue(uint256 positionId)
        public
        view
        override
        returns (uint256)
    {
        uint256 value = 0;
        Position storage pos = positions[positionId];
        uint256 bitMap = pos.debtMap;
        uint256 idx = 0;
        while (bitMap > 0) {
            if ((bitMap & 1) != 0) {
                address token = allBanks[idx];
                uint256 share = pos.debtShareOf[token];
                Bank storage bank = banks[token];
                uint256 debt = (share * bank.totalDebt).divCeil(
                    bank.totalShare
                );
                value += oracle.getDebtValue(token, debt);
            }
            idx++;
            bitMap >>= 1;
        }
        return value;
    }

    function getPositionRisk(uint256 positionId)
        public
        view
        returns (uint256 risk)
    {
        Position storage pos = positions[positionId];
        uint256 pv = getPositionValue(positionId);
        uint256 ov = getDebtValue(positionId);
        uint256 cv = oracle.getUnderlyingValue(
            pos.underlyingToken,
            pos.underlyingAmount
        );

        if (pv >= ov) risk = 0;
        else {
            risk = ov / (pv + cv);
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
        if (amountCall == 0) revert ZERO_AMOUNT();
        if (!isLiquidatable(positionId)) revert NOT_LIQUIDATABLE(positionId);
        Position storage pos = positions[positionId];
        (uint256 amountPaid, uint256 share) = repayInternal(
            positionId,
            debtToken,
            amountCall
        );
        if (pos.collToken == address(0)) revert BAD_COLLATERAL(positionId);

        uint256 liqSize = oracle.convertForLiquidation(
            debtToken,
            pos.collToken,
            pos.collId,
            amountPaid
        );
        liqSize = MathUpgradeable.min(liqSize, pos.collateralSize);
        pos.collateralSize -= liqSize;
        IERC1155Upgradeable(pos.collToken).safeTransferFrom(
            address(this),
            msg.sender,
            pos.collId,
            liqSize,
            ""
        );
        emit Liquidate(positionId, msg.sender, debtToken, amountPaid, share, 0);
    }

    /// @dev Execute the action via BlueBerryCaster, calling its function with the supplied data.
    /// @param positionId The position ID to execute the action, or zero for new position.
    /// @param spell The target spell to invoke the execution via BlueBerryCaster.
    /// @param data Extra data to pass to the target for the execution.
    function execute(
        uint256 positionId,
        address spell,
        bytes memory data
    ) external payable lock onlyEOAEx returns (uint256) {
        if (!whitelistedSpells[spell]) revert SPELL_NOT_WHITELISTED(spell);
        if (positionId == 0) {
            positionId = nextPositionId++;
            positions[positionId].owner = msg.sender;
        } else {
            if (positionId >= nextPositionId) revert BAD_POSITION(positionId);
            if (msg.sender != positions[positionId].owner)
                revert NOT_FROM_OWNER(positionId, msg.sender);
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

        if (isLiquidatable(positionId)) revert INSUFFICIENT_COLLATERAL();

        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;

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
        if (!isLendAllowed()) revert LEND_NOT_ALLOWED();

        Position storage pos = positions[POSITION_ID];
        Bank storage bank = banks[token];
        if (pos.underlyingToken != address(0)) {
            // already have isolated collateral, allow same isolated collateral
            if (pos.underlyingToken != token)
                revert INCORRECT_UNDERLYING(token);
        }

        IERC20Upgradeable(token).safeTransferFrom(
            pos.owner,
            address(this),
            amount
        );
        amount = doCutDepositFee(token, amount);
        pos.underlyingToken = token;
        pos.underlyingAmount += amount;

        if (address(ISoftVault(bank.softVault).uToken()) == token) {
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

        bank.totalLend += amount;

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
        if (token != pos.underlyingToken) revert INVALID_UTOKEN(token);
        if (shareAmount == type(uint256).max) {
            shareAmount = pos.underlyingVaultShare;
        }

        uint256 wAmount;
        if (address(ISoftVault(bank.softVault).uToken()) == token) {
            ISoftVault(bank.softVault).approve(
                bank.softVault,
                type(uint256).max
            );
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

        wAmount = doCutWithdrawFee(token, wAmount);

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
        if (!isBorrowAllowed()) revert BORROW_NOT_ALLOWED();
        Bank storage bank = banks[token];
        Position storage pos = positions[POSITION_ID];
        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = bank.totalDebt;
        uint256 share = totalShare == 0
            ? amount
            : (amount * totalShare).divCeil(totalDebt);
        bank.totalShare += share;
        uint256 newShare = pos.debtShareOf[token] + share;
        pos.debtShareOf[token] = newShare;
        if (newShare > 0) {
            pos.debtMap |= (1 << uint256(bank.index));
        }
        IERC20Upgradeable(token).safeTransfer(
            msg.sender,
            doBorrow(token, amount)
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
        if (!isRepayAllowed()) revert REPAY_NOT_ALLOWED();
        (uint256 amount, uint256 share) = repayInternal(
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
    function repayInternal(
        uint256 positionId,
        address token,
        uint256 amountCall
    ) internal returns (uint256, uint256) {
        Bank storage bank = banks[token];
        Position storage pos = positions[positionId];
        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = bank.totalDebt;
        uint256 oldShare = pos.debtShareOf[token];
        uint256 oldDebt = (oldShare * totalDebt).divCeil(totalShare);
        if (amountCall == type(uint256).max) {
            amountCall = oldDebt;
        }
        amountCall = doERC20TransferIn(token, amountCall);
        uint256 paid = doRepay(token, amountCall);
        if (paid > oldDebt) revert REPAY_EXCEEDS_DEBT(paid, oldDebt); // prevent share overflow attack
        uint256 lessShare = paid == oldDebt
            ? oldShare
            : (paid * totalShare) / totalDebt;
        bank.totalShare = totalShare - lessShare;
        uint256 newShare = oldShare - lessShare;
        pos.debtShareOf[token] = newShare;
        if (newShare == 0) {
            pos.debtMap &= ~(1 << uint256(bank.index));
        }
        return (paid, lessShare);
    }

    /// @dev Transmit user assets to the caller, so users only need to approve Bank for spending.
    /// @param token The token to transfer from user to the caller.
    /// @param amount The amount to transfer.
    function transmit(address token, uint256 amount) external override inExec {
        Position storage pos = positions[POSITION_ID];
        IERC20Upgradeable(token).safeTransferFrom(
            pos.owner,
            msg.sender,
            amount
        );
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
            if (!oracle.supportWrappedToken(collToken, collId))
                revert ORACLE_NOT_SUPPORT_WTOKEN(collToken);
            if (pos.collateralSize > 0) revert ANOTHER_COL_EXIST(pos.collToken);
            pos.collToken = collToken;
            pos.collId = collId;
        }
        uint256 amount = doERC1155TransferIn(collToken, collId, amountCall);
        pos.collateralSize += amount;
        emit PutCollateral(POSITION_ID, msg.sender, collToken, collId, amount);
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
    function doBorrow(address token, uint256 amountCall)
        internal
        returns (uint256 borrowAmount)
    {
        Bank storage bank = banks[token]; // assume the input is already sanity checked.

        IERC20Upgradeable uToken = IERC20Upgradeable(token);
        uint256 uBalanceBefore = uToken.balanceOf(address(this));
        if (ICErc20(bank.cToken).borrow(amountCall) != 0)
            revert BORROW_FAILED(amountCall);
        uint256 uBalanceAfter = uToken.balanceOf(address(this));

        borrowAmount = uBalanceAfter - uBalanceBefore;
        bank.totalDebt += amountCall;
    }

    /**
     * @dev Internal function to perform repay to the bank and return the amount actually repaid.
     * @param token The token to perform repay action.
     * @param amountCall The amount to use in the repay call.
     * NOTE: Caller must ensure that cToken interest was already accrued up to this block.
     */
    function doRepay(address token, uint256 amountCall)
        internal
        returns (uint256 repaidAmount)
    {
        Bank storage bank = banks[token]; // assume the input is already sanity checked.
        IERC20Upgradeable(token).approve(bank.cToken, amountCall);
        if (ICErc20(bank.cToken).repayBorrow(amountCall) != 0)
            revert REPAY_FAILED(amountCall);
        uint256 newDebt = ICErc20(bank.cToken).borrowBalanceStored(
            address(this)
        );
        repaidAmount = bank.totalDebt - newDebt;
        bank.totalDebt = newDebt;
    }

    function doCutDepositFee(address token, uint256 amount)
        internal
        returns (uint256)
    {
        if (config.treasury() == address(0)) revert NO_TREASURY_SET();
        uint256 fee = (amount * config.depositFee()) / DENOMINATOR;
        IERC20Upgradeable(token).safeTransfer(config.treasury(), fee);
        return amount - fee;
    }

    function doCutWithdrawFee(address token, uint256 amount)
        internal
        returns (uint256)
    {
        if (config.treasury() == address(0)) revert NO_TREASURY_SET();
        uint256 fee = (amount * config.withdrawFee()) / DENOMINATOR;
        IERC20Upgradeable(token).safeTransfer(config.treasury(), fee);
        return amount - fee;
    }

    /// @dev Internal function to perform ERC20 transfer in and return amount actually received.
    /// @param token The token to perform transferFrom action.
    /// @param amountCall The amount use in the transferFrom call.
    function doERC20TransferIn(address token, uint256 amountCall)
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
    function doERC1155TransferIn(
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
}
