import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { utils } from "ethers/lib/ethers";
import { BErc20Delegator, ERC20, HardVault, SoftVault } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

type MarketInfo = {
    underlyingName: string;
    underlyingAddress: string;
    isUnderlyingStable: boolean;
    isMinorInterestRateModel: boolean;
    bTokenName: string;
    bTokenSymbol: string;
}

export const bUSDC: MarketInfo = {
    underlyingName: 'USDC',
    underlyingAddress: ADDRESS.USDC,
    isUnderlyingStable: true,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry USDC',
    bTokenSymbol: 'bUSDC'
};

export const bDAI: MarketInfo = {
    underlyingName: 'DAI',
    underlyingAddress: ADDRESS.DAI,
    isUnderlyingStable: true,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry DAI',
    bTokenSymbol: 'bDAI'
}

export const bWETH: MarketInfo = {
    underlyingName: 'WETH',
    underlyingAddress: ADDRESS.WETH,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry WETH',
    bTokenSymbol: 'bWETH'
}

export const bWBTC: MarketInfo = {
    underlyingName: 'WBTC',
    underlyingAddress: ADDRESS.WBTC,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry WBTC',
    bTokenSymbol: 'bWBTC'
}

export const bCRV: MarketInfo = {
    underlyingName: 'CRV',
    underlyingAddress: ADDRESS.CRV,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry CRV',
    bTokenSymbol: 'bCRV'
}

export const bCrvUSD: MarketInfo = {
    underlyingName: 'CrvUSD',
    underlyingAddress: ADDRESS.CRVUSD,
    isUnderlyingStable: true,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry CrvUSD',
    bTokenSymbol: 'bCrvUSD'
}

export const bFRAX: MarketInfo = {
    underlyingName: 'FRAX',
    underlyingAddress: ADDRESS.FRAX,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry FRAX',
    bTokenSymbol: 'bFRAX'
}

export const bLINK: MarketInfo = {
    underlyingName: 'LINK',
    underlyingAddress: ADDRESS.LINK,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry LINK',
    bTokenSymbol: 'bLINK'
}

export const bOHM: MarketInfo = {
    underlyingName: 'OHM',
    underlyingAddress: ADDRESS.OHM,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry OHM',
    bTokenSymbol: 'bOHM'
}

export const bALCX: MarketInfo = {
    underlyingName: 'ALCX',
    underlyingAddress: ADDRESS.ALCX,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry ALCX',
    bTokenSymbol: 'bALCX'
}

export const bBAL: MarketInfo = {
    underlyingName: 'BAL',
    underlyingAddress: ADDRESS.BAL,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry BAL',
    bTokenSymbol: 'bBAL'
}

export const wstETH: MarketInfo = {
    underlyingName: 'wstETH',
    underlyingAddress: ADDRESS.wstETH,
    isUnderlyingStable: false,
    isMinorInterestRateModel: false,
    bTokenName: 'Blueberry wstETH',
    bTokenSymbol: 'wstETH'
}

export const blueberryMarkets: MarketInfo[] = [
    bUSDC,
    bDAI,
    bWETH,
    bWBTC,
    bCRV,
    bCrvUSD,
    bFRAX,
    bLINK,
    bOHM,
    bALCX,
    bBAL,
    wstETH
]

export const getMarketInfo = async (bToken: BErc20Delegator): Promise<MarketInfo> => {
    let underlyingAddress = await bToken.underlying();
    let marketInfo: MarketInfo | undefined = blueberryMarkets.find((market) => market.underlyingAddress === underlyingAddress);

    if (marketInfo === undefined) {
        throw new Error(`Market info for ${bToken.symbol} not found`);
    }
    return marketInfo;
}

export const deploySoftVaults = async (config: any, bank: any, comptroller: any, bTokens: BErc20Delegator[], admin: any, user: SignerWithAddress): Promise<SoftVault[]> => {
    let softVaults: SoftVault[] = [];
    const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
    const hardVault = <HardVault>await upgrades.deployProxy(HardVault, [config.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    
    const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);

    for (let i = 0; i < bTokens.length; i++) {
        let bToken: BErc20Delegator = bTokens[i];
        let bTokenInfo = await getMarketInfo(bToken);
        if (await bank.isTokenWhitelisted(bTokenInfo.underlyingAddress) != true) {
            continue;
        }

        let softVault = <SoftVault>await upgrades.deployProxy(
            SoftVault,
            [config.address, bToken.address, `Interest Bearing ${bTokenInfo.underlyingName}`, `ib${bTokenInfo.underlyingName}`, admin.address],
            {
                unsafeAllow: ['delegatecall'],
            }
        );
        await softVault.deployed();

        let liqThreshold = bTokenInfo.isUnderlyingStable ? 9000 : 8500;
        await bank.addBank(bTokenInfo.underlyingAddress, softVault.address, hardVault.address, liqThreshold);
        await comptroller._setCreditLimit(bank.address, bToken.address, utils.parseUnits('3000000'));

        const UnderlyingToken: ERC20 = await ethers.getContractAt('ERC20', bTokenInfo.underlyingAddress); 
        
        await UnderlyingToken.approve(softVault.address, ethers.constants.MaxUint256);
        await softVault.deposit(utils.parseUnits('50', await UnderlyingToken.decimals()));

        const amount = await UnderlyingToken.balanceOf(admin.address);
        await UnderlyingToken.transfer(user.address, amount);

        softVaults.push(softVault);
    }
    return softVaults;
}

export const getSoftVault = async (softVaults: SoftVault[], underlyingToken: string): Promise<SoftVault> => {
    let softVault = softVaults.find(async (softVaults) => await softVaults.getUnderlyingToken() === underlyingToken);
    if (softVault === undefined) {
        throw new Error(`SoftVault for ${underlyingToken} not found`);
    }
    return softVault;
}

export const getBToken = async (bTokens: BErc20Delegator[], underlyingToken: string): Promise<BErc20Delegator> => {
    for (let i = 0; i < bTokens.length; i++) {
        let bToken: BErc20Delegator = bTokens[i];
        let bTokenInfo = await getMarketInfo(bToken);
        if (bTokenInfo.underlyingAddress === underlyingToken) {
            return bToken;
        }
    }
    throw new Error(`bToken for ${underlyingToken} not found`);
}
