import chai, { expect } from 'chai';
import { utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { AggregatorOracle, ChainlinkAdapterOracle, MockOracle } from '../../typechain-types';
import { fork } from '../helpers';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(near);
chai.use(roughlyNear);

const OneDay = 86400;
const DEVIATION = 500; // 5%

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Aggregator Oracle2', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let mockOracle1: MockOracle;
  let mockOracle2: MockOracle;
  let mockOracle3: MockOracle;

  let chainlinkOracle: ChainlinkAdapterOracle;
  let aggregatorOracle: AggregatorOracle;

  before(async () => {
    await fork(1, 18695050);

    [admin, alice] = await ethers.getSigners();

    // Chainlink Oracle
    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(ChainlinkAdapterOracle, [admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await chainlinkOracle.deployed();

    await chainlinkOracle.setTimeGap([ADDRESS.USDC, ADDRESS.UNI, ADDRESS.CRV], [OneDay, OneDay, OneDay]);
    console.log('2');
    await chainlinkOracle.setPriceFeeds(
      [ADDRESS.USDC, ADDRESS.UNI, ADDRESS.CRV],
      [ADDRESS.CHAINLINK_USDC_USD_FEED, ADDRESS.CHAINLINK_UNI_USD_FEED, ADDRESS.CHAINLINK_CRV_USD_FEED]
    );
    console.log('3');
    // Mock Oracle
    const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
    mockOracle1 = <MockOracle>await MockOracle.deploy();
    mockOracle2 = <MockOracle>await MockOracle.deploy();
    mockOracle3 = <MockOracle>await MockOracle.deploy();

    await mockOracle1.setPrice([ADDRESS.ICHI], [utils.parseEther('1')]);
    await mockOracle2.setPrice([ADDRESS.ICHI], [utils.parseEther('0.5')]);
    await mockOracle3.setPrice([ADDRESS.ICHI], [utils.parseEther('0.7')]);
  });

  beforeEach(async () => {
    const AggregatorOracle = await ethers.getContractFactory(CONTRACT_NAMES.AggregatorOracle);
    aggregatorOracle = <AggregatorOracle>(
      await upgrades.deployProxy(AggregatorOracle, [admin.address], { unsafeAllow: ['delegatecall'] })
    );
    await aggregatorOracle.deployed();
  });

  describe('Owner', () => {
    it('should be able to set primary sources', async () => {
      await expect(
        aggregatorOracle.connect(alice).setPrimarySources(ADDRESS.USDC, DEVIATION, [chainlinkOracle.address])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        aggregatorOracle
          .connect(admin)
          .setPrimarySources(ethers.constants.AddressZero, DEVIATION, [chainlinkOracle.address])
      ).to.be.revertedWithCustomError(aggregatorOracle, 'ZERO_ADDRESS');

      await expect(
        aggregatorOracle.setPrimarySources(ADDRESS.UNI, DEVIATION, [
          chainlinkOracle.address,
          chainlinkOracle.address,
          chainlinkOracle.address,
          chainlinkOracle.address,
          chainlinkOracle.address,
        ])
      )
        .to.be.revertedWithCustomError(aggregatorOracle, 'EXCEED_SOURCE_LEN')
        .withArgs(5);

      await expect(
        aggregatorOracle.setPrimarySources(ADDRESS.UNI, DEVIATION, [
          chainlinkOracle.address,
          ethers.constants.AddressZero,
        ])
      ).to.be.revertedWithCustomError(aggregatorOracle, 'ZERO_ADDRESS');

      await expect(aggregatorOracle.setPrimarySources(ADDRESS.UNI, 1500, [chainlinkOracle.address]))
        .to.be.revertedWithCustomError(aggregatorOracle, 'OUT_OF_DEVIATION_CAP')
        .withArgs(1500);

      await expect(aggregatorOracle.setPrimarySources(ADDRESS.UNI, DEVIATION, [chainlinkOracle.address])).to.be.emit(
        aggregatorOracle,
        'SetPrimarySources'
      );

      expect(await aggregatorOracle.getMaxPriceDeviation(ADDRESS.UNI)).to.be.equal(DEVIATION);
      expect(await aggregatorOracle.getPrimarySourceCount(ADDRESS.UNI)).to.be.equal(1);
      expect(await aggregatorOracle.getPrimarySource(ADDRESS.UNI, 0)).to.be.equal(chainlinkOracle.address);
    });
    it('should be able to set multiple primary sources', async () => {
      await expect(
        aggregatorOracle
          .connect(alice)
          .setMultiPrimarySources(
            [ADDRESS.USDC, ADDRESS.UNI],
            [DEVIATION, DEVIATION],
            [[chainlinkOracle.address], [chainlinkOracle.address]]
          )
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        aggregatorOracle.setMultiPrimarySources(
          [ADDRESS.USDC, ADDRESS.UNI],
          [DEVIATION],
          [[chainlinkOracle.address], [chainlinkOracle.address]]
        )
      ).to.be.revertedWithCustomError(aggregatorOracle, 'INPUT_ARRAY_MISMATCH');

      await expect(
        aggregatorOracle.setMultiPrimarySources(
          [ADDRESS.USDC, ADDRESS.UNI],
          [DEVIATION, DEVIATION],
          [[chainlinkOracle.address]]
        )
      ).to.be.revertedWithCustomError(aggregatorOracle, 'INPUT_ARRAY_MISMATCH');

      await expect(
        aggregatorOracle.setMultiPrimarySources(
          [ADDRESS.USDC, ADDRESS.UNI],
          [DEVIATION, DEVIATION],
          [[chainlinkOracle.address], [chainlinkOracle.address]]
        )
      ).to.be.emit(aggregatorOracle, 'SetPrimarySources');

      expect(await aggregatorOracle.getMaxPriceDeviation(ADDRESS.UNI)).to.be.equal(DEVIATION);
      expect(await aggregatorOracle.getPrimarySourceCount(ADDRESS.UNI)).to.be.equal(1);
      expect(await aggregatorOracle.getPrimarySource(ADDRESS.UNI, 0)).to.be.equal(chainlinkOracle.address);
    });
  });

  describe('Price Feeds', () => {
    beforeEach(async () => {
      await aggregatorOracle.setMultiPrimarySources(
        [ADDRESS.USDC, ADDRESS.UNI, ADDRESS.CRV, ADDRESS.ICHI],
        [DEVIATION, DEVIATION, DEVIATION, DEVIATION],
        [
          [chainlinkOracle.address],
          [chainlinkOracle.address],
          [chainlinkOracle.address],
          [mockOracle1.address, mockOracle2.address, mockOracle3.address],
        ]
      );
    });
    it('should revert when there is no source', async () => {
      await expect(aggregatorOracle.callStatic.getPrice(ADDRESS.BLB_COMPTROLLER))
        .to.be.revertedWithCustomError(aggregatorOracle, 'NO_PRIMARY_SOURCE')
        .withArgs(ADDRESS.BLB_COMPTROLLER);
    });
    it('should revert when there is no source returning valid price', async () => {
      await mockOracle1.setPrice([ADDRESS.ICHI], [0]);
      await mockOracle2.setPrice([ADDRESS.ICHI], [0]);
      await mockOracle3.setPrice([ADDRESS.ICHI], [0]);

      await expect(aggregatorOracle.callStatic.getPrice(ADDRESS.ICHI))
        .to.be.revertedWithCustomError(aggregatorOracle, 'NO_VALID_SOURCE')
        .withArgs(ADDRESS.ICHI);
    });
    it('should revert when source prices exceed deviation', async () => {
      await aggregatorOracle.setPrimarySources(ADDRESS.ICHI, DEVIATION, [mockOracle1.address, mockOracle2.address]);

      await mockOracle1.setPrice([ADDRESS.ICHI], [utils.parseEther('0.7')]);
      await mockOracle2.setPrice([ADDRESS.ICHI], [utils.parseEther('1')]);

      await expect(aggregatorOracle.callStatic.getPrice(ADDRESS.ICHI)).to.be.revertedWithCustomError(
        aggregatorOracle,
        'EXCEED_DEVIATION'
      );
    });
    it('should take avgerage of valid prices within deviation', async () => {
      await mockOracle1.setPrice([ADDRESS.ICHI], [utils.parseEther('0.7')]);
      await mockOracle2.setPrice([ADDRESS.ICHI], [utils.parseEther('0.96')]);
      await mockOracle3.setPrice([ADDRESS.ICHI], [utils.parseEther('1')]);

      expect(await aggregatorOracle.callStatic.getPrice(ADDRESS.ICHI)).to.be.equal(utils.parseEther('0.98'));

      await mockOracle1.setPrice([ADDRESS.ICHI], [utils.parseEther('0.68')]);
      await mockOracle2.setPrice([ADDRESS.ICHI], [utils.parseEther('0.7')]);
      await mockOracle3.setPrice([ADDRESS.ICHI], [utils.parseEther('1')]);
      expect(await aggregatorOracle.callStatic.getPrice(ADDRESS.ICHI)).to.be.equal(utils.parseEther('0.69'));
    });
    it('CRV price feeds', async () => {
      const token = ADDRESS.CRV;
      const chainlinkPrice = await chainlinkOracle.callStatic.getPrice(token);
      console.log('CRV Price (Chainlink):', utils.formatUnits(chainlinkPrice, 18));

      const aggregatorPrice = await aggregatorOracle.callStatic.getPrice(token);
      console.log('CRV Price (Oracle):', utils.formatUnits(aggregatorPrice, 18));
      expect(chainlinkPrice).to.be.equal(aggregatorPrice);
    });
    it('UNI price feeds', async () => {
      const token = ADDRESS.UNI;
      const chainlinkPrice = await chainlinkOracle.callStatic.getPrice(token);
      console.log('UNI Price (Chainlink):', utils.formatUnits(chainlinkPrice, 18));

      const aggregatorPrice = await aggregatorOracle.callStatic.getPrice(token);
      console.log('USDC Price (Oracle):', utils.formatUnits(aggregatorPrice, 18));
      expect(chainlinkPrice).to.be.equal(aggregatorPrice);
    });
    it('USDC price feeds', async () => {
      const token = ADDRESS.USDC;
      const chainlinkPrice = await chainlinkOracle.callStatic.getPrice(token);
      console.log('USDC Price (Chainlink):', utils.formatUnits(chainlinkPrice, 18));

      const aggregatorPrice = await aggregatorOracle.callStatic.getPrice(token);
      console.log('USDC Price (Oracle):', utils.formatUnits(aggregatorPrice, 18));
      expect(chainlinkPrice.add(chainlinkPrice).div(2)).to.be.equal(aggregatorPrice);
    });
  });
});
