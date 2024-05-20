import chai, { assert, expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, CoreOracle, BalancerV2SpotOracle } from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { fork } from '../helpers';

chai.use(roughlyNear);

const OneDay = 86400;

describe('Balancer Spot Price TWAP Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let balancerV2SpotOracle: BalancerV2SpotOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  beforeEach(async () => {
    await fork(1, 19905622);
    [admin, alice] = await ethers.getSigners();

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

    const BalancerV2SpotOracle = await ethers.getContractFactory(CONTRACT_NAMES.BalancerV2SpotOracle);
    balancerV2SpotOracle = <BalancerV2SpotOracle>await upgrades.deployProxy(
      BalancerV2SpotOracle,
      [ADDRESS.BALANCER_VAULT, coreOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    await balancerV2SpotOracle.deployed();

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

  it('Fails when non-admin tries to register a token', async () => {
    await expect(
      balancerV2SpotOracle.connect(alice).registerToken(ADDRESS.AURA, ADDRESS.BAL_AURA_WETH_WEIGHTED, 3600)
    ).to.revertedWith('Ownable: caller is not the owner');
  });

  it('Reverts when trying to register a token with an invalid duration', async () => {
    await expect(
      balancerV2SpotOracle.connect(admin).registerToken(ADDRESS.AURA, ADDRESS.BAL_AURA_WETH_WEIGHTED, 3700)
    ).to.revertedWithCustomError(balancerV2SpotOracle, 'VALUE_OUT_OF_RANGE');
  });

  it('Verify Aura spot price using AURA/WETH 80/20 pool', async () => {
    const pointEight = ethers.utils.parseEther('.8');
    const pointEightFive = ethers.utils.parseEther('.85');

    await balancerV2SpotOracle.connect(admin).registerToken(ADDRESS.AURA, ADDRESS.BAL_AURA_WETH_WEIGHTED, 1800);

    const price = await balancerV2SpotOracle.callStatic.getPrice(ADDRESS.AURA);

    assert(price.gte(pointEight), 'Price is greater than .8');
    assert(price.lte(pointEightFive), 'Price is less than .85');
  });
});
