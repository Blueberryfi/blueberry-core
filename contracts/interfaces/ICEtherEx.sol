pragma solidity ^0.8.9;

import './IERC20Ex.sol';

// Export ICEther interface for mainnet-fork testing.
interface ICEtherEx is IERC20Ex {
    function mint() external payable;
}
