import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES, DEPLOYMENTS } from '../../constant';
import { SoftVaultOracle, CoreOracle, MockOracle, WERC20, SoftVault, BToken } from '../../typechain-types';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork } from '../helpers';

chai.use(near);
chai.use(roughlyNear);

const SoftVaultScalar = BigNumber.from(10).pow(8);
const EighteenScalar = BigNumber.from(10).pow(18);
const NineScalar = BigNumber.from(10).pow(9);

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Soft Vault Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let softVaultOracle: SoftVaultOracle;
  let mockOracle: MockOracle;
  let coreOracle: CoreOracle;
  let werc20: WERC20;

  before(async () => {
    [admin, alice] = await ethers.getSigners();
    await fork(1, 19272826);

    coreOracle = await ethers.getContractAt('CoreOracle', DEPLOYMENTS.coreOracle);

    const SoftVaultOracle = await ethers.getContractFactory(CONTRACT_NAMES.SoftVaultOracle);
    softVaultOracle = <SoftVaultOracle>await upgrades.deployProxy(
      SoftVaultOracle,
      [coreOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await softVaultOracle.deployed();
  });

  describe('Owner', () => {
    it('should be able to register tokens', async () => {
      await expect(softVaultOracle.connect(alice).registerSoftVault(DEPLOYMENTS.ibBAL)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );

      await softVaultOracle.registerSoftVault(DEPLOYMENTS.ibBAL);
    });
  });

  describe('18 decimal underlying token', () => {
    before(async () => {
      await softVaultOracle.registerSoftVault(DEPLOYMENTS.ibBAL);
    });

    it('should return correct price', async () => {
      const softVault = <SoftVault>await ethers.getContractAt('SoftVault', DEPLOYMENTS.ibBAL);
      const bTokenAddr = await softVault.getBToken();
      const bToken = <BToken>await ethers.getContractAt('BToken', bTokenAddr);

      const cashBalance = await bToken.getCash();
      const underlyingPrice = await coreOracle.getPrice(ADDRESS.BAL);
      const ibTokenPrice = await softVaultOracle.getPrice(DEPLOYMENTS.ibBAL);
      const ibTokenSupply = await bToken.totalSupply();

      expect(ibTokenPrice.mul(ibTokenSupply).div(SoftVaultScalar)).to.be.near(
        underlyingPrice.mul(cashBalance).div(EighteenScalar)
      );
    });
  });

  describe('8 decimal underlying token', () => {
    before(async () => {
      await softVaultOracle.registerSoftVault(DEPLOYMENTS.ibWBTC);
    });

    it('should return correct price', async () => {
      const softVault = <SoftVault>await ethers.getContractAt('SoftVault', DEPLOYMENTS.ibWBTC);
      const bTokenAddr = await softVault.getBToken();
      const bToken = <BToken>await ethers.getContractAt('BToken', bTokenAddr);

      const cashBalance = await bToken.getCash();
      const underlyingPrice = await coreOracle.getPrice(ADDRESS.WBTC);
      const ibTokenPrice = await softVaultOracle.getPrice(DEPLOYMENTS.ibWBTC);
      const ibTokenSupply = await bToken.totalSupply();

      expect(ibTokenPrice.mul(ibTokenSupply).div(SoftVaultScalar)).to.be.near(
        underlyingPrice.mul(cashBalance).div(SoftVaultScalar)
      );
    });
  });

  describe('9 decimal underlying token', () => {
    before(async () => {
      await softVaultOracle.registerSoftVault(DEPLOYMENTS.ibOHM);
    });

    it('should return correct price', async () => {
      const softVault = <SoftVault>await ethers.getContractAt('SoftVault', DEPLOYMENTS.ibOHM);
      const bTokenAddr = await softVault.getBToken();
      const bToken = <BToken>await ethers.getContractAt('BToken', bTokenAddr);

      const cashBalance = await bToken.getCash();
      const underlyingPrice = await coreOracle.getPrice(ADDRESS.OHM);
      const ibTokenPrice = await softVaultOracle.getPrice(DEPLOYMENTS.ibOHM);
      const ibTokenSupply = await bToken.totalSupply();

      expect(ibTokenPrice.mul(ibTokenSupply).div(SoftVaultScalar)).to.be.near(
        underlyingPrice.mul(cashBalance).div(NineScalar)
      );
    });
  });
});
