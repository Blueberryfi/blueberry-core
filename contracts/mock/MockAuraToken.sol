// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MockAuraToken is ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    address public operator;
    address public vecrvProxy;

    uint256 public constant EMISSIONS_MAX_SUPPLY = 5e25; // 50m
    uint256 public constant INIT_MINT_AMOUNT = 5e25; // 50m
    uint256 public constant totalCliffs = 500;
    uint256 public immutable reductionPerCliff;
    uint256 private _manuallyMinted;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor() ERC20("Aura Token", "AURA") {
        operator = msg.sender;
        reductionPerCliff = EMISSIONS_MAX_SUPPLY / totalCliffs;

        _mint(msg.sender, INIT_MINT_AMOUNT);
    }

    function setOperator(address _operator) external {
        operator = _operator;
    }

    function mintTestTokens(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function mintTestTokensManually(address to, uint256 amount) external {
        _manuallyMinted += amount;
        _mint(to, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return super.totalSupply() - _manuallyMinted;
    }

    function mint(address _to, uint256 _amount) external {
        require(totalSupply() != 0, "Not initialised");

        if (msg.sender != operator) {
            // dont error just return. if a shutdown happens, rewards on old system
            // can still be claimed, just wont mint cvx
            return;
        }

        // e.g. emissionsMinted = 6e25 - 5e25 - 0 = 1e25;
        uint256 emissionsMinted = totalSupply() - INIT_MINT_AMOUNT;
        // e.g. reductionPerCliff = 5e25 / 500 = 1e23
        // e.g. cliff = 1e25 / 1e23 = 100
        uint256 cliff = emissionsMinted / reductionPerCliff;

        // e.g. 100 < 500
        if (cliff < totalCliffs) {
            // e.g. (new) reduction = (500 - 100) * 2.5 + 700 = 1700;
            // e.g. (new) reduction = (500 - 250) * 2.5 + 700 = 1325;
            // e.g. (new) reduction = (500 - 400) * 2.5 + 700 = 950;
            uint256 reduction = totalCliffs.sub(cliff).mul(5).div(2).add(700);
            // e.g. (new) amount = 1e19 * 1700 / 500 =  34e18;
            // e.g. (new) amount = 1e19 * 1325 / 500 =  26.5e18;
            // e.g. (new) amount = 1e19 * 950 / 500  =  19e17;
            uint256 amount = _amount.mul(reduction).div(totalCliffs);
            // e.g. amtTillMax = 5e25 - 1e25 = 4e25
            uint256 amtTillMax = EMISSIONS_MAX_SUPPLY.sub(emissionsMinted);
            if (amount > amtTillMax) {
                amount = amtTillMax;
            }
            _mint(_to, amount);
        }
    }
}
