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

import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SwapRegistry } from "./SwapRegistry.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IBlueberryLiquidator, AutomationCompatibleInterface } from "../interfaces/IBlueberryLiquidator.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";

/**
 * @title BaseLiquidator
 * @author BlueberryProtocol
 * @notice This contract is the base contract for all liquidators to inherit from
 * @dev Each spell will have its own liquidator contract
 */
abstract contract BaseLiquidator is IBlueberryLiquidator, SwapRegistry, IERC1155Receiver {
    using SafeERC20 for IERC20;

    /// @dev The instance of the BlueberryBank contract
    IBank internal _bank;

    /// @dev The address of the spell that this liquidator is for
    address internal _spell;

    /// @dev The address of the treasury that will receive the profits of this bot
    address internal _treasury;

    /// @dev The position id of the liquidation
    // solhint-disable-next-line var-name-mixedcase
    uint256 internal _POS_ID;

    /// @dev Aave LendingPool
    IPool private _pool;

    /// @dev aave pool addresses provider
    IPoolAddressesProvider private _poolAddressesProvider;

    /// @dev The address of the emergency fund that will cover any extra costs for liquidation
    address internal _emergencyFund;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc AutomationCompatibleInterface
    function checkUpkeep(
        bytes calldata /* checkData */
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint nextPositionId = IBank(_bank).getNextPositionId();

        for (uint i = 1; i < nextPositionId; ++i) {
            if (_bank.isLiquidatable(i)) {
                upkeepNeeded = true;
                performData = abi.encode(i);
                break;
            }
        }
    }

    /// @inheritdoc AutomationCompatibleInterface
    function performUpkeep(bytes calldata performData) external override {
        (uint positionId, ) = abi.decode(performData, (uint256, bytes));

        if (_bank.isLiquidatable(positionId)) {
            liquidate(positionId);
        } else {
            revert Errors.NOT_LIQUIDATABLE(positionId);
        }
    }

    /// @inheritdoc IBlueberryLiquidator
    function liquidate(uint256 _positionId) public {
        IBank.Position memory posInfo = _bank.getPositionInfo(_positionId);

        _bank.accrue(posInfo.debtToken);

        // flash borrow the reserve tokens
        _POS_ID = _positionId;

        _pool.flashLoanSimple(
            address(this),
            posInfo.debtToken,
            _bank.getPositionDebt(_positionId),
            abi.encode(msg.sender),
            0
        );
    }

    /// @inheritdoc IBlueberryLiquidator
    function executeOperation(
        address asset, // DebtToken
        uint256 amount, // DebtAmount
        uint256 premium, // Fee
        address /*initiator*/,
        bytes calldata /*data*/
    ) external virtual override returns (bool) {
        if (msg.sender != address(_pool)) {
            revert Errors.UNAUTHORIZED();
        }

        IBank.Position memory posInfo = _bank.getPositionInfo(_POS_ID);
        IBank.Bank memory bankInfo = _bank.getBankInfo(posInfo.underlyingToken);

        // liquidate from bank
        uint256 uVaultShare = IERC20(bankInfo.softVault).balanceOf(address(this));

        // forceApprove debtToken for bank and liquidate
        IERC20(asset).forceApprove(address(_bank), amount);

        _bank.liquidate(_POS_ID, address(asset), amount);

        // check if collToken (debtToken/asset), uVaultShare are received after liquidation
        uVaultShare = IERC20(bankInfo.softVault).balanceOf(address(this)) - uVaultShare;

        // Withdraw SoftVault share to receive underlying token
        ISoftVault(bankInfo.softVault).withdraw(uVaultShare);

        // Unwind position
        _unwindPosition(posInfo, bankInfo.softVault, asset, amount + premium);

        // forceApprove aave pool to get back debt
        IERC20(asset).forceApprove(address(_pool), amount + premium);

        // Have the emergency fund cover any extra costs
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        if (assetBalance < amount + premium) {
            _accessEmergencyFunds(asset, (amount + premium) - assetBalance);
        }

        // reset position id
        _POS_ID = 0;

        return true;
    }

    /**
     * @notice Withdraws the balance of specified tokens from the contract
     * @param tokens The array of tokens to withdraw
     */
    function withdraw(address[] memory tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.transfer(_treasury, token.balanceOf(address(this)));
        }
    }

    /**
     * @notice Sets the address of the emergency fund
     * @param emergencyFund The address of the emergency fund
     */
    function setEmergencyFund(address emergencyFund) external onlyOwner {
        if (emergencyFund == address(0)) revert Errors.ZERO_ADDRESS();
        _emergencyFund = emergencyFund;
    }

    /**
     * @notice Sends emergency funds to the contract to cover unprofitable liquidations
     * @param asset The address of the asset to withdraw from the contract
     * @param amount Amount of asset to send to the liquidator bot
     */
    function _accessEmergencyFunds(address asset, uint256 amount) internal {
        IERC20(asset).transferFrom(_emergencyFund, address(this), amount);
    }

    /**
     * @notice Sets the Aave Lending Pool and Aave Pool Address Provider during initialization
     * @param poolAddressesProvider Address of Aave's PoolAddressesProvider
     */
    function _initializeAavePoolInfo(address poolAddressesProvider) internal {
        _poolAddressesProvider = IPoolAddressesProvider(poolAddressesProvider);
        _pool = IPool(IPoolAddressesProvider(poolAddressesProvider).getPool());
    }

    /**
     * @notice Swaps the source token for the destination token
     * @dev Swaps between the three major Dexes: Balancer, Curve, and Uniswap
     * @param srcToken The address of the source token
     * @param dstToken The address of the destination token
     * @param amount The amount of the source token to swap
     * @return amountReceived The amount of the destination token received
     */
    function _swap(address srcToken, address dstToken, uint256 amount) internal returns (uint256 amountReceived) {
        DexRoute route = _tokenToExchange[srcToken];

        address tokenReceived;
        if (route == DexRoute.Balancer) {
            (tokenReceived, amountReceived) = _swapOnBalancer(srcToken, dstToken, amount);
        } else if (route == DexRoute.Curve) {
            (tokenReceived, amountReceived) = _swapOnCurve(srcToken, dstToken, amount);
        } else {
            (tokenReceived, amountReceived) = _swapOnUniswap(srcToken, dstToken, amount);
        }

        // If the token received is not the same as the desired destination token, recursively swap until we
        // get the desired token. This will only happen in the event of a multi-hop swap
        if (tokenReceived != dstToken) {
            amountReceived = _swap(tokenReceived, dstToken, amountReceived);
        }
    }

    /**
     * @notice Unwinds the users position, by burning the wrapper token and liquidating into the debt token
     * @dev This function will be implemented by the child liquidator contract for a specific integration
     * @param posInfo The Position information struct for the position that is being liquidated
     * @param softVault Address of the SoftVault contract that the position is using
     * @param debtToken The address of the debt token, this will be the same asset that will be flash-borrowed
     * @param debtAmount The amount of debt that needs to be repaid for the flash loan
     */
    function _unwindPosition(
        IBank.Position memory posInfo,
        address softVault,
        address debtToken,
        uint256 debtAmount
    ) internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @notice Single-sided exits the liquidity pool to receive the debt token
     * @param lpToken The address of the LP token of the pool that needs to be exited
     * @param debtToken The address of the debt token that should be received after exiting the pool
     */
    function _exit(IERC20 lpToken, address debtToken) internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*//////////////////////////////////////////////////////////////////////////
                            Required ERC1155 Overrides
    //////////////////////////////////////////////////////////////////////////*/

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*value*/,
        bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return (this.onERC1155Received.selector);
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function supportsInterface(bytes4 /*interfaceId*/) external pure returns (bool) {
        return true;
    }
}
