import chai, { assert } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, StableBPTOracle, CoreOracle, WeightedBPTOracle } from '../../typechain-types';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork } from '../helpers';

chai.use(near);
chai.use(roughlyNear);

const OneDay = 86400;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Balancer Stable Pool BPT Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let coreOracle: CoreOracle;
  let stableBPTOracle: StableBPTOracle;
  let weightedOracle: WeightedBPTOracle;

  before(async () => {
    await fork();
    [admin, alice] = await ethers.getSigners();

    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    const chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
      ChainlinkAdapterOracle,
      [admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle.setTimeGap(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.GHO, ADDRESS.WETH, ADDRESS.wstETH],
      [OneDay, OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    await chainlinkAdapterOracle.setPriceFeeds(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.GHO, ADDRESS.WETH, ADDRESS.wstETH],
      [
        ADDRESS.CHAINLINK_USDC_USD_FEED,
        ADDRESS.CHAINLINK_USDT_USD_FEED,
        ADDRESS.CHAINLINK_DAI_USD_FEED,
        ADDRESS.CHAINLINK_GHO_USD_FEED,
        ADDRESS.CHAINLINK_ETH_USD_FEED,
        ADDRESS.CHAINLINK_STETH_USD_FEED,
      ]
    );

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
    await coreOracle.deployed();

    await coreOracle.setRoutes(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.GHO, ADDRESS.wstETH, ADDRESS.WETH],
      [
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
      ]
    );

    const WeightedBPTOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.WeightedBPTOracle);
    weightedOracle = <WeightedBPTOracle>(
      await upgrades.deployProxy(
        WeightedBPTOracleFactory,
        [ADDRESS.BALANCER_VAULT, coreOracle.address, admin.address],
        { unsafeAllow: ['delegatecall'] }
      )
    );

    const StableBPTOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.StableBPTOracle);

    stableBPTOracle = <StableBPTOracle>await upgrades.deployProxy(
      StableBPTOracleFactory,
      [ADDRESS.BALANCER_VAULT, coreOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    await stableBPTOracle.connect(admin).setWeightedPoolOracle(weightedOracle.address);
    await weightedOracle.connect(admin).setStablePoolOracle(stableBPTOracle.address);
  });

  it('Verify Price of a Stable Pool: Balancer USDC-DAI-USDT', async () => {
    const pointNine = ethers.utils.parseEther('0.9');
    const onePointOne = ethers.utils.parseEther('1.1');

    await stableBPTOracle.registerBpt(ADDRESS.BAL_UDU);
    const price = await stableBPTOracle.callStatic.getPrice(ADDRESS.BAL_UDU);

    assert(price.gte(pointNine), 'Price is greater than 0.9');
    assert(price.lte(onePointOne), 'Price is less than 1.1');
  });

  it('Verify Price of Nested Stable Pool: GHO/USDC-DAI-USDT', async () => {
    const pointNine = ethers.utils.parseEther('0.9');
    const onePointOne = ethers.utils.parseEther('1.1');

    await stableBPTOracle.registerBpt(ADDRESS.BAL_GHO_3POOL);
    const price = await stableBPTOracle.callStatic.getPrice(ADDRESS.BAL_GHO_3POOL);

    assert(price.gte(pointNine), 'Price is greater than 0.9');
    assert(price.lte(onePointOne), 'Price is less than 1.1');
  });

  it('Verify Price of Non-USD Stable Pool: Balancer wstETH/WETH', async () => {
    const twoThousand = ethers.utils.parseEther('2000');
    const twoThousandFiveHundred = ethers.utils.parseEther('2500');

    await stableBPTOracle.registerBpt(ADDRESS.BAL_WSTETH_WETH);
    const price = await stableBPTOracle.callStatic.getPrice(ADDRESS.BAL_WSTETH_WETH);

    assert(price > twoThousand, 'Price is greater than 2000');
    assert(price < twoThousandFiveHundred, 'Price is less than 2500');
  });
});
