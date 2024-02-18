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

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../utils/BlueberryErrors.sol" as Errors;

import { UsingBaseOracle } from "./UsingBaseOracle.sol";

import { IBaseOracle } from "../interfaces/IBaseOracle.sol";
import { IBErc20 } from "../interfaces/money-market/IBErc20.sol";
import { ISoftVault } from "../interfaces/ISoftVault.sol";

/**
 * @title SoftVaultOracle
 * @author BlueberryProtocol
 * @notice Oracle contract which privides price feeds of SoftVaults (ibTokens)
 */
contract SoftVaultOracle is IBaseOracle, UsingBaseOracle {
    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS 
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Struct to store token info related to Balancer Pool tokens
     * @param bToken The bToken associated with the soft vault
     * @param underlyingToken The base ERC20 token associated with the soft vault
     * @param underlyingDecimals The decimals of the underlying token
     */
    struct VaultInfo {
        address bToken;
        address underlyingToken;
        uint8 underlyingDecimals;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev mapping of registered Soft Vaults to their VaultInfo Struct
    mapping(address => VaultInfo) private _vaultInfo;

    /// @dev constant to represent the number of decimals in the SoftVault
    uint256 private constant _VAULT_DECIMALS = 8;

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
     * @notice Initializes the contract
     * @param base The base oracle instance.
     * @param owner Address of the owner of the contract.
     */
    function initialize(IBaseOracle base, address owner) external initializer {
        __UsingBaseOracle_init(base, owner);
    }

    /// @inheritdoc IBaseOracle
    function getPrice(address token) public view override returns (uint256) {
        VaultInfo memory vaultInfo = _vaultInfo[token];

        if (vaultInfo.bToken == address(0) || vaultInfo.underlyingToken == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        return
            (IBErc20(vaultInfo.bToken).exchangeRateStored() * _base.getPrice(vaultInfo.underlyingToken)) /
            10 ** (18 + vaultInfo.underlyingDecimals - _VAULT_DECIMALS);
    }

    /**
     * @notice Registers the Soft Vault to oracle
     * @dev Stores persistent data of an Soft Vault
     * @dev An oracle cannot be used for a token unless it is registered
     * @param softVault Address of the Blueberry Interest Bearing token (Soft Vault) to register
     */
    function registerSoftVault(address softVault) external onlyOwner {
        address underlyingToken = address(ISoftVault(softVault).getUnderlyingToken());
        address bToken = address(ISoftVault(softVault).getBToken());

        if (bToken == address(0) || underlyingToken == address(0)) {
            revert Errors.ZERO_ADDRESS();
        }

        _vaultInfo[softVault] = VaultInfo(bToken, underlyingToken, IERC20Metadata(underlyingToken).decimals());
    }
}
