// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IProtocolConfig.sol";
import "./utils/BlueBerryConst.sol" as Constants;
import "./utils/BlueBerryErrors.sol" as Errors;

import "hardhat/console.sol";

contract FeeManager is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IProtocolConfig config;

    function initialize(IProtocolConfig config_) external initializer {
        __Ownable_init();

        if (address(config_) == address(0)) revert Errors.ZERO_ADDRESS();
        config = config_;
    }

    function doCutDepositFee(address token, uint256 amount)
        external
        returns (uint256)
    {
        return _doCutFee(token, amount, config.depositFee());
    }

    function doCutWithdrawFee(address token, uint256 amount)
        external
        returns (uint256)
    {
        return _doCutFee(token, amount, config.withdrawFee());
    }

    /// @dev Cut performance fee from the rewards generated from the leveraged position
    /// @param token The token to perform the refund action.
    function doCutRewardsFee(address token, uint256 rewards)
        external
        returns (uint256)
    {
        return _doCutFee(token, rewards, config.rewardFee());
    }

    function _doCutFee(
        address token,
        uint256 amount,
        uint256 feeRate
    ) internal returns (uint256) {
        address treasury = config.treasury();
        if (treasury == address(0)) revert Errors.NO_TREASURY_SET();

        uint256 fee = (amount * feeRate) / Constants.DENOMINATOR;
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, treasury, fee);
        return amount - fee;
    }
}
