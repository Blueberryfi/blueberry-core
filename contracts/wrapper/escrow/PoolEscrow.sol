// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../../interfaces/aura/IAuraPools.sol";
import "../../interfaces/aura/IAuraRewarder.sol";
import "../../utils/EnsureApprove.sol";

contract PoolEscrow is Initializable, EnsureApprove {
    using SafeERC20 for IERC20;

    /// @dev The caller is not authorized to call the function.
    error Unauthorized();

    /// @dev Address cannot be zero.
    error AddressZero();

    /// @dev Address of the wrapper contract.
    address public wrapper;

    /// @dev PID of this escrow contract.
    uint256 public pid;

    /// @dev address of the aura pools contract.
    IAuraPools public auraPools;

    IAuraRewarder public auraRewarder;

    IERC20 public lpToken;

    /// @dev The balance for a given token for a given user
    /// e.g userBalance[msg.sender][0x23523...]
    mapping(address => mapping(address => uint256)) public userBalance;

    /// @dev Ensures caller is the wrapper contract.
    modifier onlyWrapper() {
        if (msg.sender != wrapper) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Initializes the pool escrow with the given PID.
    /// @param _pid The pool id (The first 16-bits)
    /// @param _wrapper The wrapper contract address
    function initialize(
        uint256 _pid,
        address _wrapper,
        address _auraPools,
        address _auraRewarder,
        address _lpToken
    ) public payable initializer {
        if (
            _wrapper == address(0) ||
            _auraPools == address(0) ||
            _auraRewarder == address(0) ||
            _lpToken == address(0)
        ) {
            revert AddressZero();
        }
        pid = _pid;
        wrapper = _wrapper;
        auraPools = IAuraPools(_auraPools);
        lpToken = IERC20(_lpToken);

        lpToken.approve(_wrapper, type(uint256).max);
    }

    /**
     * @notice Transfers tokens to a specified address
     * @param _from The address from which the tokens will be transferred
     * @param _to The address to which the tokens will be transferred
     * @param _amount The amount of tokens to be transferred
     */
    function transferTokenFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external virtual onlyWrapper {
        if (_amount > 0) {
            IERC20(lpToken).safeTransferFrom(_from, _to, _amount);
        }
    }

    /**
     * @notice Deposits tokens to aura pool
     * @param _amount The amount of tokens to be deposited
     */
    function deposit(uint256 _amount) external virtual onlyWrapper {
        _ensureApprove(address(lpToken), address(auraPools), _amount);
        auraPools.deposit(pid, _amount, true);
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

    // INTERNAL FUNCTIONS

    function _withdraw(uint256 _amount, address _user) internal {
        auraPools.withdraw(pid, _amount);
        IERC20(lpToken).safeTransfer(_user, _amount);
    }

    function _claimRewards(uint256 _amount) internal {
        auraRewarder.withdraw(_amount, true);
    }
}
