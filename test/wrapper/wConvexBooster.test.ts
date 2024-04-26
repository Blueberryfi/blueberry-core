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
  MockStashToken,
  PoolEscrowFactory,
} from '../../typechain-types';
import { generateRandomAddress } from '../helpers';

describe('wConvexBooster', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let lpToken: MockERC20;
  let stashToken: MockStashToken;
  let stash: MockERC20;
  let extraRewarder: MockVirtualBalanceRewardPool;
  let stakingToken: MockERC20;
  let rewardToken: MockERC20;
  let cvx: MockConvexToken;
  let booster: MockBooster;
  let cvxRewarder: MockBaseRewardPool;
  let wConvexBooster: WConvexBooster;
  let escrowFactory: PoolEscrowFactory;

  beforeEach(async () => {
    [admin, alice, bob] = await ethers.getSigners();

    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    lpToken = await MockERC20Factory.deploy('', '', 18);
    stakingToken = await MockERC20Factory.deploy('', '', 18);
    rewardToken = await MockERC20Factory.deploy('', '', 18);
    stash = await MockERC20Factory.deploy('', '', 18);

    const MockStashTokenFactory = await ethers.getContractFactory('MockStashToken');
    stashToken = await MockStashTokenFactory.deploy();
    await stashToken.setTotalSupply(utils.parseEther('1000000000'));
    await stashToken.setStash(stash.address);

    const MockConvexTokenFactory = await ethers.getContractFactory('MockConvexToken');
    cvx = await MockConvexTokenFactory.deploy();

    // Add base tokens to the stash token
    cvx.mintTestTokens(stashToken.address, await stashToken.totalSupply());

    const MockBoosterFactory = await ethers.getContractFactory('MockBooster');
    booster = await MockBoosterFactory.deploy();

    const MockBaseRewardPoolFactory = await ethers.getContractFactory('MockBaseRewardPool');

    cvxRewarder = await MockBaseRewardPoolFactory.deploy(
      0,
      stakingToken.address,
      rewardToken.address,
      cvx.address,
      booster.address
    );

    await cvx.setOperator(cvxRewarder.address);

    const MockVirtualBalanceRewardPoolFactory = await ethers.getContractFactory('MockVirtualBalanceRewardPool');
    extraRewarder = await MockVirtualBalanceRewardPoolFactory.deploy(cvxRewarder.address, stashToken.address);
    await stashToken.init(extraRewarder.address, cvx.address);
    await cvxRewarder.addExtraReward(extraRewarder.address);

    const escrowFactoryFactory = await ethers.getContractFactory('PoolEscrowFactory');
    escrowFactory = <PoolEscrowFactory>await upgrades.deployProxy(escrowFactoryFactory, [admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await escrowFactory.deployed();

    const wConvexBoosterFactory = await ethers.getContractFactory(CONTRACT_NAMES.WConvexBooster);
    wConvexBooster = <WConvexBooster>await upgrades.deployProxy(
      wConvexBoosterFactory,
      [cvx.address, booster.address, escrowFactory.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    await booster.addPool(
      lpToken.address,
      stakingToken.address,
      generateRandomAddress(),
      cvxRewarder.address,
      await stashToken.stash()
    );

    await lpToken.mintWithAmount(utils.parseEther('10000000'));
    await lpToken.approve(wConvexBooster.address, utils.parseEther('10000000'));

    await lpToken.connect(alice).mintWithAmount(utils.parseEther('10000000'));
    await lpToken.connect(alice).approve(wConvexBooster.address, utils.parseEther('10000000'));

    await lpToken.connect(bob).mintWithAmount(utils.parseEther('10000000'));
    await lpToken.connect(bob).approve(wConvexBooster.address, utils.parseEther('10000000'));

    await booster.setRewardMultipliers(cvxRewarder.address, await booster.REWARD_MULTIPLIER_DENOMINATOR());
  });

  describe('#initialize', () => {
    it('check initial values', async () => {
      expect(await wConvexBooster.getCvxToken()).to.be.eq(cvx.address);
      expect(await wConvexBooster.getCvxBooster()).to.be.eq(booster.address);
      expect(await wConvexBooster.getEscrowFactory()).to.be.eq(escrowFactory.address);
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
      const cvxPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(cvxPerShare);
      expect(await wConvexBooster.encodeId(pid, cvxPerShare)).to.be.eq(id);
    });

    it('reverts if pid is equal or greater than 2 ^ 16', async () => {
      const pid = BigNumber.from(2).pow(16);
      const cvxPerShare = BigNumber.from(100);

      await expect(wConvexBooster.encodeId(pid, cvxPerShare)).to.be.revertedWithCustomError(wConvexBooster, 'BAD_PID');
    });

    it('reverts if cvxPerShare is equal or greater than 2 ^ 240', async () => {
      const pid = BigNumber.from(2).pow(2);
      const cvxPerShare = BigNumber.from(2).pow(240);

      await expect(wConvexBooster.encodeId(pid, cvxPerShare)).to.be.revertedWithCustomError(
        wConvexBooster,
        'BAD_REWARD_PER_SHARE'
      );
    });
  });

  describe('#decodeId', () => {
    it('decode id', async () => {
      const pid = BigNumber.from(1);
      const cvxPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(cvxPerShare);
      const res = await wConvexBooster.decodeId(id);
      expect(res[0]).to.be.eq(pid);
      expect(res[1]).to.be.eq(cvxPerShare);
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
      const cvxPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(cvxPerShare);
      expect(await wConvexBooster.getUnderlyingToken(id)).to.be.eq(lptoken);
    });
  });

  describe('#getPoolInfoFromPoolId', () => {
    const lptoken = generateRandomAddress();
    const token = generateRandomAddress();
    const gauge = generateRandomAddress();
    const cvxRewarder = generateRandomAddress();
    const stash = generateRandomAddress();

    beforeEach(async () => {
      await booster.addPool(lptoken, token, gauge, cvxRewarder, stash);
    });

    it('get pool info', async () => {
      const res = await wConvexBooster.getPoolInfoFromPoolId(1);
      expect(res[0]).to.be.eq(lptoken);
      expect(res[1]).to.be.eq(token);
      expect(res[2]).to.be.eq(gauge);
      expect(res[3]).to.be.eq(cvxRewarder);
      expect(res[4]).to.be.eq(stash);
      expect(res[5]).to.be.false;
    });
  });

  describe('#pendingRewards', () => {
    const cvxPerShare = utils.parseEther('100');
    const tokenId = cvxPerShare; // pid: 0
    const amount = utils.parseEther('100');
    const pid = 0;

    beforeEach(async () => {
      await cvxRewarder.setRewardPerToken(cvxPerShare);
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
        await cvxRewarder.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(rewardPerToken.sub(cvxPerShare).mul(amount).div(BigNumber.from(10).pow(18)));
      });

      it('return 0 if rewardPerToken is lower than stRewardPerShare', async () => {
        const rewardPerToken = utils.parseEther('50');
        await cvxRewarder.setRewardPerToken(rewardPerToken);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(0);
      });
    });

    describe('calculate reward[0]', () => {
      const rewardPerToken = utils.parseEther('150');
      let reward0: BigNumber;

      beforeEach(async () => {
        await cvxRewarder.setRewardPerToken(rewardPerToken);

        reward0 = rewardPerToken.sub(cvxPerShare).mul(amount).div(BigNumber.from(10).pow(18));
      });

      it('return earned amount if AURA total supply is initial amount', async () => {
        const res = await wConvexBooster.pendingRewards(tokenId, amount);

        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(await getCvxMintAmount(reward0));
      });

      it('calculate AURA vesting amount if AURA total supply is greater than inital amount', async () => {
        const cvxSupply = utils.parseEther('10000');
        await cvx.mintTestTokens(stakingToken.address, cvxSupply);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(await getCvxMintAmount(reward0));
      });

      it('validate AURA cap for reward calculation', async () => {
        const cvxSupply = utils.parseUnits('5', 25);
        await cvx.mintTestTokens(stakingToken.address, cvxSupply);

        const cvxMaxSupply = await cvx.maxSupply();

        await lpToken.mintWithAmount(cvxMaxSupply);
        await lpToken.approve(wConvexBooster.address, cvxMaxSupply);

        await wConvexBooster.mint(pid, cvxMaxSupply.sub(amount));

        await cvxRewarder.setRewardPerToken(utils.parseEther('200'));

        reward0 = utils.parseEther('200').sub(rewardPerToken).mul(cvxMaxSupply).div(BigNumber.from(10).pow(18));

        const newTokenId = rewardPerToken;

        await wConvexBooster.pendingRewards(newTokenId, cvxMaxSupply);
      });

      it('return 0 if cliff is equal or greater than totalCliffs (when supply is same as max)', async () => {
        const cvxMaxSupply = await cvx.maxSupply();
        await cvx.mintTestTokens(stakingToken.address, cvxMaxSupply);

        const res = await wConvexBooster.pendingRewards(tokenId, amount);
        expect(res[1][1]).to.be.eq(0);
      });
    });
  });

  describe('#mint', () => {
    const pid = BigNumber.from(0);
    const amount = utils.parseEther('100');
    const amount2 = utils.parseEther('150');
    const cvxRewardPerToken = utils.parseEther('50');
    const extraRewardPerToken = utils.parseEther('40');
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(cvxRewardPerToken);

    beforeEach(async () => {
      await cvxRewarder.setRewardPerToken(cvxRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);
    });

    it('deposit into CvxBooster', async () => {
      await wConvexBooster.connect(alice).mint(pid, amount);

      const escrowContract = await wConvexBooster.getEscrow(pid);

      expect(await cvxRewarder.balanceOf(escrowContract)).to.be.eq(amount);
      expect(await lpToken.balanceOf(escrowContract)).to.be.eq(0);
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(amount);
      expect(await stakingToken.balanceOf(cvxRewarder.address)).to.be.eq(amount);
    });

    it('mint ERC1155 NFT', async () => {
      await wConvexBooster.connect(alice).mint(pid, amount);
      await wConvexBooster.connect(bob).mint(pid, amount2);

      expect(await wConvexBooster.balanceOf(bob.address, tokenId)).to.be.eq(amount2);
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
      await cvxRewarder.setRewardPerToken(cvxRewardPerToken.add(1));
      await wConvexBooster.connect(alice).mint(pid, amount);
      expect(await wConvexBooster.extraRewardsLength(pid)).to.be.eq(1);
      expect(await wConvexBooster.getExtraRewarder(pid, 0)).to.be.eq(extraRewarder.address);
    });
  });

  describe('#burn', () => {
    const pid = BigNumber.from(0);
    const mintAmount = utils.parseEther('100');
    const amount = utils.parseEther('60');
    const cvxRewardPerToken = utils.parseEther('50');
    const extraRewardPerToken = utils.parseEther('40');
    const newcvxRewardPerToken = utils.parseEther('60');
    const newExtraRewardPerToken = utils.parseEther('60');
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(cvxRewardPerToken);

    beforeEach(async () => {
      await cvxRewarder.setRewardPerToken(cvxRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);

      await wConvexBooster.connect(alice).mint(pid, mintAmount);

      await rewardToken.mintTo(cvxRewarder.address, utils.parseEther('10000000000'));
      await cvx.mintTestTokens(extraRewarder.address, utils.parseEther('10000000000'));

      await cvxRewarder.setRewardPerToken(newcvxRewardPerToken);
      await extraRewarder.setRewardPerToken(newExtraRewardPerToken);

      const escrowContract = await wConvexBooster.getEscrow(pid);

      const res = await wConvexBooster.pendingRewards(tokenId, mintAmount);
      await cvxRewarder.setReward(escrowContract, res[1][0]);
      await extraRewarder.setReward(escrowContract, res[1][1]);
    });

    it('withdraw from CvxBooster', async () => {
      const balBefore = await lpToken.balanceOf(alice.address);

      await wConvexBooster.connect(alice).burn(tokenId, amount);

      const escrowContract = await wConvexBooster.getEscrow(pid);

      expect(await cvxRewarder.balanceOf(escrowContract)).to.be.eq(mintAmount.sub(amount));
      expect(await lpToken.balanceOf(escrowContract)).to.be.eq(0);
      expect(await lpToken.balanceOf(alice.address)).to.be.eq(balBefore.add(amount));
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(mintAmount.sub(amount));
      expect(await stakingToken.balanceOf(cvxRewarder.address)).to.be.eq(mintAmount.sub(amount));
    });

    it('burn ERC1155 NFT', async () => {
      await wConvexBooster.connect(alice).burn(tokenId, amount);

      expect(await wConvexBooster.balanceOf(alice.address, tokenId)).to.be.eq(mintAmount.sub(amount));
    });

    it('receive rewards', async () => {
      const res = await wConvexBooster.pendingRewards(tokenId, amount);

      await wConvexBooster.connect(alice).burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);
      expect(await cvx.balanceOf(alice.address)).to.be.gte(res[1][1]);
    });
    it('claim extra reward manually due to extra info mismatch', async () => {
      const res = await wConvexBooster.pendingRewards(tokenId, amount);
      const beforeAliceBalance = await cvx.balanceOf(alice.address);
      await cvxRewarder.clearExtraRewards();

      await extraRewarder.setReward(await wConvexBooster.getEscrow(pid), utils.parseEther('2000'));

      await wConvexBooster.connect(alice).burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);

      expect(await cvx.balanceOf(alice.address)).to.be.greaterThan(beforeAliceBalance);
    });
  });

  const getCvxMintAmount = async (amount: BigNumber) => {
    const INIT_MINT_AMOUNT = utils.parseUnits('5', 25);
    const EMISSIONS_MAX_SUPPLY = utils.parseUnits('5', 25);
    const totalCliffs = BigNumber.from(500);

    const reductionPerCliff = EMISSIONS_MAX_SUPPLY.div(totalCliffs);

    const totalSupply = await cvx.totalSupply();
    const emissionsMinted = totalSupply.sub(INIT_MINT_AMOUNT);
    const cliff = emissionsMinted.div(reductionPerCliff);

    if (cliff.lt(totalCliffs)) {
      const reduction = totalCliffs.sub(cliff).mul(5).div(2).add(700);
      amount = amount.mul(reduction).div(totalCliffs);

      const amtTillMax = EMISSIONS_MAX_SUPPLY.sub(emissionsMinted);
      if (amount.gt(amtTillMax)) {
        amount = amtTillMax;
      }

      return amount;
    }

    return BigNumber.from(0);
  };
});
