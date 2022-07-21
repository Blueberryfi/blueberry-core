pragma solidity ^0.8.9;

interface IERC20WrapperOld {
    /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
    function getUnderlying(uint256 id) external view returns (address);
}
