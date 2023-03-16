pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@aave/core-v3/contracts/flashloan/base/FlashLoanReceiverBase.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "../interfaces/IBank.sol";
import "../interfaces/ISoftVault.sol";
import "../interfaces/IWIchiFarm.sol";
import "../interfaces/ichi/IIchiFarm.sol";
import "../interfaces/ichi/IICHIVault.sol";

contract LiquidationBot is FlashLoanReceiverBase {
    /// @dev temperory state used to store uni v3 pool when swapping on uni v3
    ISwapRouter private swapRouter;

    /// @dev address of AAVE lending pool
    address public lendingPoolAddress;

    /// @dev address of bank contract
    address public bankAddress;

    /// @dev address of USDC token
    address public USDC;

    /// @dev address of ICHI token
    address public ICHI;

    /// @dev current liquidation position ID
    uint256 public POS_ID;

    mapping(string => address) public tokenAddrs;

    constructor(
        address _poolAddressesProvider,
        address _bankAddress,
        address _swapRouter,
        address _USDC,
        address _ICHI
    ) FlashLoanReceiverBase(IPoolAddressesProvider(_poolAddressesProvider)) {
        bankAddress = _bankAddress;
        USDC = _USDC;
        ICHI = _ICHI;
        swapRouter = ISwapRouter(_swapRouter);
    }

    function liquidate(uint256 _positionId) external {
        IBank.Position memory posInfo = IBank(bankAddress).getPositionInfo(
            _positionId
        );

        // flash borrow the reserve tokens
        address[] memory assets = new address[](1);
        assets[0] = posInfo.debtToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = IBank(bankAddress).getPositionDebt(_positionId);
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt, 1 = stable debt, 2 = variable debt
        address onBehalfOf = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;

        POS_ID = _positionId;
        POOL.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }

    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @param assets The addresses of the flash-borrowed assets
     * @param amounts The amounts of the flash-borrowed assets
     * @param premiums The fee of each flash-borrowed asset
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        IBank.Position memory posInfo = IBank(bankAddress).getPositionInfo(
            POS_ID
        );
        IBank.Bank memory bankInfo = IBank(bankAddress).getBankInfoAll(
            posInfo.underlyingToken
        );

        // get the reserve and collateral tokens
        IERC1155 collateralToken = IERC1155(posInfo.collToken);
        IERC20 debtToken = IERC20(assets[0]);

        // liquidate from bank
        uint256 uVaultShare = IERC20(bankInfo.softVault).balanceOf(
            address(this)
        );
        uint256 debtAmount = amounts[0];
        uint256 fee = premiums[0];

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
        _swap(USDC, address(debtToken), usdcAmt);
        _swap(ICHI, address(debtToken), ichiAmt);
        _swap(
            address(ISoftVault(bankInfo.softVault).uToken()),
            address(debtToken),
            uTokenAmt
        );

        // send bank for flashloan
        debtToken.transfer(address(POOL), debtAmount + fee);

        // send remained reserve token to msg.sender
        debtToken.transfer(msg.sender, debtToken.balanceOf(address(this)));

        // reset position id
        POS_ID = 0;

        return true;
    }

    function _swap(
        address _srcToken,
        address _dstToken,
        uint256 _amount
    ) internal {
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
