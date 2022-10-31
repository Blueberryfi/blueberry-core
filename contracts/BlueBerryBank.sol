// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';

import './Governable.sol';
import './utils/ERC1155NaiveReceiver.sol';
import './interfaces/IBank.sol';
import './interfaces/IOracle.sol';
import './interfaces/ISafeBox.sol';
import './interfaces/compound/ICErc20.sol';

library BlueBerrySafeMath {
    /// @dev Computes round-up division.
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }
}

contract BlueBerryBank is Governable, ERC1155NaiveReceiver, IBank {
    using BlueBerrySafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private constant _NO_ID = type(uint256).max;
    address private constant _NO_ADDRESS = address(1);

    struct Bank {
        bool isListed; // Whether this market exists.
        uint8 index; // Reverse look up index for this bank.
        address cToken; // The CToken to draw liquidity from.
        address safeBox;
        uint256 reserve; // The reserve portion allocated to BlueBerry protocol.
        uint256 totalDebt; // The last recorded total debt since last action.
        uint256 totalShare; // The total debt share count across all open positions.
        uint256 totalLend; // The total lent amount
    }

    struct Position {
        address owner; // The owner of this position.
        address collToken; // The ERC1155 token used as collateral for this position.
        address underlyingToken;
        uint256 underlyingAmount;
        uint256 underlyingcTokenAmount;
        uint256 collId; // The token id used as collateral.
        uint256 collateralSize; // The size of collateral token for this position.
        uint256 debtMap; // Bitmap of nonzero debt. i^th bit is set iff debt share of i^th bank is nonzero.
        mapping(address => uint256) debtShareOf; // The debt share for each token.
    }

    uint256 public _GENERAL_LOCK; // TEMPORARY: re-entrancy lock guard.
    uint256 public _IN_EXEC_LOCK; // TEMPORARY: exec lock guard.
    uint256 public override POSITION_ID; // TEMPORARY: position ID currently under execution.
    address public override SPELL; // TEMPORARY: spell currently under execution.

    IOracle public oracle; // The oracle address for determining prices.
    uint256 public feeBps; // The fee collected as protocol reserve in basis points from interest.
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
            require(msg.sender == tx.origin, 'not eoa');
        }
        _;
    }

    /// @dev Reentrancy lock guard.
    modifier lock() {
        require(_GENERAL_LOCK == _NOT_ENTERED, 'general lock');
        _GENERAL_LOCK = _ENTERED;
        _;
        _GENERAL_LOCK = _NOT_ENTERED;
    }

    /// @dev Ensure that the function is called from within the execution scope.
    modifier inExec() {
        require(POSITION_ID != _NO_ID, 'not within execution');
        require(SPELL == msg.sender, 'not from spell');
        require(_IN_EXEC_LOCK == _NOT_ENTERED, 'in exec lock');
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
    /// @param _feeBps The fee collected to BlueBerry bank.
    function initialize(IOracle _oracle, uint256 _feeBps) external {
        __Governable__init();
        _GENERAL_LOCK = _NOT_ENTERED;
        _IN_EXEC_LOCK = _NOT_ENTERED;
        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;
        oracle = _oracle;
        require(address(_oracle) != address(0), 'bad oracle address');
        feeBps = _feeBps;
        nextPositionId = 1;
        bankStatus = 7; // allow borrow, lend, repay
        emit SetOracle(address(_oracle));
        emit SetFeeBps(_feeBps);
    }

    /// @dev Return the current executor (the owner of the current position).
    function EXECUTOR() external view override returns (address) {
        uint256 positionId = POSITION_ID;
        require(positionId != _NO_ID, 'not under execution');
        return positions[positionId].owner;
    }

    /// @dev Set allowContractCalls
    /// @param ok The status to set allowContractCalls to (false = onlyEOA)
    function setAllowContractCalls(bool ok) external onlyGov {
        allowContractCalls = ok;
    }

    /// @dev Set whitelist spell status
    /// @param spells list of spells to change status
    /// @param statuses list of statuses to change to
    function setWhitelistSpells(
        address[] calldata spells,
        bool[] calldata statuses
    ) external onlyGov {
        require(
            spells.length == statuses.length,
            'spells & statuses length mismatched'
        );
        for (uint256 idx = 0; idx < spells.length; idx++) {
            whitelistedSpells[spells[idx]] = statuses[idx];
        }
    }

    /// @dev Set whitelist token status
    /// @param tokens list of tokens to change status
    /// @param statuses list of statuses to change to
    function setWhitelistTokens(
        address[] calldata tokens,
        bool[] calldata statuses
    ) external onlyGov {
        require(
            tokens.length == statuses.length,
            'tokens & statuses length mismatched'
        );
        for (uint256 idx = 0; idx < tokens.length; idx++) {
            if (statuses[idx]) {
                // check oracle suppport
                require(support(tokens[idx]), 'oracle not support token');
            }
            whitelistedTokens[tokens[idx]] = statuses[idx];
        }
    }

    /// @dev Set whitelist user status
    /// @param users list of users to change status
    /// @param statuses list of statuses to change to
    function whitelistContracts(
        address[] calldata users,
        bool[] calldata statuses
    ) external onlyGov {
        require(
            users.length == statuses.length,
            'users & statuses length mismatched'
        );
        for (uint256 idx = 0; idx < users.length; idx++) {
            whitelistedContracts[users[idx]] = statuses[idx];
        }
    }

    /// @dev Check whether the oracle supports the token
    /// @param token ERC-20 token to check for support
    function support(address token) public view override returns (bool) {
        return oracle.support(token);
    }

    /// @dev Set bank status
    /// @param _bankStatus new bank status to change to
    function setBankStatus(uint256 _bankStatus) external onlyGov {
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
        require(bank.isListed, 'bank not exist');
        uint256 totalDebt = bank.totalDebt;
        uint256 debt = ICErc20(bank.cToken).borrowBalanceCurrent(bank.safeBox);
        if (debt > totalDebt) {
            uint256 fee = ((debt - totalDebt) * feeBps) / 10000;
            bank.totalDebt = debt;
            bank.reserve += doBorrow(token, fee);
        } else if (totalDebt != debt) {
            bank.totalDebt = debt;
        }
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
            return (share * totalDebt).ceilDiv(totalShare);
        }
    }

    /// @dev Trigger interest accrual and return the current borrow balance.
    /// @param positionId The position to query for borrow balance.
    /// @param token The token to query for borrow balance.
    function borrowBalanceCurrent(uint256 positionId, address token)
        external
        override
        returns (uint256)
    {
        accrue(token);
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
            uint256 reserve,
            uint256 totalDebt,
            uint256 totalShare
        )
    {
        Bank storage bank = banks[token];
        return (
            bank.isListed,
            bank.cToken,
            bank.reserve,
            bank.totalDebt,
            bank.totalShare
        );
    }

    /// @dev Return position information for the given position id.
    /// @param positionId The position id to query for position information.
    function getPositionInfo(uint256 positionId)
        public
        view
        override
        returns (
            address owner,
            address collToken,
            uint256 collId,
            uint256 collateralSize,
            uint256 risk
        )
    {
        Position storage pos = positions[positionId];
        return (
            pos.owner,
            pos.collToken,
            pos.collId,
            pos.collateralSize,
            getPositionRisk(positionId)
        );
    }

    /// @dev Return current position information
    function getCurrentPositionInfo()
        external
        view
        override
        returns (
            address owner,
            address collToken,
            uint256 collId,
            uint256 collateralSize,
            uint256 risk
        )
    {
        require(POSITION_ID != _NO_ID, 'no id');
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
                    .ceilDiv(bank.totalShare);
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
    function getCollateralValue(uint256 positionId)
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
            require(pos.collToken != address(0), 'bad collateral token');
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
                uint256 debt = (share * bank.totalDebt).ceilDiv(
                    bank.totalShare
                );
                value += oracle.getDebtValue(token, debt);
            }
            idx++;
            bitMap >>= 1;
        }
        return value;
    }

    /**
     * @dev Add a new bank to the ecosystem.
     * @param token The underlying token for the bank.
     * @param cToken The address of the cToken smart contract.
     * @param safeBox The address of safeBox.
     */
    function addBank(
        address token,
        address cToken,
        address safeBox
    ) external onlyGov {
        Bank storage bank = banks[token];
        require(!cTokenInBank[cToken], 'cToken already exists');
        require(!bank.isListed, 'bank already exists');
        cTokenInBank[cToken] = true;
        bank.isListed = true;
        require(allBanks.length < 256, 'reach bank limit');
        bank.index = uint8(allBanks.length);
        bank.cToken = cToken;
        bank.safeBox = safeBox;
        IERC20(token).safeApprove(cToken, 0);
        IERC20(token).safeApprove(cToken, type(uint256).max);
        allBanks.push(token);
        emit AddBank(token, cToken);
    }

    /**
     * @dev Update safeBox address of listed bank
     * @param token The underlying token of the bank
     * @param safeBox The address of new SafeBox
     */
    function updateSafeBox(address token, address safeBox) external onlyGov {
        Bank storage bank = banks[token];
        require(bank.isListed, 'bank is not listed');
        bank.safeBox = safeBox;
    }

    /// @dev Set the oracle smart contract address.
    /// @param _oracle The new oracle smart contract address.
    function setOracle(IOracle _oracle) external onlyGov {
        require(
            address(_oracle) != address(0),
            'cannot set zero address oracle'
        );
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    /// @dev Set the fee bps value that BlueBerry bank charges.
    /// @param _feeBps The new fee bps value.
    function setFeeBps(uint256 _feeBps) external onlyGov {
        require(_feeBps <= 10000, 'fee too high');
        feeBps = _feeBps;
        emit SetFeeBps(_feeBps);
    }

    /// @dev Withdraw the reserve portion of the bank.
    /// @param amount The amount of tokens to withdraw.
    function withdrawReserve(address token, uint256 amount)
        external
        onlyGov
        lock
    {
        Bank storage bank = banks[token];
        require(bank.isListed, 'bank not exist');
        bank.reserve -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit WithdrawReserve(msg.sender, token, amount);
    }

    function getPositionRisk(uint256 positionId)
        public
        view
        returns (uint256 risk)
    {
        Position storage pos = positions[positionId];
        uint256 pv = getCollateralValue(positionId);
        uint256 ov = getDebtValue(positionId);
        uint256 cv = oracle.getUnderlyingValue(
            pos.underlyingToken,
            pos.underlyingAmount
        );

        if (pv >= ov) risk = 0;
        else {
            risk = ((ov - pv) * 10000) / cv;
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
        require(isLiquidatable(positionId), 'position still healthy');
        Position storage pos = positions[positionId];
        (uint256 amountPaid, uint256 share) = repayInternal(
            positionId,
            debtToken,
            amountCall
        );
        require(pos.collToken != address(0), 'bad collateral token');
        IERC1155(pos.collToken).safeTransferFrom(
            address(this),
            msg.sender,
            pos.collId,
            0,
            ''
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
        require(whitelistedSpells[spell], 'spell not whitelisted');
        if (positionId == 0) {
            positionId = nextPositionId++;
            positions[positionId].owner = msg.sender;
        } else {
            require(positionId < nextPositionId, 'position id not exists');
            require(
                msg.sender == positions[positionId].owner,
                'not position owner'
            );
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
                revert('bad cast call');
            }
        }

        require(!isLiquidatable(positionId), 'insufficient collateral');

        POSITION_ID = _NO_ID;
        SPELL = _NO_ADDRESS;

        return positionId;
    }

    /**
     * @dev Lend tokens to bank. Must only be called while under execution.
     * @param token The token to deposit on bank as isolated collateral
     * @param amount The amount of tokens to lend.
     */
    function lend(address token, uint256 amount)
        external
        override
        inExec
        poke(token)
    {
        require(isLendAllowed(), 'lending not allowed');
        require(whitelistedTokens[token], 'token not whitelisted');

        Position storage pos = positions[POSITION_ID];
        Bank storage bank = banks[token];
        pos.underlyingToken = token;
        pos.underlyingAmount += amount;

        IERC20(token).safeTransferFrom(pos.owner, address(this), amount);
        IERC20(token).approve(bank.safeBox, amount);

        pos.underlyingcTokenAmount += ISafeBox(bank.safeBox).lend(amount);
        bank.totalLend += amount;

        emit Lend(POSITION_ID, msg.sender, token, amount);
    }

    function withdrawLend(address token, uint256 amount)
        external
        override
        inExec
        poke(token)
    {
        Position storage pos = positions[POSITION_ID];
        Bank storage bank = banks[token];
        if (amount == type(uint256).max) {
            amount = pos.underlyingcTokenAmount;
        }

        ISafeBox(bank.safeBox).approve(bank.safeBox, type(uint256).max);
        uint256 wAmount = ISafeBox(bank.safeBox).withdraw(amount);

        wAmount = wAmount > pos.underlyingAmount
            ? pos.underlyingAmount
            : wAmount;

        pos.underlyingcTokenAmount -= amount;
        pos.underlyingAmount -= wAmount;
        bank.totalLend -= wAmount;

        IERC20(token).safeTransfer(msg.sender, wAmount);
    }

    /// @dev Borrow tokens from that bank. Must only be called while under execution.
    /// @param token The token to borrow from the bank.
    /// @param amount The amount of tokens to borrow.
    function borrow(address token, uint256 amount)
        external
        override
        inExec
        poke(token)
    {
        require(isBorrowAllowed(), 'borrow not allowed');
        require(whitelistedTokens[token], 'token not whitelisted');
        Bank storage bank = banks[token];
        Position storage pos = positions[POSITION_ID];
        uint256 totalShare = bank.totalShare;
        uint256 totalDebt = bank.totalDebt;
        uint256 share = totalShare == 0
            ? amount
            : (amount * totalShare).ceilDiv(totalDebt);
        bank.totalShare += share;
        uint256 newShare = pos.debtShareOf[token] + share;
        pos.debtShareOf[token] = newShare;
        if (newShare > 0) {
            pos.debtMap |= (1 << uint256(bank.index));
        }
        IERC20(token).safeTransfer(msg.sender, doBorrow(token, amount));
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
    {
        require(isRepayAllowed(), 'repay not allowed');
        require(whitelistedTokens[token], 'token not whitelisted');
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
        uint256 oldDebt = (oldShare * totalDebt).ceilDiv(totalShare);
        if (amountCall == type(uint256).max) {
            amountCall = oldDebt;
        }
        uint256 paid = doRepay(token, doERC20TransferIn(token, amountCall));
        require(paid <= oldDebt, 'paid exceeds debt'); // prevent share overflow attack
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
        IERC20(token).safeTransferFrom(pos.owner, msg.sender, amount);
    }

    /// @dev Put more collateral for users. Must only be called during execution.
    /// @param collToken The ERC1155 token to collateral. (spell address)
    /// @param collId The token id to collateral.
    /// @param amountCall The amount of tokens to put via transferFrom.
    function putCollateral(
        address collToken,
        uint256 collId,
        uint256 amountCall
    ) external override inExec {
        Position storage pos = positions[POSITION_ID];
        if (pos.collToken != collToken || pos.collId != collId) {
            require(
                oracle.supportWrappedToken(collToken, collId),
                'collateral not supported'
            );
            require(
                pos.collateralSize == 0,
                'another type of collateral already exists'
            );
            pos.collToken = collToken;
            pos.collId = collId;
        }
        uint256 amount = doERC1155TransferIn(collToken, collId, amountCall);
        pos.collateralSize += amount;
        emit PutCollateral(POSITION_ID, msg.sender, collToken, collId, amount);
    }

    /// @dev Take some collateral back. Must only be called during execution.
    /// @param collToken The ERC1155 token to take back.
    /// @param collId The token id to take back.
    /// @param amount The amount of tokens to take back via transfer.
    function takeCollateral(
        address collToken,
        uint256 collId,
        uint256 amount
    ) external override inExec {
        Position storage pos = positions[POSITION_ID];
        require(collToken == pos.collToken, 'invalid collateral token');
        require(collId == pos.collId, 'invalid collateral token');
        if (amount == type(uint256).max) {
            amount = pos.collateralSize;
        }
        pos.collateralSize -= amount;
        IERC1155(collToken).safeTransferFrom(
            address(this),
            msg.sender,
            collId,
            amount,
            ''
        );
        emit TakeCollateral(POSITION_ID, msg.sender, collToken, collId, amount);
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
        borrowAmount = ISafeBox(bank.safeBox).borrow(amountCall);
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
        IERC20(token).safeTransfer(bank.safeBox, amountCall);
        uint256 newDebt = ISafeBox(bank.safeBox).repay(amountCall);
        repaidAmount = bank.totalDebt - newDebt;
        bank.totalDebt = newDebt;
    }

    /// @dev Internal function to perform ERC20 transfer in and return amount actually received.
    /// @param token The token to perform transferFrom action.
    /// @param amountCall The amount use in the transferFrom call.
    function doERC20TransferIn(address token, uint256 amountCall)
        internal
        returns (uint256)
    {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amountCall);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
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
        uint256 balanceBefore = IERC1155(token).balanceOf(address(this), id);
        IERC1155(token).safeTransferFrom(
            msg.sender,
            address(this),
            id,
            amountCall,
            ''
        );
        uint256 balanceAfter = IERC1155(token).balanceOf(address(this), id);
        return balanceAfter - balanceBefore;
    }
}
