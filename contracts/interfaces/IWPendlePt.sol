// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/* solhint-disable max-line-length */
import { IERC1155Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
/* solhint-enable max-line-length */

interface IWPendlePt is IERC1155Upgradeable {

    /**
     * @notice Swaps the borrow token to PT token and mints the wrapped Pendle PT.
     * @param market The market address that the wrapped Pendle PT is minted from.
     * @param amount The amount of PT that we are minting and wrapping.
     * @param data Encoded data for facilitating the opening of a PT position.
     * @return id The tokenId of the wrapped Pendle PT.
     * @return ptAmount The amount of PT tokens minted.
     */
    function mint(address market, uint256 amount, bytes memory data) external returns (uint256 id, uint256 ptAmount);

    /**
     *
     * @param id The tokenId of the wrapped Pendle PT.
     * @param amount The amount of ERC1155 tokens to burn.
     * @param data Encoded data for facilitating the closing of a PT position.
     * @return amountOut The amount of output tokens returned to the user.
     */
    function burn(uint256 id, uint256 amount, bytes memory data) external returns (uint256 amountOut);

    /**
     * @notice Fetches the market address of the wrapped Pendle PT.
     * @param id The tokenId of the wrapped Pendle PT.
     */
    function getMarket(uint256 id) external returns (address market);
}
