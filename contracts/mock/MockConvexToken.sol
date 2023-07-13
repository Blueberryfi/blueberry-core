// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockConvexToken is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;

    address public operator;
    address public vecrvProxy;

    uint256 public maxSupply = 100 * 1000000 * 1e18; //100mil
    uint256 public totalCliffs = 1000;
    uint256 public reductionPerCliff;

    constructor() ERC20("Convex Token", "CVX") {
        operator = msg.sender;
        reductionPerCliff = maxSupply / totalCliffs;
    }

    function mintTestTokens(address to, uint amount) external {
        _mint(to, amount);
    }

    function mint(address _to, uint256 _amount) external {
        if (msg.sender != operator) {
            //dont error just return. if a shutdown happens, rewards on old system
            //can still be claimed, just wont mint cvx
            return;
        }

        uint256 supply = totalSupply();
        if (supply == 0) {
            //premine, one time only
            _mint(_to, _amount);
            return;
        }

        //use current supply to gauge cliff
        //this will cause a bit of overflow into the next cliff range
        //but should be within reasonable levels.
        //requires a max supply check though
        uint256 cliff = supply / reductionPerCliff;
        //mint if below total cliffs
        if (cliff < totalCliffs) {
            //for reduction% take inverse of current cliff
            uint256 reduction = totalCliffs - cliff;
            //reduce
            _amount = (_amount * reduction) / totalCliffs;

            //supply cap check
            uint256 amtTillMax = maxSupply - supply;
            if (_amount > amtTillMax) {
                _amount = amtTillMax;
            }

            //mint
            _mint(_to, _amount);
        }
    }
}
