import chai, { assert } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, CoreOracle, PendlePtOracle } from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fork } from '../helpers';

chai.use(roughlyNear);

const OneDay = 86400;

describe('Pendle Pt Oracle', () => {
  let admin: SignerWithAddress;
  let pendlePtOracle: PendlePtOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  beforeEach(async () => {
    await fork(1, 20136893);
    [admin] = await ethers.getSigners();

    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
      ChainlinkAdapterOracle,
      [admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle.setTimeGap(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.WETH, ADDRESS.BAL, ADDRESS.ezETH, ADDRESS.ETH, ADDRESS.USDe],
      [OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    await chainlinkAdapterOracle.setPriceFeeds(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.BAL, ADDRESS.WETH, ADDRESS.ezETH, ADDRESS.ETH, ADDRESS.USDe],
      [
        ADDRESS.CHAINLINK_USDC_USD_FEED,
        ADDRESS.CHAINLINK_USDT_USD_FEED,
        ADDRESS.CHAINLINK_DAI_USD_FEED,
        ADDRESS.CHAINLINK_BAL_USD_FEED,
        ADDRESS.CHAINLINK_ETH_USD_FEED,
        ADDRESS.REDSTONE_EZETH_ETH_FEED,
        ADDRESS.CHAINLINK_ETH_USD_FEED,
        ADDRESS.REDSTONE_USDE_USD_FEED,
      ]
    );

    await chainlinkAdapterOracle.setEthDenominatedToken(ADDRESS.ezETH, true);

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });

    const PendlePtOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.PendlePtOracle);
    pendlePtOracle = <PendlePtOracle>(
      await upgrades.deployProxy(
        PendlePtOracleFactory,
        [ADDRESS.PENDLE_PY_YT_LP_ORACLE, coreOracle.address, admin.address],
        { unsafeAllow: ['delegatecall'] }
      )
    );

    await pendlePtOracle.deployed();

    await coreOracle.setRoutes(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.BAL, ADDRESS.WETH, ADDRESS.ezETH, ADDRESS.ETH, ADDRESS.USDe],
      [
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
      ]
    );
  });

  it('Verify Price of rstETH PT', async () => {
    const ptToEzETH = ethers.utils.parseEther('.9711');
    const ezETHPrice = ethers.utils.parseEther('3518');
    const ptToUSDLowerBound = ptToEzETH.mul(ezETHPrice).div(ethers.utils.parseEther('1.05'));
    const ptToUSDUpperBound = ptToEzETH.mul(ezETHPrice).div(ethers.utils.parseEther('0.95'));

    await pendlePtOracle.connect(admin).registerMarket(ADDRESS.PENDLE_EZETH_MARKET, 1800, true, true);

    const price = await pendlePtOracle.callStatic.getPrice(ADDRESS.PENDLE_EZETH_PT);

    assert.isTrue(price.gt(ptToUSDLowerBound), 'price should be greater than lower bound');
    assert.isTrue(price.lt(ptToUSDUpperBound), 'price should be less than upper bound');
  });

  it('Verify Price of USDe PT', async () => {
    const ptToUsde = ethers.utils.parseEther('.9792');
    const usdePrice = ethers.utils.parseEther('1');
    const ptToUSDLowerBound = ptToUsde.mul(usdePrice).div(ethers.utils.parseEther('1.05'));
    const ptToUSDUpperBound = ptToUsde.mul(usdePrice).div(ethers.utils.parseEther('0.95'));

    await pendlePtOracle.connect(admin).registerMarket(ADDRESS.PENDLE_USDE_MARKET, 1800, true, true);

    const price = await pendlePtOracle.callStatic.getPrice(ADDRESS.PENDLE_USDE_PT);

    assert.isTrue(price.gt(ptToUSDLowerBound), 'price should be greater than lower bound');
    assert.isTrue(price.lt(ptToUSDUpperBound), 'price should be less than upper bound');
  });

  it('Verify Price of aUSDC PT', async () => {
    const ptToUsde = ethers.utils.parseEther('0.9768');
    const usdtPrice = ethers.utils.parseEther('1');
    const ptToUSDLowerBound = ptToUsde.mul(usdtPrice).div(ethers.utils.parseEther('1.05'));
    const ptToUSDUpperBound = ptToUsde.mul(usdtPrice).div(ethers.utils.parseEther('0.95'));

    await pendlePtOracle.connect(admin).registerMarket(ADDRESS.PENDLE_AUSDT_MARKET, 1800, true, false);

    const price = await pendlePtOracle.callStatic.getPrice(ADDRESS.PENDLE_AUSDT_PT);

    assert.isTrue(price.gt(ptToUSDLowerBound), 'price should be greater than lower bound');
    assert.isTrue(price.lt(ptToUSDUpperBound), 'price should be less than upper bound');
  });
});
