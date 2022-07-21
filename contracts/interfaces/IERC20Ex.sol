pragma solidity ^0.8.9;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/IERC20.sol';

// Export IERC20 interface for mainnet-fork testing.
interface IERC20Ex is IERC20 {
    function name() external view returns (string memory);

    function owner() external view returns (address);

    function issue(uint256) external;

    function issue(address, uint256) external;

    function mint(address, uint256) external;

    function mint(
        address,
        uint256,
        uint256
    ) external returns (bool);

    function configureMinter(address, uint256) external returns (bool);

    function masterMinter() external view returns (address);

    function deposit() external payable;

    function deposit(uint256) external;

    function decimals() external view returns (uint256);

    function target() external view returns (address);

    function erc20Impl() external view returns (address);

    function custodian() external view returns (address);

    function requestPrint(address, uint256) external returns (bytes32);

    function confirmPrint(bytes32) external;

    function invest(uint256) external;

    function increaseSupply(uint256) external;

    function supplyController() external view returns (address);

    function getModules() external view returns (address[] memory);

    function addMinter(address) external;

    function governance() external view returns (address);

    function core() external view returns (address);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function symbol() external view returns (string memory);

    function getFinalTokens() external view returns (address[] memory);

    function joinPool(uint256, uint256[] memory) external;

    function getBalance(address) external view returns (uint256);

    function createTokens(uint256) external returns (bool);

    function resolverAddressesRequired()
        external
        view
        returns (bytes32[] memory addresses);

    function exchangeRateStored() external view returns (uint256);

    function accrueInterest() external returns (uint256);

    function resolver() external view returns (address);

    function repository(bytes32) external view returns (address);

    function underlying() external view returns (address);

    function mint(uint256) external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function minter() external view returns (address);

    function borrow(uint256) external returns (uint256);
}
