import { BigNumber, utils } from "ethers";
import { ADDRESS } from "../../../constant";

export type AuraStrategy = {
    strategyId: number;
    strategyName: string;
    vaultAddress: string;
    minPosition: BigNumber;
    maxPosition: BigNumber;
    collTokens: string[];
    maxLTVs: number[];
    borrowAsset: string;
}
  
export const auraStrategies: AuraStrategy[] = [
    {
        strategyId: 0,
        strategyName: 'WETH_RETH',
        vaultAddress: ADDRESS.BAL_WETH_RETH_STABLE,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.LINK],
        maxLTVs: [200000, 200000, 160000, 160000, 120000],
        borrowAsset: ADDRESS.WETH,
    },
    {
        strategyId: 1,
        strategyName: 'ALCX_WETH',
        vaultAddress: ADDRESS.BAL_ALCX_WETH_8020,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('488794', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH],
        maxLTVs: [20000, 20000, 20000, 20000],
        borrowAsset: ADDRESS.ALCX,
    },
];