// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/* solhint-disable max-line-length */

import { Test } from "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { console2 } from "forge-std/console2.sol";

contract ParaSwapSnapshot is Test {
    mapping(uint256 blockNumber => mapping(address fromToken => mapping(address toToken => mapping(uint256 amount => mapping(address userAddr => mapping(uint256 maxImpact => bytes swapData))))))
        public snapshots;

    constructor() {
        snapshots[19_330_000][0x6B175474E89094C44Da98b954EedeAC495271d0F][0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0][
            5000000000000000000000
        ][0x55d206c1A11F4b2f60459e88B5c601A4E1Cd41a5][
            100
        ] = hex"0b86a4c10000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000010f0cf064dd592000000000000000000000000000000000000000000000000000000248608b4489d5f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000001000000000000000000004de4c5578194d457dcce3f272538d1ad52c68d1ce849";
    }

    /// @notice Get paraswap data
    ///         The Paraswap SDK fetches the best route from its API at the current block, which makes the fork tests not 100% reproductible.
    ///         This function loads results from `snapshot` if available, otherwise calls paraswap.ts
    /// @dev Using paraswap.ts and `vm.ffi` to get paraswap data with the Node.js SDK
    function _getParaswapData(
        address fromToken,
        address toToken,
        uint256 amount,
        address userAddr,
        uint256 maxImpact
    ) internal returns (bytes memory) {
        if (snapshots[block.number][fromToken][toToken][amount][userAddr][maxImpact].length > 0) {
            return snapshots[block.number][fromToken][toToken][amount][userAddr][maxImpact];
        }

        string[] memory inputs = new string[](8);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./script/paraswap.ts";
        inputs[3] = Strings.toHexString(fromToken);
        inputs[4] = Strings.toHexString(toToken);
        inputs[5] = Strings.toString(amount);
        inputs[6] = Strings.toHexString(userAddr);
        inputs[7] = Strings.toString(maxImpact);

        bytes memory res = vm.ffi(inputs);
        return res;
    }
}
