import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers, upgrades } from 'hardhat';
import chai, { expect } from 'chai';
import { ProtocolConfig } from '../typechain-types';
import { roughlyNear } from './assertions/roughlyNear';
import { near } from './assertions/near';

chai.use(roughlyNear);
chai.use(near);

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Protocol Config', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let config: ProtocolConfig;

  before(async () => {
    [admin, alice, treasury] = await ethers.getSigners();
  });

  beforeEach(async () => {
    const ProtocolConfig = await ethers.getContractFactory('ProtocolConfig');
    config = <ProtocolConfig>await upgrades.deployProxy(ProtocolConfig, [treasury.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
  });

  describe('Constructor', () => {
    it('should revert initializing twice', async () => {
      await expect(config.initialize(config.address, admin.address)).to.be.revertedWith(
        'Initializable: contract is already initialized'
      );
    });
    it('should revert when treasury address is invalid', async () => {
      const ProtocolConfig = await ethers.getContractFactory('ProtocolConfig');
      await expect(
        upgrades.deployProxy(ProtocolConfig, [ethers.constants.AddressZero, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(ProtocolConfig, 'ZERO_ADDRESS');

      expect(await config.getTreasury()).to.be.equal(treasury.address);
    });
    it('should set initial states on constructor', async () => {
      expect(await config.getDepositFee()).to.be.equal(50);
      expect(await config.getWithdrawFee()).to.be.equal(50);
      expect(await config.getTreasuryFeeRate()).to.be.equal(3000);
      expect(await config.getBlbStablePoolFeeRate()).to.be.equal(3500);
      expect(await config.getBlbIchiVaultFeeRate()).to.be.equal(3500);
      expect(await config.getWithdrawVaultFee()).to.be.equal(100);
      expect(await config.getWithdrawVaultFeeWindow()).to.be.equal(60 * 60 * 24 * 60);
      expect(await config.getWithdrawVaultFeeWindowStartTime()).to.be.equal(0);
    });
  });

  it('owner should be able to start vault withdraw fee', async () => {
    await expect(config.connect(alice).startVaultWithdrawFee()).to.be.revertedWith('Ownable: caller is not the owner');

    await config.startVaultWithdrawFee();

    await expect(config.startVaultWithdrawFee()).to.be.revertedWithCustomError(config, 'FEE_WINDOW_ALREADY_STARTED');
  });

  it('owner should be able to set vault withdraw fee window', async () => {
    await expect(config.connect(alice).setWithdrawVaultFeeWindow(60)).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );
    await expect(config.setWithdrawVaultFeeWindow(60 * 60 * 24 * 90))
      .to.be.revertedWithCustomError(config, 'FEE_WINDOW_TOO_LONG')
      .withArgs(60 * 60 * 24 * 90);

    await config.setWithdrawVaultFeeWindow(60);
    expect(await config.getWithdrawVaultFeeWindow()).to.be.equal(60);
  });

  it('owner should be able to set deposit fee', async () => {
    await expect(config.connect(alice).setDepositFee(100)).to.be.revertedWith('Ownable: caller is not the owner');
    await expect(config.setDepositFee(2500)).to.be.revertedWithCustomError(config, 'RATIO_TOO_HIGH').withArgs(2500);

    await config.setDepositFee(100);
    expect(await config.getDepositFee()).to.be.equal(100);
  });

  it('owner should be able to set withdraw fee', async () => {
    await expect(config.connect(alice).setWithdrawFee(100)).to.be.revertedWith('Ownable: caller is not the owner');
    await expect(config.setWithdrawFee(2500)).to.be.revertedWithCustomError(config, 'RATIO_TOO_HIGH').withArgs(2500);

    await config.setWithdrawFee(100);
    expect(await config.getWithdrawFee()).to.be.equal(100);
  });

  it('owner should be able to set rewards fee', async () => {
    await expect(config.connect(alice).setRewardFee(100)).to.be.revertedWith('Ownable: caller is not the owner');
    await expect(config.setRewardFee(2500)).to.be.revertedWithCustomError(config, 'RATIO_TOO_HIGH').withArgs(2500);

    await config.setRewardFee(100);
    expect(await config.getRewardFee()).to.be.equal(100);
  });

  it('owner should be able to set fee distribution rates', async () => {
    await expect(config.connect(alice).setFeeDistribution(0, 0, 0)).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );
    await expect(config.setFeeDistribution(0, 4000, 3000)).to.be.revertedWithCustomError(
      config,
      'INVALID_FEE_DISTRIBUTION'
    );

    await config.setFeeDistribution(3000, 4000, 3000);
    expect(await config.getTreasuryFeeRate()).to.be.equal(3000);
    expect(await config.getBlbStablePoolFeeRate()).to.be.equal(4000);
    expect(await config.getBlbIchiVaultFeeRate()).to.be.equal(3000);
  });

  it('owner should be able to set treasury wallet', async () => {
    await expect(config.connect(alice).setTreasuryWallet(treasury.address)).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );
    await expect(config.setTreasuryWallet(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
      config,
      'ZERO_ADDRESS'
    );

    await config.setTreasuryWallet(treasury.address);
    expect(await config.getTreasury()).to.be.equal(treasury.address);
  });

  it('owner should be able to set fee manager', async () => {
    await expect(config.connect(alice).setFeeManager(treasury.address)).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );
    await expect(config.setFeeManager(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
      config,
      'ZERO_ADDRESS'
    );

    await config.setFeeManager(treasury.address);
    expect(await config.getFeeManager()).to.be.equal(treasury.address);
  });

  it('owner should be able to set BLB/USDC ichi vault', async () => {
    await expect(config.connect(alice).setBlbUsdcIchiVault(treasury.address)).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );
    await expect(config.setBlbUsdcIchiVault(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
      config,
      'ZERO_ADDRESS'
    );

    await config.setBlbUsdcIchiVault(treasury.address);
    expect(await config.getBlbUsdcIchiVault()).to.be.equal(treasury.address);
  });

  it('owner should be able to set BLB stable pool', async () => {
    await expect(config.connect(alice).setBlbStabilityPool(treasury.address)).to.be.revertedWith(
      'Ownable: caller is not the owner'
    );
    await expect(config.setBlbStabilityPool(ethers.constants.AddressZero)).to.be.revertedWithCustomError(
      config,
      'ZERO_ADDRESS'
    );

    await config.setBlbStabilityPool(treasury.address);
    expect(await config.getBlbStabilityPool()).to.be.equal(treasury.address);
  });
});
