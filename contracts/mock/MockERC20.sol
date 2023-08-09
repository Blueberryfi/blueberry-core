// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 _decimals;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimal
    ) ERC20(name, symbol) {
        _decimals = decimal;
    }

    function setDecimals(uint8 decimal) external {
        _decimals = decimal;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint() external {
        _mint(msg.sender, 100 * 10 ** _decimals);
    }

    function mintWithAmount(uint amount) external {
        _mint(msg.sender, amount);
    }

    function mintTo(address to, uint amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint amount) external {
        _burn(from, amount);
    }
}
