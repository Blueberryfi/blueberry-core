import { ethers, upgrades } from 'hardhat';
import { utils } from 'ethers';
import { WERC20, PendleSpell, PendlePtOracle } from '../../../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../../../constant';
import { setupBasicBank } from '../utils';

export type PendleStrategy = {
  ptAddress: string;
  market: string;
  borrowAssets: string[];
  collateralAssets: string[];
  maxLtv: number;
  maxStrategyBorrow: number;
  isSyTradeable: boolean;
  unitOfPrice: string;
  unitOfPriceOracle: string;
  isPricedInUSD: boolean;
};

export const strategies: PendleStrategy[] = [
  {
    ptAddress: ADDRESS.PENDLE_APXETH_PT,
    market: ADDRESS.PENDLE_APXETH_MARKET,
    borrowAssets: [ADDRESS.WETH],
    collateralAssets: [ADDRESS.WETH],
    maxLtv: 2500,
    maxStrategyBorrow: 5_000_000,
    isSyTradeable: true,
    unitOfPrice: ADDRESS.apxETH,
    unitOfPriceOracle: ADDRESS.REDSTONE_APXETH_ETH_FEED,
    isPricedInUSD: false,
  },
  {
    ptAddress: ADDRESS.PENDLE_SDAI_PT,
    market: ADDRESS.PENDLE_SDAI_MARKET,
    borrowAssets: [ADDRESS.USDC],
    collateralAssets: [ADDRESS.USDC],
    maxLtv: 2500,
    maxStrategyBorrow: 5_000_000,
    isSyTradeable: false,
    unitOfPrice: ADDRESS.DAI,
    unitOfPriceOracle: ADDRESS.CHAINLINK_DAI_USD_FEED,
    isPricedInUSD: true,
  },
  {
    ptAddress: ADDRESS.PENDLE_EETH_PT,
    market: ADDRESS.PENDLE_EETH_MARKET,
    borrowAssets: [ADDRESS.WETH],
    collateralAssets: [ADDRESS.WETH],
    maxLtv: 2500,
    maxStrategyBorrow: 5_000_000,
    isSyTradeable: true,
    unitOfPrice: ADDRESS.WETH,
    unitOfPriceOracle: ADDRESS.CHAINLINK_ETH_USD_FEED,
    isPricedInUSD: true,
  },
];

export const setupStrategy = async () => {
  const [admin] = await ethers.getSigners();
  const protocol = await setupBasicBank();

  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  const werc20 = <WERC20>await upgrades.deployProxy(WERC20, [admin.address], { unsafeAllow: ['delegatecall'] });

  const chainlinkAdapterOracleAddr = await protocol.oracle.getRoute(ADDRESS.USDC);
  const chainlinkAdapterOracle = await ethers.getContractAt('ChainlinkAdapterOracle', chainlinkAdapterOracleAddr);

  const PendlePtOracle = await ethers.getContractFactory(CONTRACT_NAMES.PendlePtOracle);
  const pendlePtOracle = <PendlePtOracle>(
    await upgrades.deployProxy(
      PendlePtOracle,
      [ADDRESS.PENDLE_PY_YT_LP_ORACLE, protocol.oracle.address, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

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

    await chainlinkAdapterOracle.setPriceFeeds([strategy.unitOfPrice], [strategy.unitOfPriceOracle]);
    await chainlinkAdapterOracle.setTimeGap([strategy.unitOfPrice], [86400]);

    if (!strategy.isPricedInUSD) {
      await chainlinkAdapterOracle.setEthDenominatedToken(strategy.unitOfPrice, true);
    }

    await protocol.oracle.setRoutes([strategy.unitOfPrice], [chainlinkAdapterOracle.address]);

    await pendlePtOracle.registerMarket(strategy.market, strategy.unitOfPrice, 900, true, strategy.isSyTradeable);
    await protocol.oracle.setRoutes(
      [strategy.ptAddress, strategy.unitOfPrice],
      [pendlePtOracle.address, chainlinkAdapterOracleAddr]
    );

    await pendleSpell.addStrategy(
      strategy.ptAddress,
      strategy.market,
      utils.parseUnits('100', 18),
      utils.parseUnits('2000000', 18)
    );

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
    strategies,
  };
};
