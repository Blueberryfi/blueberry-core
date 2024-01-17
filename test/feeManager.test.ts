import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers, upgrades } from 'hardhat';
import chai, { expect } from 'chai';
import { FeeManager, MockERC20, ProtocolConfig } from '../typechain-types';
import { roughlyNear } from './assertions/roughlyNear';
import { near } from './assertions/near';

chai.use(roughlyNear);
chai.use(near);

describe('Fee Manager', () => {
  let admin: SignerWithAddress;
  let treasury: SignerWithAddress;

  let mockToken: MockERC20;
  let config: ProtocolConfig;
  let feeManager: FeeManager;

  before(async () => {
    [admin, treasury] = await ethers.getSigners();

    const ProtocolConfig = await ethers.getContractFactory('ProtocolConfig');
    config = <ProtocolConfig>await upgrades.deployProxy(ProtocolConfig, [treasury.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });

    const MockERC20 = await ethers.getContractFactory('MockERC20');
    mockToken = await MockERC20.deploy('Mock Token', 'MOCK', 18);
    await mockToken.deployed();
    await mockToken.mint();
  });

  beforeEach(async () => {
    const FeeManager = await ethers.getContractFactory('FeeManager');
    feeManager = <FeeManager>await upgrades.deployProxy(FeeManager, [config.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
  });

  describe('Constructor', () => {
    it('should revert initializing twice', async () => {
      await expect(feeManager.initialize(config.address, admin.address)).to.be.revertedWith(
        'Initializable: contract is already initialized'
      );
    });
    it('should revert deployment when zero address provided as config address', async () => {
      const FeeManager = await ethers.getContractFactory('FeeManager');
      await expect(
        upgrades.deployProxy(FeeManager, [ethers.constants.AddressZero, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(FeeManager, 'ZERO_ADDRESS');
    });
  });

  it('should cut fee and transfer to treasury wallet', async () => {
    const beforeBalance = await mockToken.balanceOf(admin.address);
    await mockToken.approve(feeManager.address, beforeBalance);

    await feeManager.doCutRewardsFee(mockToken.address, beforeBalance);
    const rewardsFee = await config.getRewardFee();

    const afterBalance = await mockToken.balanceOf(admin.address);
    expect(afterBalance).to.be.equal(beforeBalance.sub(beforeBalance.mul(rewardsFee).div(10000)));

    await feeManager.doCutRewardsFee(mockToken.address, 0);
    expect(await mockToken.balanceOf(admin.address)).to.be.equal(afterBalance);
  });
});
