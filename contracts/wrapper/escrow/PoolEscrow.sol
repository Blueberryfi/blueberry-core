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

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../../utils/BlueBerryErrors.sol" as Errors;
import "../../interfaces/aura/IAuraBooster.sol";
import "../../interfaces/aura/IAuraRewarder.sol";
import "../../interfaces/aura/IAuraExtraRewarder.sol";
import "../../libraries/UniversalERC20.sol";

contract PoolEscrow is Initializable {
    using SafeERC20 for IERC20;
    using UniversalERC20 for IERC20;

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev PID of this escrow contract.
    uint256 public pid;

    /// @dev address of the aura pools contract.
    IAuraBooster public auraBooster;

    /// @dev address of the rewarder contract.
    IAuraRewarder public auraRewarder;

    /// @dev address of the lptoken for this escrow.
    IERC20 public lpToken;

    /// @dev The balance for a given token for a given user
    /// e.g userBalance[msg.sender][0x23523...]
    mapping(address => mapping(address => uint256)) public userBalance;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Errors.UNAUTHORIZED();
        }
        _;
    }

    /// @dev Initializes the pool escrow with the given parameters
    /// @param _pid The pool id (The first 16-bits)
    /// @param _wrapper The wrapper contract address
    function initialize(
        uint256 _pid,
        address _wrapper,
        address _auraBooster,
        address _auraRewarder,
        address _lpToken
    ) public payable initializer {
        if (
            _wrapper == address(0) ||
            _auraBooster == address(0) ||
            _auraRewarder == address(0) ||
            _lpToken == address(0)
        ) {
            revert Errors.ZERO_ADDRESS();
        }
        pid = _pid;
        wrapper = _wrapper;
        auraBooster = IAuraBooster(_auraBooster);
        auraRewarder = IAuraRewarder(_auraRewarder);
        lpToken = IERC20(_lpToken);

        lpToken.approve(_wrapper, type(uint256).max);
    }

    /**
     * @notice Transfers tokens to and from a specified address
     * @param _from The address from which the tokens will be transferred
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferTokenFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external virtual onlyWrapper {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    /**
     * @notice Transfers tokens to a specified address
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferToken(
        address _token,
        address _to,
        uint256 _amount
    ) external virtual onlyWrapper {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /**
     * @notice Deposits tokens to pool
     * @param _amount The amount of tokens to be deposited
     */
    function deposit(uint256 _amount) external virtual onlyWrapper {
        IERC20(address(lpToken)).universalApprove(address(auraBooster), _amount);
        auraBooster.deposit(pid, _amount, true);
    }

    /**
     * @notice Withdraws tokens for a given user
     * @param _amount The amount of tokens to be withdrawn
     * @param _user The user to withdraw tokens to
     */
    function withdraw(
        uint256 _amount,
        address _user
    ) external virtual onlyWrapper {
        _withdraw(_amount, _user);
    }

    /**
     * @notice claims rewards and withdraws for a given user
     * @param _amount The amount of tokens to be withdrawn
     * @param _user The user to withdraw tokens to
     */
    function claimAndWithdraw(
        uint256 _amount,
        address _user
    ) external onlyWrapper {
        _claimRewards(_amount);
        _withdraw(_amount, _user);
    }

    /**
     * @notice Claims rewards from the aura rewarder
     * @param _amount The amount of tokens
     */
    function claimRewards(uint256 _amount) external virtual onlyWrapper {
        _claimRewards(_amount);
    }

    /**
     * @notice Gets rewards from the extra aura rewarder
     * @param _extraRewardsAddress the rewards address to gather from
     */
    function getRewardExtra(
        address _extraRewardsAddress
    ) external virtual onlyWrapper {
        IAuraExtraRewarder(_extraRewardsAddress).getReward();
    }

    // INTERNAL FUNCTIONS

    function _withdraw(uint256 _amount, address _user) internal {
        auraBooster.withdraw(pid, _amount);
        IERC20(lpToken).safeTransfer(_user, _amount);
    }

    function _claimRewards(uint256 _amount) internal {
        auraRewarder.withdraw(_amount, true);
    }
}
