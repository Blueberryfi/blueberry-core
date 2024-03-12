// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Addresses } from "@test/Addresses.t.sol";

struct ShortLongStrategy {
    uint256 strategyId;
    string strategyName;
    uint256 minPosition;
    uint256 maxPosition;
    address[] collTokens;
    uint256[] maxLTVs;
    address[] borrowAssets;
    address softVaultUnderlying;
}

contract ShortLongStrategies is Addresses {
    ShortLongStrategy[] public strategies;
    constructor() {
        address[] memory collTokens = new address[](5);
        collTokens[0] = DAI;
        collTokens[1] = USDC;
        collTokens[2] = WBTC;
        collTokens[3] = WETH_ADDRESS;
        collTokens[4] = WSTETH;

        uint256[] memory maxLTVs = new uint256[](5);
        maxLTVs[0] = 20000;
        maxLTVs[1] = 20000;
        maxLTVs[2] = 20000;
        maxLTVs[3] = 20000;
        maxLTVs[4] = 20000;

        address[] memory borrowAssets = new address[](1);
        borrowAssets[0] = DAI;

        strategies.push(
            ShortLongStrategy({
                strategyId: 4,
                strategyName: "WSTETH_Long",
                minPosition: 4000e18,
                maxPosition: 750000e18,
                collTokens: collTokens,
                maxLTVs: maxLTVs,
                borrowAssets: borrowAssets,
                softVaultUnderlying: WSTETH
            })
        );

        borrowAssets = new address[](3);
        borrowAssets[0] = WETH_ADDRESS;
        borrowAssets[1] = WBTC;
        borrowAssets[2] = LINK;

        strategies.push(
            ShortLongStrategy({
                strategyId: 5,
                strategyName: "WETH_WBTC_LINK_Short",
                minPosition: 4000e18,
                maxPosition: 750000e18,
                collTokens: collTokens,
                maxLTVs: maxLTVs,
                borrowAssets: borrowAssets,
                softVaultUnderlying: DAI
            })
        );

        collTokens = new address[](4);
        collTokens[0] = DAI;
        collTokens[1] = USDC;
        collTokens[2] = WBTC;
        collTokens[3] = WETH_ADDRESS;

        maxLTVs = new uint256[](4);
        maxLTVs[0] = 20000;
        maxLTVs[1] = 20000;
        maxLTVs[2] = 20000;
        maxLTVs[3] = 20000;

        strategies.push(
            ShortLongStrategy({
                strategyId: 6,
                strategyName: "WBTC_Long",
                minPosition: 4000e18,
                maxPosition: 750000e18,
                collTokens: collTokens,
                maxLTVs: maxLTVs,
                borrowAssets: borrowAssets,
                softVaultUnderlying: WBTC
            })
        );

        strategies.push(
            ShortLongStrategy({
                strategyId: 7,
                strategyName: "LINK_Long",
                minPosition: 4000e18,
                maxPosition: 750000e18,
                collTokens: collTokens,
                maxLTVs: maxLTVs,
                borrowAssets: borrowAssets,
                softVaultUnderlying: LINK
            })
        );
    }
}
