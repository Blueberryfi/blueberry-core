import { ethers, upgrades } from 'hardhat';
import { utils } from 'ethers';
import { WERC20, PendleSpell} from '../../../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../../../constant';
import { StrategyInfo, setupBasicBank } from '../utils';

type PendleStrategy = {
    ptAddress: string;
    market: string;
    borrowAssets: string[];
    collateralAssets: string[];
    maxLtv: number;
    maxStrategyBorrow: number;
}


export const strategies: PendleStrategy[] = [
  {
    ptAddress: ADDRESS.PENDLE_AUSDT_PT,
    market: ADDRESS.PENDLE_AUSDT_MARKET,
    borrowAssets: [ADDRESS.USDC, ADDRESS.DAI],
    collateralAssets: [ADDRESS.DAI, ADDRESS.USDC],
    maxLtv: 2500,
    maxStrategyBorrow: 5_000_000,
  },
];

export const setupStrategy = async () => {
  const [admin] = await ethers.getSigners();
  const protocol = await setupBasicBank();
  console.log('bank setup');

  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  const werc20 = <WERC20>await upgrades.deployProxy(WERC20, [admin.address], { unsafeAllow: ['delegatecall'] });

  const PendleSpell = await ethers.getContractFactory(CONTRACT_NAMES.PendleSpell);
  const pendleSpell = <PendleSpell>(
    await upgrades.deployProxy(
      PendleSpell,
      [
        protocol.bank.address,
        werc20.address,
        ADDRESS.WETH,
        ADDRESS.PENDLE_ROUTER,
        ADDRESS.AUGUSTUS_SWAPPER,
        ADDRESS.TOKEN_TRANSFER_PROXY,
        admin.address,
      ],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  // Setup Bank
  await protocol.bank.whitelistSpells([pendleSpell.address], [true]);
  await protocol.bank.whitelistERC1155([werc20.address], true);

  for (let i = 0; i < strategies.length; i += 1) {
    const strategy = strategies[i];

    await pendleSpell.addStrategy(strategy.ptAddress, strategy.market,utils.parseUnits('100', 18), utils.parseUnits('2000000', 18));

    await pendleSpell.setCollateralsMaxLTVs(
      i,
      strategy.collateralAssets,
      strategy.collateralAssets.map(() => (strategy.maxLtv * 10000) / 100)
    );
  }

  return {
    protocol,
    pendleSpell,
    werc20,
  };
};
