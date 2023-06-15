pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../interfaces/IBank.sol";
import "../interfaces/ISoftVault.sol";
import "../interfaces/IWIchiFarm.sol";
import "../interfaces/ichi/IIchiFarm.sol";
import "../interfaces/ichi/IICHIVault.sol";
import "../utils/ERC1155NaiveReceiver.sol";

contract Liquidator is
    OwnableUpgradeable,
    AutomationCompatibleInterface,
    ERC1155NaiveReceiver
{
    /// @dev temperory state used to store uni v3 pool when swapping on uni v3
    ISwapRouter private swapRouter;

    /// @dev address of bank contract
    address public bankAddress;

    /// @dev address of USDC token
    address public USDC;

    /// @dev address of ICHI token
    address public ICHI;

    /// @dev current liquidation position ID
    uint256 public POS_ID;

    /// @dev aave pool addresses provider
    IPoolAddressesProvider public ADDRESSES_PROVIDER;

    /// @dev aave pool
    IPool public POOL;

    /// @dev mapping for token name to token address
    mapping(string => address) public tokenAddrs;

    /// @dev Initialize the bank smart contract, using msg.sender as the first governor.
    /// @param _poolAddressesProvider AAVE poolAdddressesProvider address
    /// @param _bankAddress BlueBerry bank contract address
    /// @param _swapRouter Swap Router address
    function initialize(
        address _poolAddressesProvider,
        address _bankAddress,
        address _swapRouter,
        address _USDC,
        address _ICHI
    ) external initializer {
        __Ownable_init();
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_poolAddressesProvider);
        POOL = IPool(IPoolAddressesProvider(_poolAddressesProvider).getPool());
        bankAddress = _bankAddress;
        USDC = _USDC;
        ICHI = _ICHI;
        swapRouter = ISwapRouter(_swapRouter);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint nextPositionId = IBank(bankAddress).nextPositionId();

        for (uint i = 1; i < nextPositionId; i += 1) {
            if (IBank(bankAddress).isLiquidatable(i)) {
                upkeepNeeded = true;
                performData = abi.encode(i);
                break;
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        (uint positionId, ) = abi.decode(performData, (uint256, bytes));

        if (IBank(bankAddress).isLiquidatable(positionId)) {
            liquidate(positionId);
        } else {
            revert("Not liquidatable");
        }
    }

    /**
     * @notice Liquidate position using AAVE flashloan
     * @param _positionId position id to liquidate
     */
    function liquidate(uint256 _positionId) public {
        IBank.Position memory posInfo = IBank(bankAddress).getPositionInfo(
            _positionId
        );

        // flash borrow the reserve tokens
        POS_ID = _positionId;

        POOL.flashLoanSimple(
            address(this),
            posInfo.debtToken,
            IBank(bankAddress).getPositionDebt(_positionId),
            abi.encode(msg.sender),
            0
        );
    }

    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @param asset The addresses of the flash-borrowed assets
     * @param amount The amounts of the flash-borrowed assets
     * @param premium The fee of each flash-borrowed asset
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata data
    ) external returns (bool) {
        address sender = abi.decode(data, (address));
        IBank.Position memory posInfo = IBank(bankAddress).getPositionInfo(
            POS_ID
        );
        IBank.Bank memory bankInfo = IBank(bankAddress).getBankInfoAll(
            posInfo.underlyingToken
        );

        // get the reserve and collateral tokens
        IERC1155 collateralToken = IERC1155(posInfo.collToken);
        IERC20 debtToken = IERC20(asset);

        // liquidate from bank
        uint256 uVaultShare = IERC20(bankInfo.softVault).balanceOf(
            address(this)
        );
        uint256 debtAmount = amount;
        uint256 fee = premium;

        // approve debtToken for bank and liquidate
        debtToken.approve(bankAddress, debtAmount);
        IBank(bankAddress).liquidate(POS_ID, address(debtToken), debtAmount);

        // check if collToken, uVaultShare are received after liquidation
        uVaultShare =
            IERC20(bankInfo.softVault).balanceOf(address(this)) -
            uVaultShare;
        require(
            uVaultShare != 0 &&
                IERC1155(posInfo.collToken).balanceOf(
                    address(this),
                    posInfo.collId
                ) >=
                posInfo.collateralSize,
            "Liquidation Error"
        );

        // Withdraw SoftVault share
        ISoftVault(bankInfo.softVault).withdraw(uVaultShare);

        // Withdraw ERC1155 liquidiation
        IWIchiFarm(posInfo.collToken).burn(
            posInfo.collId,
            posInfo.collateralSize
        );

        // Withdraw lp from ichiFarm
        (uint256 pid, ) = IWIchiFarm(posInfo.collToken).decodeId(
            posInfo.collId
        );
        address lpToken = IIchiFarm(IWIchiFarm(posInfo.collToken).ichiFarm())
            .lpToken(pid);
        IICHIVault(lpToken).withdraw(
            IERC20(lpToken).balanceOf(address(this)),
            address(this)
        );

        uint256 usdcAmt = IERC20(USDC).balanceOf(address(this));
        uint256 ichiAmt = IERC20(ICHI).balanceOf(address(this));
        uint256 uTokenAmt = IERC20Upgradeable(
            ISoftVault(bankInfo.softVault).uToken()
        ).balanceOf(address(this));

        if (USDC != address(debtToken) && usdcAmt != 0)
            _swap(USDC, address(debtToken), usdcAmt);
        if (ICHI != address(debtToken) && ichiAmt != 0)
            _swap(ICHI, address(debtToken), ichiAmt);
        if (
            address(ISoftVault(bankInfo.softVault).uToken()) !=
            address(debtToken) &&
            uTokenAmt != 0
        )
            _swap(
                address(ISoftVault(bankInfo.softVault).uToken()),
                address(debtToken),
                uTokenAmt
            );

        // approve aave pool to get back debt
        debtToken.approve(address(POOL), debtAmount + fee);

        // send remained reserve token to msg.sender
        debtToken.transfer(
            sender,
            debtToken.balanceOf(address(this)) - debtAmount - fee
        );

        // reset position id
        POS_ID = 0;

        return true;
    }

    function _swap(
        address _srcToken,
        address _dstToken,
        uint256 _amount
    ) internal {
        if (IERC20(_srcToken).balanceOf(address(this)) >= _amount) {
            IERC20(_srcToken).approve(address(swapRouter), _amount);

            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: _srcToken,
                    tokenOut: _dstToken,
                    fee: 1e4,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }
}
