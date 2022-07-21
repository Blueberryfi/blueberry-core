pragma solidity ^0.8.9;

import 'OpenZeppelin/openzeppelin-contracts@3.4.0/contracts/token/ERC20/ERC20.sol';

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public ERC20(name, symbol) {
        _setupDecimals(decimals);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
