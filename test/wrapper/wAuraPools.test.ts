import chai, { expect } from "chai";
import { BigNumber, constants, utils } from "ethers";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { CONTRACT_NAMES } from "../../constant";
import {
  WAuraPools,
  MockAuraToken,
  MockBooster,
  MockERC20,
  MockBaseRewardPool,
  MockVirtualBalanceRewardPool,
  MockStashToken,
  PoolEscrow,
  PoolEscrowFactory,
} from "../../typechain-types";
import { evm_increaseTime, evm_mine_blocks, generateRandomAddress } from "../helpers";

describe("wAuraPools", () => {
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let lpToken: MockERC20;
  let stashToken: MockStashToken;
  let stash: MockERC20;
  let extraRewarder: MockVirtualBalanceRewardPool;
  let stakingToken: MockERC20;
  let rewardToken: MockERC20;
  let aura: MockAuraToken;
  let booster: MockBooster;
  let auraRewarder: MockBaseRewardPool;
  let wAuraPools: WAuraPools;
  let escrowBase: PoolEscrow;
  let escrowFactory: PoolEscrowFactory;

  beforeEach(async () => {
    [alice, bob] = await ethers.getSigners();

    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    lpToken = await MockERC20Factory.deploy("", "", 18);
    stakingToken = await MockERC20Factory.deploy("", "", 18);
    rewardToken = await MockERC20Factory.deploy("", "", 18);
    stash = await MockERC20Factory.deploy("", "", 18);

    const MockStashTokenFactory = await ethers.getContractFactory(
      "MockStashToken" 
    );
    stashToken = await MockStashTokenFactory.deploy();
    await stashToken.setTotalSupply(utils.parseEther("1000000000"));
    await stashToken.setStash(stash.address);

    const MockConvexTokenFactory = await ethers.getContractFactory(
      "MockAuraToken"
    );
    aura = await MockConvexTokenFactory.deploy();
    
    // Add base tokens to the stash token
    aura.mintTestTokens(stashToken.address, await stashToken.totalSupply());
    
    const MockBoosterFactory = await ethers.getContractFactory("MockBooster");
    booster = await MockBoosterFactory.deploy();

    const MockBaseRewardPoolFactory = await ethers.getContractFactory(
      "MockBaseRewardPool"
    );

    auraRewarder = await MockBaseRewardPoolFactory.deploy(
      0,
      stakingToken.address,
      rewardToken.address,
      aura.address,
      booster.address,
    );

    await aura.setOperator(auraRewarder.address);

    const MockVirtualBalanceRewardPoolFactory = await ethers.getContractFactory(
      "MockVirtualBalanceRewardPool"
    );
    extraRewarder = await MockVirtualBalanceRewardPoolFactory.deploy(
      auraRewarder.address,
      stashToken.address,
    );    
    await stashToken.init(extraRewarder.address, aura.address);
    await auraRewarder.addExtraReward(extraRewarder.address);

    const escrowBaseFactory = await ethers.getContractFactory("PoolEscrow");
    escrowBase = await escrowBaseFactory.deploy();

    const escrowFactoryFactory = await ethers.getContractFactory(
      "PoolEscrowFactory"
    );
    escrowFactory = await escrowFactoryFactory.deploy(escrowBase.address);

    const wAuraPoolsFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.WAuraPools
    );
    wAuraPools = <WAuraPools>(
      await upgrades.deployProxy(
        wAuraPoolsFactory,
        [
          aura.address,
          booster.address,
          escrowFactory.address,
        ],
        { unsafeAllow: ["delegatecall"] }
      )
    );

    escrowFactory.initialize(wAuraPools.address, booster.address);

    await booster.addPool(
      lpToken.address,
      stakingToken.address,
      generateRandomAddress(),
      auraRewarder.address,
      await stashToken.stash()
    );

    await lpToken.mintWithAmount(utils.parseEther("10000000"));
    await lpToken.approve(wAuraPools.address, utils.parseEther("10000000"));

    await lpToken.connect(bob).mintWithAmount(utils.parseEther("10000000"));
    await lpToken
      .connect(bob)
      .approve(wAuraPools.address, utils.parseEther("10000000"));

    await booster.setRewardMultipliers(
      auraRewarder.address,
      await booster.REWARD_MULTIPLIER_DENOMINATOR()
    );
  });

  describe("#initialize", () => {
    it("check initial values", async () => {
      expect(await wAuraPools.AURA()).to.be.eq(aura.address);
      expect(await wAuraPools.auraBooster()).to.be.eq(booster.address);
      expect(await wAuraPools.escrowFactory()).to.be.eq(escrowFactory.address);
    });

    it("should revert initializing twice", async () => {
      await expect(
        wAuraPools.initialize(
          aura.address,
          booster.address,
          escrowFactory.address
        )
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("#encodeId", () => {
    it("encode id", async () => {
      const pid = BigNumber.from(1);
      const auraPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(auraPerShare);
      expect(await wAuraPools.encodeId(pid, auraPerShare)).to.be.eq(id);
    });

    it("reverts if pid is equal or greater than 2 ^ 16", async () => {
      const pid = BigNumber.from(2).pow(16);
      const auraPerShare = BigNumber.from(100);

      await expect(
        wAuraPools.encodeId(pid, auraPerShare)
      ).to.be.revertedWithCustomError(wAuraPools, "BAD_PID");
    });

    it("reverts if auraPerShare is equal or greater than 2 ^ 240", async () => {
      const pid = BigNumber.from(2).pow(2);
      const auraPerShare = BigNumber.from(2).pow(240);

      await expect(
        wAuraPools.encodeId(pid, auraPerShare)
      ).to.be.revertedWithCustomError(wAuraPools, "BAD_REWARD_PER_SHARE");
    });
  });

  describe("#decodeId", () => {
    it("decode id", async () => {
      const pid = BigNumber.from(1);
      const auraPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(auraPerShare);
      const res = await wAuraPools.decodeId(id);
      expect(res[0]).to.be.eq(pid);
      expect(res[1]).to.be.eq(auraPerShare);
    });
  });

  describe("#getUnderlyingToken", () => {
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

    it("get underlying token", async () => {
      const pid = BigNumber.from(1);
      const auraPerShare = BigNumber.from(100);

      const id = pid.mul(BigNumber.from(2).pow(240)).add(auraPerShare);
      expect(await wAuraPools.getUnderlyingToken(id)).to.be.eq(lptoken);
    });
  });

  describe("#getPoolInfoFromPoolId", () => {
    const lptoken = generateRandomAddress();
    const token = generateRandomAddress();
    const gauge = generateRandomAddress();
    const auraRewarder = generateRandomAddress();
    const stash = generateRandomAddress();

    beforeEach(async () => {
      await booster.addPool(lptoken, token, gauge, auraRewarder, stash);
    });

    it("get pool info", async () => {
      const res = await wAuraPools.getPoolInfoFromPoolId(1);
      expect(res[0]).to.be.eq(lptoken);
      expect(res[1]).to.be.eq(token);
      expect(res[2]).to.be.eq(gauge);
      expect(res[3]).to.be.eq(auraRewarder);
      expect(res[4]).to.be.eq(stash);
      expect(res[5]).to.be.false;
    });
  });

  describe("#pendingRewards", () => {
    const auraPerShare = utils.parseEther("100");
    const tokenId = auraPerShare; // pid: 0
    const amount = utils.parseEther("100");
    const pid = 0;

    beforeEach(async () => {
      await auraRewarder.setRewardPerToken(auraPerShare);
      await wAuraPools.mint(pid, amount);
    });

    it("return zero at initial stage", async () => {
      const res = await wAuraPools.pendingRewards(tokenId, amount);

      expect(res[0][0]).to.be.eq(rewardToken.address);
      expect(res[0][1]).to.be.eq(aura.address);
      expect(res[1][0]).to.be.eq(0);
      expect(res[1][1]).to.be.eq(0);
    });

    describe("calculate reward[0]", () => {
      it("calculate reward[0] when its decimals is 18", async () => {
        const rewardPerToken = utils.parseEther("150");
        await auraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(
          rewardPerToken
            .sub(auraPerShare)
            .mul(amount)
            .div(BigNumber.from(10).pow(18))
        );
      });

      it("return 0 if rewardPerToken is lower than stRewardPerShare", async () => {
        const rewardPerToken = utils.parseEther("50");
        await auraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(0);
      });
    });

    describe("calculate reward[0]", () => {
      const rewardPerToken = utils.parseEther("150");
      let reward0: BigNumber;

      beforeEach(async () => {
        await auraRewarder.setRewardPerToken(rewardPerToken);

        reward0 = rewardPerToken
          .sub(auraPerShare)
          .mul(amount)
          .div(BigNumber.from(10).pow(18));
      });

      it("return earned amount if AURA total supply is initial amount", async () => {
        const res = await wAuraPools.pendingRewards(tokenId, amount);

        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(await getAuraMintAmount(reward0));
      });

      it("calculate AURA vesting amount if AURA total supply is greater than inital amount", async () => {
        const auraSupply = utils.parseEther("10000");
        await aura.mintTestTokens(stakingToken.address, auraSupply);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(await getAuraMintAmount(reward0));
      });

      it("validate AURA cap for reward calculation", async () => {
        const auraSupply = utils.parseUnits("5", 25);
        await aura.mintTestTokens(stakingToken.address, auraSupply);

        const auraMaxSupply = await aura.EMISSIONS_MAX_SUPPLY();

        await lpToken.mintWithAmount(auraMaxSupply);
        await lpToken.approve(wAuraPools.address, auraMaxSupply);

        await wAuraPools.mint(pid, auraMaxSupply.sub(amount));

        await auraRewarder.setRewardPerToken(utils.parseEther("200"));

        reward0 = utils
          .parseEther("200")
          .sub(rewardPerToken)
          .mul(auraMaxSupply)
          .div(BigNumber.from(10).pow(18));

        const newTokenId = rewardPerToken;

        const res = await wAuraPools.pendingRewards(newTokenId, auraMaxSupply);

      });

      it("return 0 if cliff is equal or greater than totalCliffs (when supply is same as max)", async () => {
        const auraMaxSupply = await aura.EMISSIONS_MAX_SUPPLY();
        await aura.mintTestTokens(stakingToken.address, auraMaxSupply);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][1]).to.be.eq(0);
      });
    });
  });

  describe("#mint", () => {
    const pid = BigNumber.from(0);
    const amount = utils.parseEther("100");
    const amount2 = utils.parseEther("150");
    const auraRewardPerToken = utils.parseEther("50");
    const extraRewardPerToken = utils.parseEther("40");
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(auraRewardPerToken);

    beforeEach(async () => {
      await auraRewarder.setRewardPerToken(auraRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);
    });

    it("deposit into auraPools", async () => {
      await wAuraPools.mint(pid, amount);

      const escrowContract = await wAuraPools.getEscrow(pid);

      expect(await auraRewarder.balanceOf(escrowContract)).to.be.eq(amount);
      expect(await lpToken.balanceOf(escrowContract)).to.be.eq(0);
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(amount);
      expect(await stakingToken.balanceOf(auraRewarder.address)).to.be.eq(
        amount
      );
    });

    it("mint ERC1155 NFT", async () => {
      await wAuraPools.connect(alice).mint(pid, amount);
      await wAuraPools.connect(bob).mint(pid, amount2);

      expect(await wAuraPools.balanceOf(bob.address, tokenId)).to.be.eq(
        amount2
      );
      expect(await wAuraPools.balanceOf(alice.address, tokenId)).to.be.eq(
        amount
      );
    });

    it("sync extra reward info", async () => {
      await wAuraPools.mint(pid, amount);

      expect(
        await wAuraPools.accExtPerShare(tokenId, extraRewarder.address)
      ).to.be.eq(extraRewardPerToken);

      expect(await wAuraPools.extraRewardsLength(pid)).to.be.eq(1);
      expect(await wAuraPools.getExtraRewarder(pid, 0)).to.be.eq(extraRewarder.address);
    });

    it("keep existing extra reward info when syncing", async () => {
      await wAuraPools.mint(pid, amount);
      await wAuraPools.mint(pid, amount);
      expect(await wAuraPools.extraRewardsLength(pid)).to.be.eq(1);
      expect(await wAuraPools.getExtraRewarder(pid, 0)).to.be.eq(extraRewarder.address);
    });
  });

  describe("#burn", () => {
    const pid = BigNumber.from(0);
    const mintAmount = utils.parseEther("100");
    const amount = utils.parseEther("60");
    const auraRewardPerToken = utils.parseEther("50");
    const extraRewardPerToken = utils.parseEther("40");
    const newauraRewardPerToken = utils.parseEther("60");
    const newExtraRewardPerToken = utils.parseEther("60");
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(auraRewardPerToken);

    beforeEach(async () => {
      await auraRewarder.setRewardPerToken(auraRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);

      await wAuraPools.mint(pid, mintAmount);

      await rewardToken.mintTo(
        auraRewarder.address,
        utils.parseEther("10000000000")
      );
      await aura.mintTestTokens(
        extraRewarder.address,
        utils.parseEther("10000000000")
      );
      
      await auraRewarder.setRewardPerToken(newauraRewardPerToken);
      await extraRewarder.setRewardPerToken(newExtraRewardPerToken);

      const escrowContract = await wAuraPools.getEscrow(pid);

      const res = await wAuraPools.pendingRewards(tokenId, mintAmount);
      await auraRewarder.setReward(escrowContract, res[1][0]);
      await extraRewarder.setReward(escrowContract, res[1][1]);
    });

    it("withdraw from auraPools", async () => {
      const balBefore = await lpToken.balanceOf(alice.address);
      
      await wAuraPools.burn(tokenId, amount);

      const escrowContract = await wAuraPools.getEscrow(pid);

      expect(await auraRewarder.balanceOf(escrowContract)).to.be.eq(
        mintAmount.sub(amount)
      );
      expect(await lpToken.balanceOf(escrowContract)).to.be.eq(0);
      expect(await lpToken.balanceOf(alice.address)).to.be.eq(
        balBefore.add(amount)
      );
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(
        mintAmount.sub(amount)
      );
      expect(await stakingToken.balanceOf(auraRewarder.address)).to.be.eq(
        mintAmount.sub(amount)
      );
    });

    it("burn ERC1155 NFT", async () => {
      await wAuraPools.burn(tokenId, amount);

      expect(await wAuraPools.balanceOf(alice.address, tokenId)).to.be.eq(
        mintAmount.sub(amount)
      );
    });

    it("receive rewards", async () => {
      const res = await wAuraPools.pendingRewards(tokenId, amount);

      let beforeAliceBalance = await aura.balanceOf(alice.address);
      await wAuraPools.burn(tokenId, amount);

      let expectedAuraRewards = newauraRewardPerToken
      .sub(auraRewardPerToken)
      .mul(amount)
      .div(BigNumber.from(10).pow(8));

      let expectedStashRewards = newExtraRewardPerToken
        .sub(extraRewardPerToken)

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);
      expect(await aura.balanceOf(alice.address)).to.be.gte(res[1][1]);
    });
    it("claim extra reward manually due to extra info mismatch", async () => {
      const res = await wAuraPools.pendingRewards(tokenId, amount);
      let beforeAliceBalance = await aura.balanceOf(alice.address);
      await auraRewarder.clearExtraRewards();
      
      await extraRewarder.setReward(await wAuraPools.getEscrow(pid), utils.parseEther("2000"));

      await wAuraPools.burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);

      expect(await aura.balanceOf(alice.address)).to.be.greaterThan(beforeAliceBalance);
    });
  });

  const getAuraMintAmount = async (amount: BigNumber) => {
    const INIT_MINT_AMOUNT = utils.parseUnits("5", 25);
    const EMISSIONS_MAX_SUPPLY = utils.parseUnits("5", 25);
    const totalCliffs = BigNumber.from(500);

    const reductionPerCliff = EMISSIONS_MAX_SUPPLY.div(totalCliffs);

    const totalSupply = await aura.totalSupply();
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
