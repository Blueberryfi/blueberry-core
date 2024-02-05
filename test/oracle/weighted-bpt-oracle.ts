import chai, { assert } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, CoreOracle, StableBPTOracle, WeightedBPTOracle } from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fork } from '../helpers';

chai.use(roughlyNear);

const OneDay = 86400;

describe('Balancer Weighted Pool BPT Oracle', () => {
  let admin: SignerWithAddress;
  let weightedOracle: WeightedBPTOracle;
  let stableOracle: StableBPTOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  beforeEach(async () => {
    await fork();
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
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.WETH, ADDRESS.BAL],
      [OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    await chainlinkAdapterOracle.setPriceFeeds(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.BAL, ADDRESS.WETH],
      [
        ADDRESS.CHAINLINK_USDC_USD_FEED,
        ADDRESS.CHAINLINK_USDT_USD_FEED,
        ADDRESS.CHAINLINK_DAI_USD_FEED,
        ADDRESS.CHAINLINK_BAL_USD_FEED,
        ADDRESS.CHAINLINK_ETH_USD_FEED,
      ]
    );

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });

    const WeightedBPTOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.WeightedBPTOracle);
    weightedOracle = <WeightedBPTOracle>(
      await upgrades.deployProxy(
        WeightedBPTOracleFactory,
        [ADDRESS.BALANCER_VAULT, coreOracle.address, admin.address],
        { unsafeAllow: ['delegatecall'] }
      )
    );

    await weightedOracle.deployed();

    const StableBPTOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.StableBPTOracle);

    stableOracle = <StableBPTOracle>await upgrades.deployProxy(
      StableBPTOracleFactory,
      [ADDRESS.BALANCER_VAULT, coreOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    await stableOracle.deployed();

    await weightedOracle.connect(admin).setStablePoolOracle(stableOracle.address);

    await coreOracle.setRoutes(
      [ADDRESS.USDC, ADDRESS.USDT, ADDRESS.DAI, ADDRESS.BAL, ADDRESS.WETH],
      [
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
      ]
    );
  });

  // Nested Weighted Pool with a Stable Pool inside
  it('Verify Price of a Nested Weighted Pool: 50WETH-50-3pool', async () => {
    const thirty = ethers.utils.parseEther('30');
    const fifty = ethers.utils.parseEther('50');

    await stableOracle.connect(admin).registerBpt(ADDRESS.BAL_UDU);
    await weightedOracle.connect(admin).registerBpt(ADDRESS.BAL_WETH_3POOL);

    const price = await weightedOracle.callStatic.getPrice(ADDRESS.BAL_WETH_3POOL);

    assert(price.gte(thirty), 'Price is greater than 30');
    assert(price.lte(fifty), 'Price is less than 50');
  });

  it('Verify Price of a Weighted Pool: B-80BAL-20WETH', async () => {
    const ten = ethers.utils.parseEther('10');
    const twenty = ethers.utils.parseEther('20');

    await weightedOracle.registerBpt(ADDRESS.BAL_WETH);
    const price = await weightedOracle.callStatic.getPrice(ADDRESS.BAL_WETH);

    assert(price.gte(ten), 'Price is greater than 10');
    assert(price.lte(twenty), 'Price is less than 20');
  });
});
