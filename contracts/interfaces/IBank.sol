// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IBank {
    /// The governor adds a new bank gets added to the system.
    event AddBank(address token, address cToken);
    /// The governor sets the address of the oracle smart contract.
    event SetOracle(address oracle);
    /// The governor sets the basis point fee of the bank.
    event SetFeeBps(uint256 feeBps);
    /// The governor withdraw tokens from the reserve of a bank.
    event WithdrawReserve(address user, address token, uint256 amount);
    /// Someone borrows tokens from a bank via a spell caller.
    event Borrow(
        uint256 positionId,
        address caller,
        address token,
        uint256 amount,
        uint256 share
    );
    /// Someone repays tokens to a bank via a spell caller.
    event Repay(
        uint256 positionId,
        address caller,
        address token,
        uint256 amount,
        uint256 share
    );
    /// Someone puts tokens as collateral via a spell caller.
    event PutCollateral(
        uint256 positionId,
        address caller,
        address token,
        uint256 id,
        uint256 amount
    );
    /// Someone takes tokens from collateral via a spell caller.
    event TakeCollateral(
        uint256 positionId,
        address caller,
        address token,
        uint256 id,
        uint256 amount
    );
    /// Someone calls liquidatation on a position, paying debt and taking collateral tokens.
    event Liquidate(
        uint256 positionId,
        address liquidator,
        address debtToken,
        uint256 amount,
        uint256 share,
        uint256 bounty
    );

    /// @dev Return the current position while under execution.
    function POSITION_ID() external view returns (uint256);

    /// @dev Return the current target while under execution.
    function SPELL() external view returns (address);

    /// @dev Return the current executor (the owner of the current position).
    function EXECUTOR() external view returns (address);

    /// @dev Return bank information for the given token.
    function getBankInfo(address token)
        external
        view
        returns (
            bool isListed,
            address cToken,
            uint256 reserve,
            uint256 totalDebt,
            uint256 totalShare
        );

    /// @dev Return position information for the given position id.
    function getPositionInfo(uint256 positionId)
        external
        view
        returns (
            address owner,
            address collToken,
            uint256 collId,
            uint256 collateralSize
        );

    /// @dev Return the borrow balance for given positon and token without trigger interest accrual.
    function borrowBalanceStored(uint256 positionId, address token)
        external
        view
        returns (uint256);

    /// @dev Trigger interest accrual and return the current borrow balance.
    function borrowBalanceCurrent(uint256 positionId, address token)
        external
        returns (uint256);

    /// @dev Lend tokens from the bank.
    function lend(address token, uint256 amount) external;

    /// @dev Borrow tokens from the bank.
    function borrow(address token, uint256 amount) external;

    /// @dev Repays tokens to the bank.
    function repay(address token, uint256 amountCall) external;

    /// @dev Transmit user assets to the spell.
    function transmit(address token, uint256 amount) external;

    /// @dev Put more collateral for users.
    function putCollateral(
        address collToken,
        uint256 collId,
        uint256 amountCall
    ) external;

    /// @dev Take some collateral back.
    function takeCollateral(
        address collToken,
        uint256 collId,
        uint256 amount
    ) external;

    /// @dev Liquidate a position.
    function liquidate(
        uint256 positionId,
        address debtToken,
        uint256 amountCall
    ) external;

    function getDebtValue(uint256 positionId) external view returns (uint256);

    function getCollateralValue(uint256 positionId)
        external
        view
        returns (uint256);

    function accrue(address token) external;

    function nextPositionId() external view returns (uint256);

    /// @dev Return current position information.
    function getCurrentPositionInfo()
        external
        view
        returns (
            address owner,
            address collToken,
            uint256 collId,
            uint256 collateralSize
        );

    function support(address token) external view returns (bool);
}
