import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { ChainlinkAdapterOracle, CoreOracle, MockOracle, WERC20 } from '../../typechain-types';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(near);
chai.use(roughlyNear);

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Core Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let chainlinkOracle: ChainlinkAdapterOracle;
  let mockOracle: MockOracle;
  let coreOracle: CoreOracle;
  let werc20: WERC20;

  before(async () => {
    [admin, alice] = await ethers.getSigners();
  });

  beforeEach(async () => {
    const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
    mockOracle = <MockOracle>await MockOracle.deploy();

    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(ChainlinkAdapterOracle, [admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await chainlinkOracle.deployed();

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });

    const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
    werc20 = <WERC20>await WERC20.deploy();
    await werc20.deployed();
  });

  describe('Owner', () => {
    it('should be able to set routes', async () => {
      await expect(coreOracle.connect(alice).setRoutes([ADDRESS.USDC], [mockOracle.address])).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );

      await expect(
        coreOracle.setRoutes([ethers.constants.AddressZero], [mockOracle.address])
      ).to.be.revertedWithCustomError(coreOracle, 'ZERO_ADDRESS');

      await expect(coreOracle.setRoutes([ADDRESS.USDC], [ethers.constants.AddressZero])).to.be.revertedWithCustomError(
        coreOracle,
        'ZERO_ADDRESS'
      );

      await expect(
        coreOracle.setRoutes([ADDRESS.USDC, ADDRESS.USDT], [mockOracle.address])
      ).to.be.revertedWithCustomError(coreOracle, 'INPUT_ARRAY_MISMATCH');

      await expect(coreOracle.setRoutes([ADDRESS.USDC], [mockOracle.address])).to.be.emit(coreOracle, 'SetRoute');

      const route = await coreOracle.getRoute(ADDRESS.USDC);
      expect(route).to.be.equal(mockOracle.address);
    });
    it('should revert initializing twice', async () => {
      await expect(coreOracle.initialize(admin.address)).to.be.revertedWith(
        'Initializable: contract is already initialized'
      );
    });
  });
  describe('Utils', () => {
    beforeEach(async () => {
      await coreOracle.setRoutes([ADDRESS.USDC], [mockOracle.address]);
      await mockOracle.setPrice([ADDRESS.USDC], [10000000]);
    });

    it('should to able to get if the wrapper is supported or not', async () => {
      await expect(coreOracle.callStatic.isWrappedTokenSupported(ADDRESS.USDC, 0)).to.be.reverted;

      let collId = BigNumber.from(ADDRESS.USDC);
      expect(await coreOracle.callStatic.isWrappedTokenSupported(werc20.address, collId)).to.be.true;

      collId = BigNumber.from(ADDRESS.USDT);
      expect(await coreOracle.callStatic.isWrappedTokenSupported(werc20.address, collId)).to.be.false;
    });
    it('should be able to get if the token price is supported or not', async () => {
      await coreOracle.setRoutes([ADDRESS.USDT], [mockOracle.address]);
      await mockOracle.setPrice([ADDRESS.USDC], [utils.parseEther('1')]);

      expect(await coreOracle.callStatic.isTokenSupported(ADDRESS.USDC)).to.be.true;

      await expect(coreOracle.callStatic.getPrice(ADDRESS.USDT))
        .to.be.revertedWithCustomError(coreOracle, 'PRICE_FAILED')
        .withArgs(ADDRESS.USDT);

      await coreOracle.setRoutes([ADDRESS.ICHI], [chainlinkOracle.address]);
      expect(await coreOracle.callStatic.isTokenSupported(ADDRESS.ICHI)).to.be.false;
    });
  });
  describe('Value', () => {
    // TODO: Cover getPositionValue
    describe('Token Value', async () => {
      it('should revert when oracle route is not set', async () => {
        await expect(coreOracle.callStatic.getTokenValue(ADDRESS.CRV, 100))
          .to.be.revertedWithCustomError(coreOracle, 'NO_ORACLE_ROUTE')
          .withArgs(ADDRESS.CRV);
      });
    });
  });
  describe('Pauseable', () => {
    it('owner should be able to pause the contract', async () => {
      await expect(coreOracle.connect(alice).pause()).to.be.revertedWith('Ownable: caller is not the owner');

      await coreOracle.pause();
      expect(await coreOracle.paused()).to.be.true;
    });
    it('owner should be able to unpause the contract', async () => {
      expect(await coreOracle.paused()).to.be.false;
      await coreOracle.pause();
      await expect(coreOracle.connect(alice).unpause()).to.be.revertedWith('Ownable: caller is not the owner');

      await coreOracle.unpause();
      expect(await coreOracle.paused()).to.be.false;
    });
    it('should revert price feed when paused', async () => {
      await coreOracle.pause();
      await expect(coreOracle.callStatic.getPrice(ADDRESS.USDC)).to.be.revertedWith('Pausable: paused');
    });
  });
});
