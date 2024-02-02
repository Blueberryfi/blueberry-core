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

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../utils/BlueberryErrors.sol" as Errors;
import "../libraries/Paraswap/PSwapLib.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IBlueberryLiquidator, AutomationCompatibleInterface } from "../interfaces/IBlueberryLiquidator.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";

/**
 * @title BaseLiquidator
 * @author BlueberryProtocol
 * @notice This contract is the base contract for all liquidators to inherit from
 * @dev Each spell will have its own liquidator contract
 */
abstract contract BaseLiquidator is IBlueberryLiquidator, Ownable2StepUpgradeable {
    /// @dev The instance of the BlueberryBank contract
    IBank internal _bank;

    /// @dev The address of the spell that this liquidator is for
    address internal _spell;

    /// @dev paraswap AugustusSwapper Address
    address internal _augustusSwapper;

    /// @dev paraswap TokenTransferProxy Address
    address internal _tokenTransferProxy;

    /// @dev The position id of the liquidation
    uint256 public POS_ID;

    /// @dev Aave LendingPool
    IPool public _pool;

    /// @dev The address of the stable token used for liquidation profits
    address public _stableAsset;

    /// @dev aave pool addresses provider
    IPoolAddressesProvider public _poolAddressesProvider;

    /*//////////////////////////////////////////////////////////////////////////
                                      FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc AutomationCompatibleInterface
    function checkUpkeep(
        bytes calldata /* checkData */
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint nextPositionId = IBank(_bank).getNextPositionId();

        /// @audit: Will PositionID ever be 1
        /// @audit: Is there a way to read the health score of a position directly from the bank contract.
        /// @audit: False positives on closed positions?
        for (uint i = 1; i < nextPositionId; ++i) {
            if (_bank.isLiquidatableStored(i)) {
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

        // flash borrow the reserve tokens
        POS_ID = _positionId;

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
        address asset,
        uint256 amount,
        uint256 premium,
        address /*initiator*/,
        bytes calldata data
    ) external virtual override returns (bool) {
        require(msg.sender == address(_pool));

        address sender = abi.decode(data, (address));
        IBank.Position memory posInfo = _bank.getPositionInfo(POS_ID);
        IBank.Bank memory bankInfo = _bank.getBankInfo(posInfo.underlyingToken);

        // get the reserve and collateral tokens
        IERC20 debtToken = IERC20(asset);

        // liquidate from bank
        uint256 uVaultShare = IERC20(bankInfo.softVault).balanceOf(address(this));
        uint256 debtAmount = amount;
        uint256 fee = premium;

        // approve debtToken for bank and liquidate
        debtToken.approve(address(_bank), debtAmount);
        _bank.liquidate(POS_ID, address(debtToken), debtAmount);

        // check if collToken, uVaultShare are received after liquidation
        uVaultShare = IERC20(bankInfo.softVault).balanceOf(address(this)) - uVaultShare;
        require(
            uVaultShare != 0 &&
                IERC1155(posInfo.collToken).balanceOf(address(this), posInfo.collId) >= posInfo.collateralSize,
            "Liquidation Error"
        );

        // Withdraw SoftVault share
        ISoftVault(bankInfo.softVault).withdraw(uVaultShare);

        // Unwind position
        _unwindPosition(posInfo, bankInfo.softVault, asset);

        // approve aave pool to get back debt
        debtToken.approve(address(_pool), debtAmount + fee);

        // send remained reserve token to msg.sender
        debtToken.transfer(sender, debtToken.balanceOf(address(this)) - debtAmount - fee);

        // reset position id
        POS_ID = 0;

        return true;
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
     * @notice Swaps two assets with paraswaps augustus swapper
     * @param srcToken Address of the source token
     * @param dstToken Address of the destination token
     * @param amount Amount of source tokens to swap for
     */
    function _swapOnParaswap(address srcToken, address dstToken, uint256 amount) internal {
        if(
            !PSwapLib.swap(_augustusSwapper, _tokenTransferProxy, srcToken, amount, )
        ) {
            revert Errors.SWAP_FAILED(srcToken);
        }
    }

    /**
     * @notice Unwinds the users position, by burning the wrapper token and liquidating into the debt token
     * @dev This function will be implemented by the child liquidator contract for a specific integration
     * @param posInfo The Position information struct for the position that is being liquidated
     * @param softVault Address of the SoftVault contract that the position is using
     * @param debtToken The address of the debt token, this will be the same asset that will be flash-borrowed
     */
    function _unwindPosition(IBank.Position memory posInfo, address softVault, address debtToken) internal virtual {
        // unwind position
    }
}
