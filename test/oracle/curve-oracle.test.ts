import chai, { expect } from 'chai';
import { utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
  ChainlinkAdapterOracle,
  CoreOracle,
  CurveStableOracle,
  CurveVolatileOracle,
  CurveTricryptoOracle,
} from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

const OneDay = 86400;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Curve LP Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  before(async () => {
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
      [
        ADDRESS.USDC,
        ADDRESS.USDT,
        ADDRESS.DAI,
        ADDRESS.WETH,
        ADDRESS.FRXETH,
        ADDRESS.WBTC,
        ADDRESS.FRAX,
        ADDRESS.CVX,
        ADDRESS.CRV,
        ADDRESS.ETH,
      ],
      [OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
    await coreOracle.deployed();
  });

  beforeEach(async () => {
    const CurveStableOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveStableOracle);
    stableOracle = <CurveStableOracle>(
      await upgrades.deployProxy(
        CurveStableOracleFactory,
        [ADDRESS.CRV_ADDRESS_PROVIDER, coreOracle.address, admin.address],
        { unsafeAllow: ['delegatecall'] }
      )
    );

    await stableOracle.deployed();

    const CurveVolatileOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveVolatileOracle);
    volatileOracle = <CurveVolatileOracle>(
      await upgrades.deployProxy(
        CurveVolatileOracleFactory,
        [ADDRESS.CRV_ADDRESS_PROVIDER, coreOracle.address, admin.address],
        { unsafeAllow: ['delegatecall'] }
      )
    );

    await volatileOracle.deployed();

    const CurveTricryptoOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveTricryptoOracle);
    tricryptoOracle = <CurveTricryptoOracle>(
      await upgrades.deployProxy(
        CurveTricryptoOracleFactory,
        [ADDRESS.CRV_ADDRESS_PROVIDER, coreOracle.address, admin.address],
        { unsafeAllow: ['delegatecall'] }
      )
    );

    await tricryptoOracle.deployed();
  });

  describe('Owner', () => {
    it('fail to register curve lp with non-owner', async () => {
      await expect(volatileOracle.connect(alice).registerCurveLp(ADDRESS.CRV_CVXETH)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('should be able to set limiter', async () => {
      await volatileOracle.connect(admin).registerCurveLp(ADDRESS.CRV_CVXETH);
      const poolInfo = await volatileOracle.callStatic.getPoolInfo(ADDRESS.CRV_CVXETH);

      await expect(
        volatileOracle.connect(alice).setLimiter(ADDRESS.CRV_CVXETH, poolInfo.virtualPrice)
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(volatileOracle.setLimiter(ADDRESS.CRV_CVXETH, 0)).to.be.revertedWithCustomError(
        volatileOracle,
        'INCORRECT_LIMITS'
      );

      await expect(
        volatileOracle.setLimiter(ADDRESS.CRV_CVXETH, poolInfo.virtualPrice.add(1))
      ).to.be.revertedWithCustomError(volatileOracle, 'INCORRECT_LIMITS');

      await expect(
        volatileOracle.setLimiter(ADDRESS.CRV_CVXETH, poolInfo.virtualPrice.mul(9).div(10))
      ).to.be.revertedWithCustomError(volatileOracle, 'INCORRECT_LIMITS');
    });
  });

  describe('Price Feed', () => {
    it('Getting PoolInfo', async () => {
      await stableOracle.registerCurveLp(ADDRESS.CRV_3Crv);
      await tricryptoOracle.registerCurveLp(ADDRESS.CRV_TriCrypto);
      await stableOracle.registerCurveLp(ADDRESS.CRV_FRAXUSDC);
      await stableOracle.registerCurveLp(ADDRESS.CRV_FRXETH);
      await volatileOracle.registerCurveLp(ADDRESS.CRV_CVXETH);
      await stableOracle.registerCurveLp(ADDRESS.CRV_CVXCRV_CRV);

      console.log('3CrvPool', await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_3Crv));
      console.log('TriCrypto2 Pool', await tricryptoOracle.callStatic.getPoolInfo(ADDRESS.CRV_TriCrypto));
      console.log('FRAX/USDC USD Pool', await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_FRAXUSDC));
      console.log('frxETH/ETH ETH Pool', await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_FRXETH));
      console.log('CVX/ETH Crypto Pool', await volatileOracle.callStatic.getPoolInfo(ADDRESS.CRV_CVXETH));
      console.log('cvxCRV/CRV Factory Pool', await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_CVXCRV_CRV));
    });

    it('Should fail to get price when base oracle is not set', async () => {
      await expect(stableOracle.callStatic.getPrice(ADDRESS.CRV_3Crv)).to.be.reverted;

      await expect(tricryptoOracle.callStatic.getPrice(ADDRESS.CRV_CVXETH))
        .to.be.revertedWithCustomError(tricryptoOracle, 'ORACLE_NOT_SUPPORT_LP')
        .withArgs(ADDRESS.CRV_CVXETH);
    });

    it('Crv Lp Price', async () => {
      await chainlinkAdapterOracle.setPriceFeeds(
        [
          ADDRESS.USDC,
          ADDRESS.USDT,
          ADDRESS.DAI,
          ADDRESS.WETH,
          ADDRESS.FRXETH,
          ADDRESS.WBTC,
          ADDRESS.FRAX,
          ADDRESS.CVX,
          ADDRESS.CRV,
          ADDRESS.ETH,
        ],
        [
          ADDRESS.CHAINLINK_USDC_USD_FEED,
          ADDRESS.CHAINLINK_USDT_USD_FEED,
          ADDRESS.CHAINLINK_DAI_USD_FEED,
          ADDRESS.CHAINLINK_ETH_USD_FEED,
          ADDRESS.CHAINLINK_ETH_USD_FEED,
          ADDRESS.CHAINLINK_BTC_USD_FEED,
          ADDRESS.CHAINLINK_FRAX_USD_FEED,
          ADDRESS.CHAINLINK_CVX_USD_FEED,
          ADDRESS.CHAINLINK_CRV_USD_FEED,
          ADDRESS.CHAINLINK_ETH_USD_FEED,
        ]
      );

      await coreOracle.setRoutes(
        [
          ADDRESS.USDC,
          ADDRESS.USDT,
          ADDRESS.DAI,
          ADDRESS.WETH,
          ADDRESS.FRXETH,
          ADDRESS.WBTC,
          ADDRESS.FRAX,
          ADDRESS.CVX,
          ADDRESS.CRV,
          ADDRESS.ETH,
        ],
        [
          chainlinkAdapterOracle.address,
          chainlinkAdapterOracle.address,
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

      await volatileOracle.registerCurveLp(ADDRESS.CRV_CVXETH);

      const poolInfo = await volatileOracle.callStatic.getPoolInfo(ADDRESS.CRV_CVXETH);
      await volatileOracle.setLimiter(ADDRESS.CRV_CVXETH, poolInfo.virtualPrice);

      await stableOracle.registerCurveLp(ADDRESS.CRV_3Crv);
      let price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_3Crv);
      console.log('3CrvPool Price:', utils.formatUnits(price, 18));

      await tricryptoOracle.registerCurveLp(ADDRESS.CRV_TriCrypto);
      price = await tricryptoOracle.callStatic.getPrice(ADDRESS.CRV_TriCrypto);
      console.log('TriCrypto Price:', utils.formatUnits(price, 18));

      await stableOracle.registerCurveLp(ADDRESS.CRV_FRAXUSDC);
      price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_FRAXUSDC);
      console.log('FRAX/USDC Price:', utils.formatUnits(price, 18));

      await volatileOracle.registerCurveLp(ADDRESS.CRV_CVXETH);
      price = await volatileOracle.callStatic.getPrice(ADDRESS.CRV_CVXETH);
      console.log('CVX/ETH Price:', utils.formatUnits(price, 18));

      await stableOracle.registerCurveLp(ADDRESS.CRV_FRXETH);
      price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_FRXETH);
      console.log('frxETH/ETH Price:', utils.formatUnits(price, 18));
    });
  });
});
