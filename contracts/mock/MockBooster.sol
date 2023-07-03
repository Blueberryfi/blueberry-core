// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockBooster {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    //index(pid) -> pool
    PoolInfo[] public poolInfo;

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //create a new pool
    function addPool(
        address _lptoken,
        address _token,
        address _gauge,
        address _crvRewards,
        address _stash
    ) external returns (bool) {
        //add the new pool
        poolInfo.push(
            PoolInfo({
                lptoken: _lptoken,
                token: _token,
                gauge: _gauge,
                crvRewards: _crvRewards,
                stash: _stash,
                shutdown: false
            })
        );
        return true;
    }
}
