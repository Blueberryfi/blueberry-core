import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS } from '../../constant';
import { MockIchiFarm, WIchiFarm } from '../../typechain-types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

describe('Wrapped Ichi Farm', () => {
  let ichiFarm: MockIchiFarm;
  let wichi: WIchiFarm;
  let admin: SignerWithAddress;

  before(async () => {
    [admin] = await ethers.getSigners();
    const MockIchiFarm = await ethers.getContractFactory('MockIchiFarm');
    ichiFarm = <MockIchiFarm>await MockIchiFarm.deploy(
      ADDRESS.ICHI_FARM,
      ethers.utils.parseUnits('1', 9) // 1 ICHI.FARM per block
    );
    const WIchiFarm = await ethers.getContractFactory('WIchiFarm');
    wichi = <WIchiFarm>await upgrades.deployProxy(
      WIchiFarm,
      [ADDRESS.ICHI, ADDRESS.ICHI_FARM, ichiFarm.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await wichi.deployed();
  });

  describe('Constructor', () => {
    it('should revert when zero address is provided in params', async () => {
      const WIchiFarm = await ethers.getContractFactory('WIchiFarm');
      await expect(
        upgrades.deployProxy(
          WIchiFarm,
          [ethers.constants.AddressZero, ADDRESS.ICHI_FARM, ichiFarm.address, admin.address],
          {
            unsafeAllow: ['delegatecall'],
          }
        )
      ).to.be.revertedWithCustomError(WIchiFarm, 'ZERO_ADDRESS');
      await expect(
        upgrades.deployProxy(WIchiFarm, [ADDRESS.ICHI, ethers.constants.AddressZero, ichiFarm.address, admin.address], {
          unsafeAllow: ['delegatecall'],
        })
      ).to.be.revertedWithCustomError(WIchiFarm, 'ZERO_ADDRESS');
      await expect(
        upgrades.deployProxy(
          WIchiFarm,
          [ADDRESS.ICHI, ADDRESS.ICHI_FARM, ethers.constants.AddressZero, admin.address],
          {
            unsafeAllow: ['delegatecall'],
          }
        )
      ).to.be.revertedWithCustomError(WIchiFarm, 'ZERO_ADDRESS');
    });
    it('should revert initializing twice', async () => {
      await expect(
        wichi.initialize(ADDRESS.ICHI, ADDRESS.ICHI_FARM, ichiFarm.address, admin.address)
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });
  });

  it('should encode pool id and reward per share to tokenId', async () => {
    const poolId = BigNumber.from(10);
    const rewardPerShare = BigNumber.from(10000);

    await expect(wichi.encodeId(BigNumber.from(2).pow(16), rewardPerShare))
      .to.be.revertedWithCustomError(wichi, 'BAD_PID')
      .withArgs(BigNumber.from(2).pow(16));

    await expect(wichi.encodeId(poolId, BigNumber.from(2).pow(240)))
      .to.be.revertedWithCustomError(wichi, 'BAD_REWARD_PER_SHARE')
      .withArgs(BigNumber.from(2).pow(240));

    const tokenId = await wichi.encodeId(poolId, rewardPerShare);
    expect(tokenId).to.be.equal(BigNumber.from(2).pow(240).mul(poolId).add(rewardPerShare));
  });
});
