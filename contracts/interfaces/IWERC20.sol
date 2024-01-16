// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
/* solhint-enable max-line-length */

import { IERC20Wrapper } from "./IERC20Wrapper.sol";

/**
 * @title IWERC20
 * @author This interface defines the functionality of the Wrapped ERC20 (WERC20) token.
 * @notice WERC20 tokens enable ERC20 tokens to be represented
 *         as ERC1155 tokens, providing batch transfer capabilities and more.
 */
interface IWERC20 is IERC1155Upgradeable, IERC20Wrapper {
    /// @notice Emitted when a token is minted.
    event Minted(uint256 indexed id, uint256 amount);

    /// @notice Emitted when a token is burned.
    event Burned(uint256 indexed id, uint256 amount);

    /**
     * @notice Fetches the balance of the underlying ERC20 token for a specific user.
     * @param token The ERC20 token address.
     * @param user The user's address.
     * @return The user's balance of the specified ERC20 token.
     */
    function balanceOfERC20(address token, address user) external view returns (uint256);

    /**
     * @notice Allows users to wrap their ERC20 tokens into the corresponding ERC1155 tokenId.
     * @param token The address of the ERC20 token to wrap.
     * @param amount The amount of the ERC20 token to wrap.
     * @return id The tokenId of the wrapped ERC20 token.
     */
    function mint(address token, uint256 amount) external returns (uint256 id);

    /**
     * @notice Allows users to burn their ERC1155 token to retrieve the original ERC20 tokens.
     * @param token The address of the ERC20 token to unwrap.
     * @param amount The amount of the ERC20 token to unwrap.
     */
    function burn(address token, uint256 amount) external;
}
