import { ethers } from 'hardhat';
import { deployBTokens } from '../helpers/money-market';
import { fork } from '../helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BErc20Delegator, Comptroller, PriceOracleProxyUSD } from '../../typechain-types';
import { expect } from 'chai';
import { utils } from 'ethers';

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Money Market Oracle', async () => {
  let admin: SignerWithAddress;
  let comptroller: Comptroller;

  let bWETH: BErc20Delegator;
  let bUSDC: BErc20Delegator;
  let bWBTC: BErc20Delegator;
  let bOHM: BErc20Delegator;
  let oracle: PriceOracleProxyUSD;

  const USDC_DECIMALS = 6;
  const WBTC_DECIMALS = 8;
  const OHM_DECIMALS = 9;
  const WETH_DECIMALS = 18;

  before(async () => {
    await fork(1, 19763043);
    [admin] = await ethers.getSigners();

    const market = await deployBTokens(admin.address);

    comptroller = market.comptroller;
    bWETH = market.bWETH;
    bUSDC = market.bUSDC;
    bWBTC = market.bWBTC;
    bOHM = market.bOHM;

    oracle = await ethers.getContractAt('PriceOracleProxyUSD', await comptroller.oracle());
  });

  it('properly prices USDC | 6 decimals', async () => {
    const lowerBound = utils.parseUnits('.99', moneyMarketScaler(USDC_DECIMALS));
    const upperBound = utils.parseUnits('1.01', moneyMarketScaler(USDC_DECIMALS));

    const price = await oracle.getUnderlyingPrice(bUSDC.address);

    expect(price).to.be.greaterThan(lowerBound);
    expect(price).to.be.lessThan(upperBound);
  });

  it('properly prices WBTC | 8 decimals', async () => {
    const lowerBound = utils.parseUnits('62000', moneyMarketScaler(WBTC_DECIMALS));
    const upperBound = utils.parseUnits('63000', moneyMarketScaler(WBTC_DECIMALS));

    const price = await oracle.getUnderlyingPrice(bWBTC.address);

    expect(price).to.be.greaterThan(lowerBound);
    expect(price).to.be.lessThan(upperBound);
  });

  it('properly prices OHM | 9 decimals', async () => {
    const lowerBound = utils.parseUnits('12', moneyMarketScaler(OHM_DECIMALS));
    const upperBound = utils.parseUnits('13', moneyMarketScaler(OHM_DECIMALS));

    const price = await oracle.getUnderlyingPrice(bOHM.address);

    expect(price).to.be.greaterThan(lowerBound);
    expect(price).to.be.lessThan(upperBound);
  });

  it('properly prices WETH | 18 decimals', async () => {
    const lowerBound = utils.parseUnits('3100', moneyMarketScaler(WETH_DECIMALS));
    const upperBound = utils.parseUnits('3300', moneyMarketScaler(WETH_DECIMALS));

    const price = await oracle.getUnderlyingPrice(bWETH.address);

    expect(price).to.be.greaterThan(lowerBound);
    expect(price).to.be.lessThan(upperBound);
  });
});

function moneyMarketScaler(decimals: number): number {
  return 18 + 18 - decimals;
}
