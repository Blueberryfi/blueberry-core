import chai, { expect, assert } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, IFeedRegistry, IWstETH } from '../../typechain-types';
import WstETHABI from '../../abi/IWstETH.json';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(near);
chai.use(roughlyNear);

const OneDay = 86400;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Chainlink Adapter Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;
  let chainlinkFeedOracle: IFeedRegistry;
  let wstETH: IWstETH;
  before(async () => {
    [admin, alice] = await ethers.getSigners();
    wstETH = <IWstETH>await ethers.getContractAt(WstETHABI, ADDRESS.wstETH);
  });

  beforeEach(async () => {
    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
      ChainlinkAdapterOracle,
      [ADDRESS.ChainlinkRegistry, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle.setTokenRemappings([ADDRESS.wstETH], [ADDRESS.stETH]);
    
    await chainlinkAdapterOracle.connect(admin).setPriceFeeds([ADDRESS.CHAINLINK_ETH], [ADDRESS.CHAINLINK_ETH_USD_FEED]);

    await chainlinkAdapterOracle.setTimeGap(
      [ADDRESS.USDC, ADDRESS.UNI, ADDRESS.stETH, ADDRESS.ALCX],
      [OneDay, OneDay, OneDay, OneDay]
    );
  });

  describe('Constructor', () => {
    it('should revert when feed registry address is invalid', async () => {
      const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
      await expect(
        upgrades.deployProxy(ChainlinkAdapterOracle, [ethers.constants.AddressZero, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(ChainlinkAdapterOracle, 'ZERO_ADDRESS');
    });
    it('should set feed registry', async () => {
      expect(await chainlinkAdapterOracle.getPriceFeed(ADDRESS.CHAINLINK_ETH)).to.be.equal(ADDRESS.CHAINLINK_ETH_USD_FEED);
    });
  });
  describe('Owner', () => {
    it('should be able to set routes', async () => {
      await expect(chainlinkAdapterOracle.connect(alice).setPriceFeeds([ADDRESS.USDC], [ADDRESS.CHAINLINK_USDC_FEED])).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );

      await expect(chainlinkAdapterOracle.setPriceFeeds([ADDRESS.USDC], [ADDRESS.CHAINLINK_USDC_FEED])).to.be.revertedWithCustomError(
        chainlinkAdapterOracle,
        'ZERO_ADDRESS'
      );

      await expect(chainlinkAdapterOracle.setPriceFeeds([ADDRESS.USDC], [ADDRESS.CHAINLINK_USDC_FEED]))
        .to.be.emit(chainlinkAdapterOracle, 'SetRegistry')
        .withArgs(ADDRESS.ChainlinkRegistry);

      expect(await chainlinkAdapterOracle.getPriceFeed(ADDRESS.USDC)).to.be.equal(ADDRESS.CHAINLINK_USDC_FEED);
    });
    it('should be able to set maxDelayTimes', async () => {
      await expect(
        chainlinkAdapterOracle.connect(alice).setTimeGap([ADDRESS.USDC, ADDRESS.UNI], [OneDay, OneDay])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        chainlinkAdapterOracle.setTimeGap([ADDRESS.USDC, ADDRESS.UNI], [OneDay, OneDay, OneDay])
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'INPUT_ARRAY_MISMATCH');

      await expect(chainlinkAdapterOracle.setTimeGap([ADDRESS.USDC, ADDRESS.UNI], [OneDay, OneDay * 3]))
        .to.be.revertedWithCustomError(chainlinkAdapterOracle, 'TOO_LONG_DELAY')
        .withArgs(OneDay * 3);

      await expect(
        chainlinkAdapterOracle.setTimeGap([ADDRESS.USDC, ethers.constants.AddressZero], [OneDay, OneDay])
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'ZERO_ADDRESS');

      await expect(chainlinkAdapterOracle.setTimeGap([ADDRESS.USDC, ADDRESS.UNI], [OneDay, OneDay])).to.be.emit(
        chainlinkAdapterOracle,
        'SetTimeGap'
      );

      expect(await chainlinkAdapterOracle.getTimeGap(ADDRESS.USDC)).to.be.equal(OneDay);
    });
    it('should be able to set setTokenRemappings', async () => {
      await expect(
        chainlinkAdapterOracle
          .connect(alice)
          .setTokenRemappings([ADDRESS.USDC, ADDRESS.UNI], [ADDRESS.USDC, ADDRESS.UNI])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        chainlinkAdapterOracle.setTokenRemappings([ADDRESS.USDC, ADDRESS.UNI], [ADDRESS.USDC, ADDRESS.UNI, ADDRESS.UNI])
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'INPUT_ARRAY_MISMATCH');

      await expect(
        chainlinkAdapterOracle.setTokenRemappings(
          [ADDRESS.USDC, ethers.constants.AddressZero],
          [ADDRESS.USDC, ADDRESS.UNI]
        )
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'ZERO_ADDRESS');

      await expect(chainlinkAdapterOracle.setTokenRemappings([ADDRESS.USDC], [ADDRESS.USDC])).to.be.emit(
        chainlinkAdapterOracle,
        'SetTokenRemapping'
      );

      expect(await chainlinkAdapterOracle.getTokenRemapping(ADDRESS.USDC)).to.be.equal(ADDRESS.USDC);
    });
  });

  describe('Price Feeds', () => {
    it('should revert when max delay time is not set', async () => {
      await expect(chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.CRV))
        .to.be.revertedWithCustomError(chainlinkAdapterOracle, 'NO_MAX_DELAY')
        .withArgs(ADDRESS.CRV);
    });
    it('USDC price feeds / based 10^18', async () => {
      const decimals = await chainlinkFeedOracle.decimals(ADDRESS.USDC, ADDRESS.CHAINLINK_USD);
      const { answer } = await chainlinkFeedOracle.latestRoundData(ADDRESS.USDC, ADDRESS.CHAINLINK_USD);
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.USDC);

      expect(answer.mul(BigNumber.from(10).pow(18)).div(BigNumber.from(10).pow(decimals))).to.be.roughlyNear(price);

      // real usdc price should be closed to $1
      expect(price).to.be.roughlyNear(BigNumber.from(10).pow(18));
      console.log('USDC Price:', utils.formatUnits(price, 18));
    });
    it('UNI price feeds / based 10^18', async () => {
      const decimals = await chainlinkFeedOracle.decimals(ADDRESS.UNI, ADDRESS.CHAINLINK_USD);
      const uniData = await chainlinkFeedOracle.latestRoundData(ADDRESS.UNI, ADDRESS.CHAINLINK_USD);
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.UNI);

      expect(uniData.answer.mul(BigNumber.from(10).pow(18)).div(BigNumber.from(10).pow(decimals))).to.be.roughlyNear(
        price
      );
      console.log('UNI Price:', utils.formatUnits(price, 18));
      console.log('Block Number:', await ethers.provider.getBlockNumber());
    });

    it('ALCX price feeds / based 10^18', async () => {
      const fiften = ethers.utils.parseEther('15');
      const thirty = ethers.utils.parseEther('30');
            
      await chainlinkAdapterOracle.connect(admin).setPriceFeeds([ADDRESS.ALCX], [ADDRESS.CHAINLINK_ALCX_ETH_FEED]);

      await chainlinkAdapterOracle.connect(admin).setEthDenominatedToken(ADDRESS.ALCX, true);
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.ALCX);

      assert(price.gte(fiften), 'Price is greater than 15');
      assert(price.lte(thirty), 'Price is less than 30');
      console.log('ALCX Price:', utils.formatUnits(price, 18));
    });

    it('wstETH price feeds / based 10^18', async () => {
      const decimals = await chainlinkFeedOracle.decimals(ADDRESS.stETH, ADDRESS.CHAINLINK_USD);
      const stETHData = await chainlinkFeedOracle.latestRoundData(ADDRESS.stETH, ADDRESS.CHAINLINK_USD);
      const stEthPerToken = await wstETH.stEthPerToken();
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.wstETH);

      expect(
        stETHData.answer
          .mul(BigNumber.from(10).pow(18))
          .mul(stEthPerToken)
          .div(BigNumber.from(10).pow(18 + decimals))
      ).to.be.roughlyNear(price);
      console.log('wstETH Price:', utils.formatUnits(price, 18));
    });

    it('CRV price feeds', async () => {
      await chainlinkAdapterOracle.setTimeGap([ADDRESS.CRV], [OneDay]);
      await chainlinkAdapterOracle.setTokenRemappings([ADDRESS.CRV], [ADDRESS.CRV]);
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.CRV);
      console.log('CRV Price:', utils.formatUnits(price, 18));
    });
    it('should revert for too old prices', async () => {
      const dydx = '0x92D6C1e31e14520e676a687F0a93788B716BEff5';
      await chainlinkAdapterOracle.setTimeGap([dydx], [3600]);
      await expect(chainlinkAdapterOracle.callStatic.getPrice(dydx))
        .to.be.revertedWithCustomError(chainlinkAdapterOracle, 'PRICE_OUTDATED')
        .withArgs(dydx);
    });
    it('should revert for invalid feeds', async () => {
      await chainlinkAdapterOracle.setTimeGap([ADDRESS.ICHI], [OneDay]);
      await expect(chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.ICHI)).to.be.revertedWith('Feed not found');
    });
  });
});
