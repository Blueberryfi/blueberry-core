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

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { IPoolAddressesProvider } from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../utils/BlueberryErrors.sol" as Errors;
import "../libraries/UniV3/LiquidityAmounts.sol" as UniLiquidity;

import { SwapRegistry } "./SwapRegistry.sol";

import { IBank } from "../interfaces/IBank.sol";
import { IBlueberryLiquidator, AutomationCompatibleInterface } from "../interfaces/IBlueberryLiquidator.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";

/**
 * @title BaseLiquidator
 * @author BlueberryProtocol
 * @notice This contract is the base contract for all liquidators to inherit from
 * @dev Each spell will have its own liquidator contract
 */
abstract contract BaseLiquidator is IBlueberryLiquidator, SwapRegistry {
    /// @dev The instance of the BlueberryBank contract
    IBank internal _bank;

    /// @dev The address of the spell that this liquidator is for
    address internal _spell;

    /// @dev The address of the treasury that will receive the profits of this bot
    address internal _treasury;

    /// @dev The position id of the liquidation
    uint256 internal POS_ID;

    /// @dev Aave LendingPool
    IPool private _pool;

    /// @dev The address of the stable token used for liquidation profits
    address internal _stableAsset;

    /// @dev aave pool addresses provider
    IPoolAddressesProvider private _poolAddressesProvider;

    /// @dev The Balancer Vault address
    address private _balancerVault;

    /// @dev The address of the swap router
    ISwapRouter private _swapRouter;

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

        // check if collToken (debtToken), uVaultShare are received after liquidation
        uint256 uVaultShareAfter = IERC20(bankInfo.softVault).balanceOf(address(this));
        uVaultShare = uVaultShareAfter - uVaultShare;

        require(
            uVaultShare > 0 &&
                IERC1155(posInfo.collToken).balanceOf(address(this), posInfo.collId) >= posInfo.collateralSize,
            "Liquidation Error"
        );

        // Withdraw SoftVault share to receive underlying token
        ISoftVault(bankInfo.softVault).withdraw(uVaultShare);

        // Unwind position
        _unwindPosition(posInfo, bankInfo.softVault, asset, debtAmount + fee);

        // approve aave pool to get back debt
        debtToken.approve(address(_pool), debtAmount + fee);

        // send remained reserve token to msg.sender
        debtToken.transfer(sender, debtToken.balanceOf(address(this)) - debtAmount - fee);

        // reset position id
        POS_ID = 0;

        // Send Profits to treasury

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
        // unwind position
    }

    function _swap(address srcToken, address dstToken, uint256 amount) internal {
        DexRoute route = _dexRoutes[srcToken];
        if (route == DexRoute.Balancer) {
            _swapOnBalancer(srcToken, dstToken, amount);
        } else if (route == DexRoute.Curve) {
            _swapOnCurve(srcToken, dstToken, amount);
        } else {
            _swapOnUniswap(srcToken, dstToken, amount);
        }
    }

    function _swapOnBalancer(address srcToken, address dstToken, uint256 amount) internal return (address dstToken, uint256 amount) {
        if (IERC20(srcToken).balanceOf(address(this)) >= amount) {
            if (srcToken == _auraToken || srcToken == _balToken) {
                dstToken == address(_weth);
            }

            IERC20(srcToken).approve(address(_balancerVault), amount);

            uint256 poolId = _balancerRoutes[srcToken][dstToken];

            if (poolId == bytes32(0)) {
                revert Errors.ZERO_AMOUNT();
            }

            IBalancerVault.SingleSwap memory singleSwap;
            singleSwap.poolId = poolId; 
            singleSwap.kind = IBalancerVault.SwapKind.GIVEN_IN;
            singleSwap.assetIn = IAsset(srcToken);
            singleSwap.assetOut = IAsset(dstToken);
            singleSwap.amount = amount;

            IBalancerVault.FundManagement memory funds;
            funds.sender = address(this);
            funds.recipient = payable(address(this));
            
            amount = _balancerVault.swap(singleSwap, funds, 0, block.timestamp);
        }
    }

    function _swapOnCurve(address srcToken, address dstToken, uint256 amount) internal (address dstToken, uint256 amountReceived) {
        if (IERC20(srcToken).balanceOf(address(this)) >= amount) {
            if (srcToken == _crvToken || srcToken == _convexToken) {
                dstToken == address(_weth);
            }
            
            ICurvePool pool = ICurvePool(_curveRoutes[srcToken][dstToken]);
            IERC20(srcToken).approve(address(pool), amount);
            
            uint256 srcIndex;
            uint256 dstIndex;
            for (uint256 i=0; i<3; i++) {
                try pool.coins(i) returns (address coin) {
                    if (coin == srcToken) {
                        srcIndex = i;
                    } else if (coin == dstToken) {
                        dstIndex = i;
                    }
                } catch {}

                if (srcIndex != 0 && dstIndex != 0) {
                    break;
                }
            }

            amountReceived = pool.exchange(srcIndex, dstIndex, amount, 0, false, address(this));
        }
    }

    function _swapOnUniswap(address srcToken, address dstToken, uint256 amount) internal returns (uint256 amountReceived) {
        if (IERC20(srcToken).balanceOf(address(this)) >= amount) {
            IERC20(srcToken).approve(address(_swapRouter), amount);

            uint256 amountReceived = _swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: srcToken,
                    tokenOut: dstToken,
                    fee: 3000,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }
}
