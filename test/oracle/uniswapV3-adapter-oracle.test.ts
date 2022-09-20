import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import {
  SimpleOracle,
  CoreOracle,
  ProxyOracle,
  AggregatorOracle,
  UniswapV3AdapterOracle,
  IUniswapV3Pool,
} from '../../typechain-types';
import { solidity } from 'ethereum-waffle';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(solidity);
chai.use(near);
chai.use(roughlyNear);

describe('UniswapV3 Adapter Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let eve: SignerWithAddress;

  let simpleOracle: SimpleOracle;
  let coreOracle: CoreOracle;
  let oracle: ProxyOracle;
  let aggregatorOracle: AggregatorOracle;
  let uniswapV3AdapterOracle: UniswapV3AdapterOracle;
  before(async () => {
    [admin, alice, bob, eve] = await ethers.getSigners();

    const SimpleOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.SimpleOracle
    );
    simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
    await simpleOracle.deployed();

    const CoreOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.CoreOracle
    );
    coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
    await coreOracle.deployed();

    const ProxyOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.ProxyOracle
    );
    oracle = <ProxyOracle>await ProxyOracleFactory.deploy(coreOracle.address);
    await oracle.deployed();
  });

  describe('Basic', async () => {
    it('UniswapV3 Adapter Oracle testing', async () => {
      const daiAddr = ADDRESS.DAI;
      const usdcAddr = ADDRESS.USDC;
      const usdtAddr = ADDRESS.USDT;
      const uniAddr = ADDRESS.UNI;

      const uni_eth_uniV3_poolAddr = ADDRESS.UNI_V3_UNI_WETH;
      const uni_usdc_uniV3_poolAddr = ADDRESS.UNI_V3_UNI_USDC;

      const uni_eth_uniV3_pool = <IUniswapV3Pool>(
        await ethers.getContractAt(
          CONTRACT_NAMES.IUniswapV3Pool,
          uni_eth_uniV3_poolAddr
        )
      );

      await simpleOracle.setPrice(
        [daiAddr, usdtAddr, usdcAddr, uniAddr],
        [
          BigNumber.from(2).pow(112).div(600),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
          BigNumber.from(2).pow(112).div(600),
        ]
      );

      const UniswapV3AdapterOracle = await ethers.getContractFactory(
        CONTRACT_NAMES.UniswapV3AdapterOracle
      );
      uniswapV3AdapterOracle = <UniswapV3AdapterOracle>(
        await UniswapV3AdapterOracle.deploy()
      );
      await uniswapV3AdapterOracle.deployed();
      await uniswapV3AdapterOracle.setPoolsETH(
        [uniAddr],
        [uni_eth_uniV3_poolAddr]
      );
      await uniswapV3AdapterOracle.setPoolsStable(
        [uniAddr],
        [uni_usdc_uniV3_poolAddr]
      );
      await uniswapV3AdapterOracle.setTimeAgos([uniAddr], ['600']); // timeAgo - 10 mins

      const AggregatorOracle = await ethers.getContractFactory(
        CONTRACT_NAMES.AggregatorOracle
      );
      aggregatorOracle = <AggregatorOracle>await AggregatorOracle.deploy();
      await aggregatorOracle.deployed();

      await aggregatorOracle.setPrimarySources(
        uniAddr,
        BigNumber.from('1500000000000000000'),
        [uniswapV3AdapterOracle.address]
      );

      await coreOracle.setRoute(
        [daiAddr, usdtAddr, usdcAddr, uniAddr],
        [
          simpleOracle.address,
          simpleOracle.address,
          simpleOracle.address,
          aggregatorOracle.address,
        ]
      );

      await oracle.setTokenFactors(
        [daiAddr, usdcAddr, usdtAddr, uniAddr],
        [
          {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqThreshold: 10000,
          },
          {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqThreshold: 10000,
          },
          {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqThreshold: 10000,
          },
          {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqThreshold: 10000,
          },
        ]
      );

      const uniPriceETHPx = await uniswapV3AdapterOracle.getPrice(uniAddr);
      const uniPrice = uniPriceETHPx
        .mul(BigNumber.from(10).pow(18))
        .div(BigNumber.from(2).pow(112));

      const slot0 = await uni_eth_uniV3_pool.slot0();
      expect(uniPrice).to.be.roughlyNear(
        BigNumber.from(2)
          .pow(192)
          .mul(BigNumber.from(10).pow(18))
          .div(slot0.sqrtPriceX96.mul(slot0.sqrtPriceX96))
      );
    });
  });
});
