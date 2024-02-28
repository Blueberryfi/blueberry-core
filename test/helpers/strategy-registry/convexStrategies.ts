import { BigNumber, utils } from "ethers";
import { ADDRESS } from "../../../constant";

export type ConvexStrategy = {
    strategyId: number;
    strategyName: string;
    vaultAddress: string;
    minPosition: BigNumber;
    maxPosition: BigNumber;
    collTokens: string[];
    maxLTVs: number[];
    borrowAssets: string[];
}
  
export const convexStableStrategies: ConvexStrategy[] = [
    {
        strategyId: 0,
        strategyName: 'WSTETH_WETH',
        vaultAddress: ADDRESS.CRV_STETH,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.LINK],
        maxLTVs: [200000, 200000, 120000, 200000, 200000, 140000],
        borrowAssets: [ADDRESS.WETH],
    }
];

export const convexVolativeStrategies: ConvexStrategy[] = [
    {
        strategyId: 0,
        strategyName: 'ALCX_FRAXBP',
        vaultAddress: ADDRESS.CRV_ALCX_FRAXBP,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('488794', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.LINK],
        maxLTVs: [20000, 20000, 20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.ALCX],
    },
    {
        strategyId: 1,
        strategyName: 'OHM_FRAXBP',
        vaultAddress: ADDRESS.CRV_OHM_FRAXBP,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('488794', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.LINK],
        maxLTVs: [20000, 20000, 20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.OHM],
    }
]

export const convexTricryptoStrategies: ConvexStrategy[] = [
    {
        strategyId: 0,
        strategyName: 'TricryptoUSDC',
        vaultAddress: ADDRESS.CRV_TricryptoUSDC,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH],
    }
]