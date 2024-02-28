import { BigNumber, utils } from "ethers";
import { ADDRESS } from "../../../constant";

export type IchiStrategy = {
    strategyId: number;
    strategyName: string;
    vaultAddress: string;
    minPosition: BigNumber;
    maxPosition: BigNumber;
    collTokens: string[];
    maxLTVs: number[];
    borrowAsset: string;
}
  
export const ichiStrategies: IchiStrategy[] = [
    {
        strategyId: 0,
        strategyName: 'ICHI_VAULT_ALCX_ETH',
        vaultAddress: ADDRESS.ICHI_VAULT_ALCX_ETH,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('488794', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 20000, 20000],
        borrowAsset: ADDRESS.ALCX,
    },
    {
        strategyId: 1,
        strategyName: 'ICHI_VAULT_ALCX_ETH',
        vaultAddress: ADDRESS.ICHI_VAULT_ALCX_USDC,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('488794', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 20000, 20000],
        borrowAsset: ADDRESS.ALCX,
    },
    {
        strategyId: 2,
        strategyName: 'ICHI_VAULT_USDC_ALCX',
        vaultAddress: ADDRESS.ICHI_VAULT_USDC_ALCX,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('488794', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 20000, 20000],
        borrowAsset: ADDRESS.USDC,
    },
    {
        strategyId: 3,
        strategyName: 'ICHI_VAULT_ETH_USDC',
        vaultAddress: ADDRESS.ICHI_VAULT_ETH_USDC,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [20000, 20000, 40000, 50000],
        borrowAsset: ADDRESS.WETH,
    },
    {
        strategyId: 4,
        strategyName: 'ICHI_VAULT_USDC_ETH',
        vaultAddress: ADDRESS.ICHI_VAULT_USDC_ETH,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH],
        maxLTVs: [30000, 30000, 20000, 20000],
        borrowAsset: ADDRESS.USDC,
    },
    {
        strategyId: 5,
        strategyName: 'ICHI_VAULT_WBTC_USDC',
        vaultAddress: ADDRESS.ICHI_VAULT_WBTC_USDC,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.WBTC],
        maxLTVs: [20000, 20000, 20000, 20000, 40000],
        borrowAsset: ADDRESS.WBTC,
    },
    {
        strategyId: 6,
        strategyName: 'ICHI_VAULT_USDC_WBTC',
        vaultAddress: ADDRESS.ICHI_VAULT_USDC_WBTC,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.WBTC],
        maxLTVs: [40000, 40000, 20000, 20000, 20000],
        borrowAsset: ADDRESS.USDC,
    },
    {
        strategyId: 7,
        strategyName: 'ICHI_VAULT_WBTC_ETH',
        vaultAddress: ADDRESS.ICHI_VAULT_WBTC_ETH,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.WBTC],
        maxLTVs: [20000, 20000, 20000, 20000, 40000],
        borrowAsset: ADDRESS.WBTC,
    },
    {
        strategyId: 8,
        strategyName: 'ICHI_VAULT_ETH_WBTC',
        vaultAddress: ADDRESS.ICHI_VAULT_ETH_WBTC,
        minPosition: utils.parseUnits('4000', 18),
        maxPosition: utils.parseUnits('750000', 18),
        collTokens: [ADDRESS.DAI, ADDRESS.USDC, ADDRESS.WETH, ADDRESS.wstETH, ADDRESS.WBTC],
        maxLTVs: [20000, 20000, 20000, 40000, 20000],
        borrowAsset: ADDRESS.WETH,
    },
];