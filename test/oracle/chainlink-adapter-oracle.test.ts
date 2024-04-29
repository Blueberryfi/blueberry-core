import chai, { expect, assert } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, IAggregatorV3Interface, IWstETH } from '../../typechain-types';
import WstETHABI from '../../abi/contracts/interfaces/IWstETH.sol/IWstETH.json';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork, evm_increaseTime } from '../helpers';

chai.use(near);
chai.use(roughlyNear);

const OneDay = 86400;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Chainlink Adapter Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;
  let chainlinkFeedOracle: IAggregatorV3Interface;
  let wstETH: IWstETH;
  before(async () => {
    await fork(1, 18687993);
    [admin, alice] = await ethers.getSigners();
    wstETH = <IWstETH>await ethers.getContractAt(WstETHABI, ADDRESS.wstETH);
  });

  beforeEach(async () => {
    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
      ChainlinkAdapterOracle,
      [admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle
      .connect(admin)
      .setPriceFeeds(
        [ADDRESS.ETH, ADDRESS.USDC, ADDRESS.UNI, ADDRESS.ALCX, ADDRESS.wstETH],
        [
          ADDRESS.CHAINLINK_ETH_USD_FEED,
          ADDRESS.CHAINLINK_USDC_USD_FEED,
          ADDRESS.CHAINLINK_UNI_USD_FEED,
          ADDRESS.CHAINLINK_ALCX_ETH_FEED,
          ADDRESS.CHAINLINK_STETH_USD_FEED,
        ]
      );

    await chainlinkAdapterOracle.setTimeGap(
      [ADDRESS.ETH, ADDRESS.USDC, ADDRESS.UNI, ADDRESS.wstETH, ADDRESS.ALCX],
      [OneDay, OneDay, OneDay, OneDay, OneDay]
    );
  });

  describe('Owner', () => {
    it('should be able to set routes', async () => {
      await expect(
        chainlinkAdapterOracle.connect(alice).setPriceFeeds([ADDRESS.USDC], [ADDRESS.CHAINLINK_USDC_USD_FEED])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        chainlinkAdapterOracle.setPriceFeeds([ADDRESS.USDC], [ethers.constants.AddressZero])
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'ZERO_ADDRESS');

      await expect(chainlinkAdapterOracle.setPriceFeeds([ADDRESS.USDC], [ADDRESS.CHAINLINK_USDC_USD_FEED]))
        .to.be.emit(chainlinkAdapterOracle, 'SetTokenPriceFeed')
        .withArgs(ADDRESS.USDC, ADDRESS.CHAINLINK_USDC_USD_FEED);

      expect(await chainlinkAdapterOracle.getPriceFeed(ADDRESS.USDC)).to.be.equal(ADDRESS.CHAINLINK_USDC_USD_FEED);
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
      const pointNine = ethers.utils.parseEther('0.9');
      const onePointOne = ethers.utils.parseEther('1.1');
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.USDC);

      assert(price.gte(pointNine), 'Price is greater than 0.9');
      assert(price.lte(onePointOne), 'Price is less than 1.1');

      // real usdc price should be closed to $1
      expect(price).to.be.roughlyNear(BigNumber.from(10).pow(18));
      console.log('USDC Price:', utils.formatUnits(price, 18));
    });
    it('UNI price feeds / based 10^18', async () => {
      const five = ethers.utils.parseEther('5.0');
      const sixPointFive = ethers.utils.parseEther('6.5');
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.UNI);

      assert(price.gte(five), 'Price is greater than 5.0');
      assert(price.lte(sixPointFive), 'Price is less than 6.5');
      console.log('UNI Price:', utils.formatUnits(price, 18));
      console.log('Block Number:', await ethers.provider.getBlockNumber());
    });

    it('ALCX price feeds / based 10^18', async () => {
      const fiften = ethers.utils.parseEther('15');
      const thirty = ethers.utils.parseEther('30');
      await chainlinkAdapterOracle.connect(admin).setPriceFeeds([ADDRESS.ALCX], [ADDRESS.CHAINLINK_ALCX_ETH_FEED]);

      await chainlinkAdapterOracle.connect(admin).setEthDenominatedToken(ADDRESS.ALCX, true);
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.ALCX);
      console.log('ALCX Price:', utils.formatUnits(price, 18));

      assert(price.gte(fiften), 'Price is greater than 15');
      assert(price.lte(thirty), 'Price is less than 30');
    });

    it('wstETH price feeds / based 10^18', async () => {
      const twoThousand = ethers.utils.parseEther('2000');
      const twoThousandFiveHundred = ethers.utils.parseEther('2500');
      const stEthPerToken = await wstETH.stEthPerToken();
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.wstETH);
      assert(price > twoThousand, 'Price is greater than 2000');
      assert(price < twoThousandFiveHundred, 'Price is less than 2500');
      console.log('wstETH Price:', utils.formatUnits(price, 18));
    });

    it('CRV price feeds', async () => {
      await chainlinkAdapterOracle.setTimeGap([ADDRESS.CRV], [OneDay]);
      await chainlinkAdapterOracle.setTokenRemappings([ADDRESS.CRV], [ADDRESS.CRV]);
      await chainlinkAdapterOracle.connect(admin).setPriceFeeds([ADDRESS.CRV], [ADDRESS.CHAINLINK_CRV_USD_FEED]);
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.CRV);
      console.log('CRV Price:', utils.formatUnits(price, 18));
    });
    it('should revert for too old prices', async () => {
      const bnb = '0xb8c77482e45f1f44de1745f52c74426c631bdd52';
      const bnbFeed = '0x14e613AC84a31f709eadbdF89C6CC390fDc9540A';
      await chainlinkAdapterOracle.setTokenRemappings([bnb], [bnb]);
      await chainlinkAdapterOracle.connect(admin).setPriceFeeds([bnb], [bnbFeed]);
      await chainlinkAdapterOracle.setTimeGap([bnb], [3600]);
      await evm_increaseTime(3600);
      await expect(chainlinkAdapterOracle.callStatic.getPrice(bnb))
        .to.be.revertedWithCustomError(chainlinkAdapterOracle, 'PRICE_OUTDATED')
        .withArgs(bnbFeed);
    });
    it('should revert for invalid feeds', async () => {
      await chainlinkAdapterOracle.setTimeGap([ADDRESS.ICHI], [OneDay]);
      await expect(chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.ICHI)).to.be.reverted;
    });
  });
});
