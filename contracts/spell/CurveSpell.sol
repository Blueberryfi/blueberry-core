// SPDX-License-Identifier: MIT
/*
██████╗ ██╗     ██╗   ██╗███████╗██████╗ ███████╗██████╗ ██████╗ ██╗   ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝██║     ██║   ██║█████╗  ██████╔╝█████╗  ██████╔╝██████╔╝ ╚████╔╝
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██╔══╝  ██╔══██╗██╔══██╗  ╚██╔╝
██████╔╝███████╗╚██████╔╝███████╗██████╔╝███████╗██║  ██║██║  ██║   ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
*/

pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./BasicSpell.sol";
import "../interfaces/IWCurveGauge.sol";

contract CurveSpell is BasicSpell {
    using SafeCast for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev address of ICHI farm wrapper
    IWCurveGauge public wCurveGauge;
    /// @dev address of curve registry
    ICurveRegistry public registry;
    /// @dev address of ICHI token
    address public CRV;
    /// @dev Mapping from LP token address -> underlying token addresses
    mapping(address => address[]) public ulTokens;
    /// @dev Mapping from LP token address to -> pool address
    mapping(address => address) public poolOf;

    function initialize(
        IBank bank_,
        address werc20_,
        address weth_,
        address wCurveGauge_
    ) external initializer {
        __BasicSpell_init(bank_, werc20_, weth_);

        wCurveGauge = IWCurveGauge(wCurveGauge_);
        CRV = address(wCurveGauge.CRV());
        registry = wCurveGauge.registry();
        wCurveGauge.setApprovalForAll(address(bank_), true);
    }

    /// @dev Return pool address given LP token and update pool info if not exist.
    /// @param lp LP token to find the corresponding pool.
    function getPool(address lp) public returns (address) {
        address pool = poolOf[lp];
        if (pool == address(0)) {
            require(lp != address(0), "no lp token");
            pool = registry.get_pool_from_lp_token(lp);
            require(pool != address(0), "no corresponding pool for lp token");
            poolOf[lp] = pool;
            (uint n, ) = registry.get_n_coins(pool);
            address[8] memory tokens = registry.get_coins(pool);
            ulTokens[lp] = new address[](n);
            for (uint i = 0; i < n; i++) {
                ulTokens[lp][i] = tokens[i];
            }
        }
        return pool;
    }
}
