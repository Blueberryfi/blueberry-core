// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockStashToken {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public constant MAX_TOTAL_SUPPLY = 1e38;

    address public rewardPool;
    address public baseToken;

    uint256 internal _totalSupply;

    function init(address _rewardPool, address _baseToken) external {
        rewardPool = _rewardPool;
        baseToken = _baseToken;
    }

    function name() external view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "Stash Token ",
                    IERC20Metadata(baseToken).name()
                )
            );
    }

    function symbol() external view returns (string memory) {
        return
            string(
                abi.encodePacked("STASH-", IERC20Metadata(baseToken).symbol())
            );
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function mint(uint256 _amount) external {
        require(
            _totalSupply.add(_amount) < MAX_TOTAL_SUPPLY,
            "totalSupply exceeded"
        );

        _totalSupply = _totalSupply.add(_amount);
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(msg.sender == rewardPool, "!rewardPool");
        require(_totalSupply >= _amount, "amount>totalSupply");

        _totalSupply = _totalSupply.sub(_amount);
        IERC20(baseToken).safeTransfer(_to, _amount);

        return true;
    }
}
