import { BigNumber, utils } from "ethers";
import { ADDRESS } from "../../../constant";

export type ShortLongStrategy = {
    strategyId: number;
    strategyName: string;
    minPosition: BigNumber;
    maxPosition: BigNumber;
    collTokens: string[];
    maxLTVs: number[];
    borrowAssets: string[];
    softVaultUnderlying: string;
}
  
export const shortLongStrategies: ShortLongStrategy[] = [
    {
        strategyId: 0,
        strategyName: 'WSTETH_Long',
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.DAI],
        softVaultUnderlying: ADDRESS.wstETH,
    },
    {
        strategyId: 1,
        strategyName: 'WETH_WBTC_LINK_Short',
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.WETH, ADDRESS.WBTC, ADDRESS.LINK],  // Swapping to DAI to short one of these 3 assets
        softVaultUnderlying: ADDRESS.DAI,
    },
    {
        strategyId: 2,
        strategyName: 'WBTC_Long',
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH],
        maxLTVs: [20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.DAI],
        softVaultUnderlying: ADDRESS.WBTC,
    },
    {
        strategyId: 3,
        strategyName: 'LINK_Long',
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WBTC, ADDRESS.WETH],
        maxLTVs: [20000, 20000, 20000, 20000],
        borrowAssets: [ADDRESS.DAI],
        softVaultUnderlying: ADDRESS.LINK,
    },
]; 