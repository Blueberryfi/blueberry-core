import { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { CONTRACT_NAMES } from '../../constant';
import {
  WConvexBooster,
  MockConvexToken,
  MockBooster,
  MockERC20,
  MockBaseRewardPool,
  MockVirtualBalanceRewardPool,
  PoolEscrowFactory,
} from '../../typechain-types';
import { generateRandomAddress } from '../helpers';

describe('WConvexBooster', () => {
  let alice: SignerWithAddress;
  let admin: SignerWithAddress;

  let lpToken: MockERC20;
  let extraRewarder: MockVirtualBalanceRewardPool;
  let stakingToken: MockERC20;
  let rewardToken: MockERC20;
  let extraRewardToken: MockERC20;
  let cvx: MockConvexToken;
  let booster: MockBooster;
  let crvRewards: MockBaseRewardPool;
  let wConvexBooster: WConvexBooster;
  let escrowFactory: PoolEscrowFactory;

  beforeEach(async () => {
    [admin, alice] = await ethers.getSigners();

    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    lpToken = await MockERC20Factory.deploy('', '', 18);
    stakingToken = await MockERC20Factory.deploy('', '', 18);
    rewardToken = await MockERC20Factory.deploy('', '', 18);
    extraRewardToken = await MockERC20Factory.deploy('', '', 18);

    const MockConvexTokenFactory = await ethers.getContractFactory('MockConvexToken');
    cvx = await MockConvexTokenFactory.deploy();

    const MockBoosterFactory = await ethers.getContractFactory('MockBooster');
    booster = await MockBoosterFactory.deploy();

    const MockBaseRewardPoolFactory = await ethers.getContractFactory('MockBaseRewardPool');
    crvRewards = await MockBaseRewardPoolFactory.deploy(
      0,
      stakingToken.address,
      rewardToken.address,
      cvx.address,
      booster.address
    );

    await cvx.setOperator(crvRewards.address);

    const MockVirtualBalanceRewardPoolFactory = await ethers.getContractFactory('MockVirtualBalanceRewardPool');
    extraRewarder = await MockVirtualBalanceRewardPoolFactory.deploy(crvRewards.address, extraRewardToken.address);

    await crvRewards.addExtraReward(extraRewarder.address);

    const escrowFactoryFactory = await ethers.getContractFactory('PoolEscrowFactory');
    escrowFactory = <PoolEscrowFactory>await upgrades.deployProxy(escrowFactoryFactory, [admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await escrowFactory.deployed();

    const WConvexBoosterFactory = await ethers.getContractFactory(CONTRACT_NAMES.WConvexBooster);

    wConvexBooster = <WConvexBooster>await upgrades.deployProxy(
      WConvexBoosterFactory,
      [cvx.address, booster.address, escrowFactory.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    await booster.addPool(
      lpToken.address,
      stakingToken.address,
      generateRandomAddress(),
      crvRewards.address,
      generateRandomAddress()
    );

    await lpToken.mintWithAmount(utils.parseEther('10000000'));
    await lpToken.approve(wConvexBooster.address, utils.parseEther('10000000'));

    await lpToken.connect(alice).mintWithAmount(utils.parseEther('10000000'));
    await lpToken.connect(alice).approve(wConvexBooster.address, utils.parseEther('10000000'));
  });

  describe('#initialize', () => {
    it('check initial values', async () => {
      expect(await wConvexBooster.getCvxToken()).to.be.eq(cvx.address);
      expect(await wConvexBooster.getCvxBooster()).to.be.eq(booster.address);
    });

    it('should revert initializing twice', async () => {
      await expect(
        wConvexBooster.initialize(cvx.address, booster.address, escrowFactory.address, admin.address)
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });
  });

  describe('#encodeId', () => {
    it('encode id', async () => {
      const pid = BigNumber.from(1);
      const crvPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(crvPerShare);
      expect(await wConvexBooster.encodeId(pid, crvPerShare)).to.be.eq(id);
    });

    it('reverts if pid is equal or greater than 2 ^ 16', async () => {
      const pid = BigNumber.from(2).pow(16);
      const crvPerShare = BigNumber.from(100);

      await expect(wConvexBooster.encodeId(pid, crvPerShare)).to.be.revertedWithCustomError(wConvexBooster, 'BAD_PID');
    });

    it('reverts if crvPerShare is equal or greater than 2 ^ 240', async () => {
      const pid = BigNumber.from(2).pow(2);
      const crvPerShare = BigNumber.from(2).pow(240);

      await expect(wConvexBooster.encodeId(pid, crvPerShare)).to.be.revertedWithCustomError(
        wConvexBooster,
        'BAD_REWARD_PER_SHARE'
      );
    });
  });

  describe('#decodeId', () => {
    it('decode id', async () => {
      const pid = BigNumber.from(1);
      const crvPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(crvPerShare);
      const res = await wConvexBooster.decodeId(id);
      expect(res[0]).to.be.eq(pid);
      expect(res[1]).to.be.eq(crvPerShare);
    });
  });

  describe('#getUnderlyingToken', () => {
    const lptoken = generateRandomAddress();

    beforeEach(async () => {
      await booster.addPool(
        lptoken,
        generateRandomAddress(),
        generateRandomAddress(),
        generateRandomAddress(),
        generateRandomAddress()
      );
    });

    it('get underlying token', async () => {
      const pid = BigNumber.from(1);
      const crvPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(crvPerShare);
      expect(await wConvexBooster.getUnderlyingToken(id)).to.be.eq(lptoken);
    });
  });

  describe('#getPoolInfoFromPoolId', () => {
    const lptoken = generateRandomAddress();
    const token = generateRandomAddress();
    const gauge = generateRandomAddress();
    const crvRewards = generateRandomAddress();
    const stash = generateRandomAddress();

    beforeEach(async () => {
      await booster.addPool(lptoken, token, gauge, crvRewards, stash);
    });

    it('get pool info', async () => {
      const res = await wConvexBooster.getPoolInfoFromPoolId(1);
      expect(res[0]).to.be.eq(lptoken);
      expect(res[1]).to.be.eq(token);
      expect(res[2]).to.be.eq(gauge);
      expect(res[3]).to.be.eq(crvRewards);
      expect(res[4]).to.be.eq(stash);
      expect(res[5]).to.be.false;
    });
  });

  describe('#pendingRewards', () => {
    const crvPerShare = utils.parseEther('100');
    const tokenId = crvPerShare; // pid: 0
    const pid = 0;
    const amount = utils.parseEther('100');

    beforeEach(async () => {
      await crvRewards.setRewardPerToken(crvPerShare);
      await wConvexBooster.connect(alice).mint(pid, amount);
    });

    it('return zero at initial stage', async () => {
      const res = await wConvexBooster.pendingRewards(tokenId, amount);
      expect(res[0][0]).to.be.eq(rewardToken.address);
      expect(res[0][1]).to.be.eq(cvx.address);
      expect(res[1][0]).to.be.eq(0);
      expect(res[1][1]).to.be.eq(0);
    });

    describe('calculate reward[0]', () => {
      it('calculate reward[0] when its decimals is 18', async () => {
        const rewardPerToken = utils.parseEther('150');
        await crvRewards.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(rewardPerToken.sub(crvPerShare).mul(amount).div(BigNumber.from(10).pow(18)));
      });

      it('calculate reward[0] when its decimals is not 18', async () => {
        await lpToken.setDecimals(8);

        expect(await lpToken.decimals()).to.be.eq(8);

        const rewardPerToken = utils.parseEther('150');
        await crvRewards.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(rewardPerToken.sub(crvPerShare).mul(amount).div(BigNumber.from(10).pow(8)));
      });

      it('return 0 if rewardPerToken is lower than stRewardPerShare', async () => {
        const rewardPerToken = utils.parseEther('50');
        await crvRewards.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(0);
      });
    });

    describe('calculate reward[1]', () => {
      const rewardPerToken = utils.parseEther('150');
      let reward0: BigNumber;

      beforeEach(async () => {
        await crvRewards.setRewardPerToken(rewardPerToken);

        reward0 = rewardPerToken.sub(crvPerShare).mul(amount).div(BigNumber.from(10).pow(18));
      });

      it('return earned amount if CVX total supply is zero', async () => {
        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(reward0);
      });

      it('calculate CVX vesting amount if CVX total supply is not zero', async () => {
        const cvxSupply = utils.parseEther('10000');
        await cvx.mintTestTokens(stakingToken.address, cvxSupply);

        const reductionPerCliff = await cvx.reductionPerCliff();
        const totalCliffs = await cvx.totalCliffs();
        const cliff = cvxSupply.div(reductionPerCliff);

        expect(cliff.lt(totalCliffs)).to.be.true;

        const reduction = totalCliffs.sub(cliff);
        const mintAmount = reward0.mul(reduction).div(totalCliffs);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(mintAmount);
      });

      it('validate CVX cap for reward calculation', async () => {
        const cvxSupply = utils.parseEther('10000');
        await cvx.mintTestTokens(stakingToken.address, cvxSupply);

        const cvxMaxSupply = await cvx.maxSupply();

        await lpToken.mintWithAmount(cvxMaxSupply);
        await lpToken.approve(wConvexBooster.address, cvxMaxSupply);

        await wConvexBooster.mint(pid, cvxMaxSupply.sub(amount));

        await crvRewards.setRewardPerToken(utils.parseEther('200'));

        const reductionPerCliff = await cvx.reductionPerCliff();
        const totalCliffs = await cvx.totalCliffs();
        const cliff = cvxSupply.div(reductionPerCliff);

        expect(cliff.lt(totalCliffs)).to.be.true;

        reward0 = utils.parseEther('200').sub(rewardPerToken).mul(cvxMaxSupply).div(BigNumber.from(10).pow(18));

        const newTokenId = rewardPerToken;
        const res = await wConvexBooster.pendingRewards(newTokenId, cvxMaxSupply);
        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(cvxMaxSupply.sub(cvxSupply));
      });

      it('return 0 if cliff is equal or greater than totalCliffs (when supply is same as max)', async () => {
        const cvxMaxSupply = await cvx.maxSupply();
        await cvx.mintTestTokens(stakingToken.address, cvxMaxSupply);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][1]).to.be.eq(0);
      });
    });

    describe('calculate extraRewards', () => {
      const pid = 0;
      const amount = utils.parseEther('100');
      const prevRewardPerToken = utils.parseEther('50');
      const tokenId = crvPerShare;

      beforeEach(async () => {
        await extraRewarder.setRewardPerToken(prevRewardPerToken);
        await wConvexBooster.connect(alice).mint(pid, amount);
      });

      it('calculate reward[2] when its decimals is 18', async () => {
        const rewardPerToken = utils.parseEther('150');
        await extraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[0][2]).to.be.eq(extraRewardToken.address);
        expect(res[1][2]).to.be.eq(rewardPerToken.sub(prevRewardPerToken).mul(amount).div(BigNumber.from(10).pow(18)));
      });

      it('calculate reward[2] when its decimals is not 18', async () => {
        await lpToken.setDecimals(8);

        expect(await lpToken.decimals()).to.be.eq(8);

        const rewardPerToken = utils.parseEther('150');
        await extraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[0][2]).to.be.eq(extraRewardToken.address);
        expect(res[1][2]).to.be.eq(rewardPerToken.sub(prevRewardPerToken).mul(amount).div(BigNumber.from(10).pow(8)));
      });

      it('return 0 if rewardPerToken is lower than stRewardPerShare', async () => {
        const rewardPerToken = utils.parseEther('50');
        await extraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][2]).to.be.eq(0);
      });
    });
  });

  describe('#mint', () => {
    const pid = BigNumber.from(0);
    const amount = utils.parseEther('100');
    const crvRewardPerToken = utils.parseEther('50');
    const extraRewardPerToken = utils.parseEther('40');
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(crvRewardPerToken);

    beforeEach(async () => {
      await crvRewards.setRewardPerToken(crvRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);
    });

    it('deposit into cvxPools', async () => {
      await wConvexBooster.connect(alice).mint(pid, amount);

      const escrowContract = await wConvexBooster.getEscrow(pid);

      expect(await crvRewards.balanceOf(escrowContract)).to.be.eq(amount);
      expect(await lpToken.balanceOf(escrowContract)).to.be.eq(0);
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(amount);
      expect(await stakingToken.balanceOf(crvRewards.address)).to.be.eq(amount);
    });

    it('mint ERC1155 NFT', async () => {
      await wConvexBooster.connect(alice).mint(pid, amount);

      expect(await wConvexBooster.balanceOf(alice.address, tokenId)).to.be.eq(amount);
    });

    it('sync extra reward info', async () => {
      await wConvexBooster.connect(alice).mint(pid, amount);

      expect(await wConvexBooster.getInitialTokenPerShare(tokenId, extraRewarder.address)).to.be.eq(
        extraRewardPerToken
      );

      expect(await wConvexBooster.extraRewardsLength(pid)).to.be.eq(1);
      expect(await wConvexBooster.getExtraRewarder(pid, 0)).to.be.eq(extraRewarder.address);
    });

    it('keep existing extra reward info when syncing', async () => {
      await wConvexBooster.connect(alice).mint(pid, amount);
      await wConvexBooster.connect(alice).mint(pid, amount);

      expect(await wConvexBooster.extraRewardsLength(pid)).to.be.eq(1);
      expect(await wConvexBooster.getExtraRewarder(pid, 0)).to.be.eq(extraRewarder.address);
    });
  });

  describe('#burn', () => {
    const pid = BigNumber.from(0);
    const mintAmount = utils.parseEther('100');
    const amount = utils.parseEther('60');
    const crvRewardPerToken = utils.parseEther('50');
    const extraRewardPerToken = utils.parseEther('40');
    const newCrvRewardPerToken = utils.parseEther('60');
    const newExtraRewardPerToken = utils.parseEther('70');
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(crvRewardPerToken);

    beforeEach(async () => {
      await crvRewards.setRewardPerToken(crvRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);

      await wConvexBooster.connect(alice).mint(pid, mintAmount);

      await rewardToken.mintTo(crvRewards.address, utils.parseEther('10000000000'));
      await extraRewardToken.mintTo(extraRewarder.address, utils.parseEther('10000000000'));

      await crvRewards.setRewardPerToken(newCrvRewardPerToken);
      await extraRewarder.setRewardPerToken(newExtraRewardPerToken);

      const escrowContract = await wConvexBooster.getEscrow(pid);

      const res = await wConvexBooster.pendingRewards(tokenId, mintAmount);
      await crvRewards.setReward(escrowContract, res[1][0]);
      await extraRewarder.setReward(escrowContract, res[1][2]);
    });

    it('withdraw from cvxPools', async () => {
      const balBefore = await lpToken.balanceOf(alice.address);

      await wConvexBooster.connect(alice).burn(tokenId, amount);

      const escrowContract = await wConvexBooster.getEscrow(pid);

      expect(await crvRewards.balanceOf(escrowContract)).to.be.eq(mintAmount.sub(amount));
      expect(await lpToken.balanceOf(escrowContract)).to.be.eq(0);
      expect(await lpToken.balanceOf(alice.address)).to.be.eq(balBefore.add(amount));
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(mintAmount.sub(amount));
      expect(await stakingToken.balanceOf(crvRewards.address)).to.be.eq(mintAmount.sub(amount));
    });

    it('burn ERC1155 NFT', async () => {
      await wConvexBooster.connect(alice).burn(tokenId, amount);

      expect(await wConvexBooster.balanceOf(alice.address, tokenId)).to.be.eq(mintAmount.sub(amount));
    });

    it('receive rewards', async () => {
      const res = await wConvexBooster.pendingRewards(tokenId, amount);

      await wConvexBooster.connect(alice).burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);
      expect(await cvx.balanceOf(alice.address)).to.be.eq(res[1][1]);
      expect(await extraRewardToken.balanceOf(alice.address)).to.be.eq(res[1][2]);
    });

    it('claim extra reward manually due to extra info mismatch', async () => {
      const res = await wConvexBooster.pendingRewards(tokenId, amount);

      await crvRewards.clearExtraRewards();
      await wConvexBooster.connect(alice).burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);
      expect(await cvx.balanceOf(alice.address)).to.be.eq(res[1][1]);
      expect(await extraRewardToken.balanceOf(alice.address)).to.be.eq(res[1][2]);
    });
  });
});
