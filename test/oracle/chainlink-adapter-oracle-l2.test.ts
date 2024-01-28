import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracleL2 } from '../../typechain-types';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork, evm_increaseTime } from '../helpers';

chai.use(near);
chai.use(roughlyNear);

const OneDay = 86400;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Aggregator Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let chainlinkAdapterOracle: ChainlinkAdapterOracleL2;

  before(async () => {
    // fork arbitrum mainnet
    await fork(42161);

    [admin, alice] = await ethers.getSigners();
  });

  beforeEach(async () => {
    // Chainlink Oracle
    const ChainlinkAdapterOracleL2 = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracleL2);
    chainlinkAdapterOracle = <ChainlinkAdapterOracleL2>await upgrades.deployProxy(
      ChainlinkAdapterOracleL2,
      [ADDRESS.ChainlinkSequencerArb, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle.setTimeGap([ADDRESS.USDC_ARB, ADDRESS.UNI_ARB], [OneDay, OneDay]);
  });

  describe('Constructor', () => {
    it('should revert when sequencer address is invalid', async () => {
      const ChainlinkAdapterOracleL2 = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracleL2);
      await expect(
        upgrades.deployProxy(ChainlinkAdapterOracleL2, [ethers.constants.AddressZero, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(ChainlinkAdapterOracleL2, 'ZERO_ADDRESS');
    });
    it('should set sequencer', async () => {
      expect(await chainlinkAdapterOracle.getSequencerUptimeFeed()).to.be.equal(ADDRESS.ChainlinkSequencerArb);
    });
  });

  describe('Owner', () => {
    it('should be able to set sequencer', async () => {
      await expect(
        chainlinkAdapterOracle.connect(alice).setSequencerUptimeFeed(ADDRESS.ChainlinkSequencerArb)
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        chainlinkAdapterOracle.setSequencerUptimeFeed(ethers.constants.AddressZero)
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'ZERO_ADDRESS');

      await expect(chainlinkAdapterOracle.setSequencerUptimeFeed(ADDRESS.ChainlinkSequencerArb))
        .to.be.emit(chainlinkAdapterOracle, 'SetSequencerUptimeFeed')
        .withArgs(ADDRESS.ChainlinkSequencerArb);

      expect(await chainlinkAdapterOracle.getSequencerUptimeFeed()).to.be.equal(ADDRESS.ChainlinkSequencerArb);
    });

    it('should be able to set price feeds', async () => {
      await expect(
        chainlinkAdapterOracle.connect(alice).setPriceFeeds([ADDRESS.USDC_ARB], [ADDRESS.CHAINLINK_USDC_FEED])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        chainlinkAdapterOracle.setPriceFeeds(
          [ADDRESS.USDC_ARB],
          [ADDRESS.CHAINLINK_USDC_FEED, ADDRESS.CHAINLINK_UNI_FEED]
        )
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'INPUT_ARRAY_MISMATCH');

      await expect(
        chainlinkAdapterOracle.setPriceFeeds(
          [ADDRESS.USDC_ARB, ethers.constants.AddressZero],
          [ADDRESS.CHAINLINK_USDC_FEED, ADDRESS.CHAINLINK_UNI_FEED]
        )
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'ZERO_ADDRESS');

      await expect(
        chainlinkAdapterOracle.setPriceFeeds(
          [ADDRESS.USDC_ARB, ADDRESS.UNI_ARB],
          [ADDRESS.CHAINLINK_USDC_FEED, ethers.constants.AddressZero]
        )
      ).to.be.revertedWithCustomError(chainlinkAdapterOracle, 'ZERO_ADDRESS');

      await expect(chainlinkAdapterOracle.setPriceFeeds([ADDRESS.USDC_ARB], [ADDRESS.CHAINLINK_USDC_FEED])).to.be.emit(
        chainlinkAdapterOracle,
        'SetTokenPriceFeed'
      );

      expect(await chainlinkAdapterOracle.getPriceFeed(ADDRESS.USDC_ARB)).to.be.equal(ADDRESS.CHAINLINK_USDC_FEED);
    });
  });

  describe('Price Feeds', () => {
    beforeEach(async () => {
      await chainlinkAdapterOracle.setPriceFeeds(
        [ADDRESS.USDC_ARB, ADDRESS.UNI_ARB],
        [ADDRESS.CHAINLINK_USDC_FEED, ADDRESS.CHAINLINK_UNI_FEED]
      );
    });

    it('should revert when max delay time is not set', async () => {
      await expect(chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.CRV_ARB))
        .to.be.revertedWithCustomError(chainlinkAdapterOracle, 'NO_MAX_DELAY')
        .withArgs(ADDRESS.CRV_ARB);
    });

    it('USDC price feeds / based 10^18', async () => {
      const price = await chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.USDC_ARB);

      // real usdc price should be closed to $1
      expect(price).to.be.roughlyNear(BigNumber.from(10).pow(18));
      console.log('USDC Price:', utils.formatUnits(price, 18));
    });

    it('should revert for too old prices', async () => {
      await chainlinkAdapterOracle.setTimeGap([ADDRESS.UNI_ARB], [3600]);
      await evm_increaseTime(3600);
      await expect(chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.UNI_ARB))
        .to.be.revertedWithCustomError(chainlinkAdapterOracle, 'PRICE_OUTDATED')
        .withArgs(ADDRESS.UNI_ARB);
    });

    it('should revert for invalid feeds', async () => {
      await chainlinkAdapterOracle.setTimeGap([ADDRESS.ICHI], [OneDay]);
      await expect(chainlinkAdapterOracle.callStatic.getPrice(ADDRESS.ICHI)).to.be.revertedWithCustomError(
        chainlinkAdapterOracle,
        'ZERO_ADDRESS'
      );
    });
  });
});
