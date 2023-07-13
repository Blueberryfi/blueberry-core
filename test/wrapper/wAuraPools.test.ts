import chai, { expect } from "chai";
import { BigNumber, utils } from "ethers";
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
} from "../../typechain-types";
import { generateRandomAddress } from "../helpers";

describe("wAuraPools", () => {
  let alice: SignerWithAddress;

  let lpToken: MockERC20;
  let stashToken: MockStashToken;
  let extraRewarder: MockVirtualBalanceRewardPool;
  let stakingToken: MockERC20;
  let rewardToken: MockERC20;
  let extraRewardToken: MockERC20;
  let aura: MockAuraToken;
  let booster: MockBooster;
  let auraRewarder: MockBaseRewardPool;
  let wAuraPools: WAuraPools;

  beforeEach(async () => {
    [alice] = await ethers.getSigners();

    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    lpToken = await MockERC20Factory.deploy("", "", 18);
    stakingToken = await MockERC20Factory.deploy("", "", 18);
    rewardToken = await MockERC20Factory.deploy("", "", 18);
    extraRewardToken = await MockERC20Factory.deploy("", "", 18);

    const MockStashTokenFactory = await ethers.getContractFactory(
      "MockStashToken"
    );
    stashToken = await MockStashTokenFactory.deploy();

    const MockBaseRewardPoolFactory = await ethers.getContractFactory(
      "MockBaseRewardPool"
    );
    auraRewarder = await MockBaseRewardPoolFactory.deploy(
      0,
      stakingToken.address,
      rewardToken.address
    );

    const MockVirtualBalanceRewardPoolFactory = await ethers.getContractFactory(
      "MockVirtualBalanceRewardPool"
    );
    extraRewarder = await MockVirtualBalanceRewardPoolFactory.deploy(
      auraRewarder.address,
      extraRewardToken.address
    );

    await auraRewarder.addExtraReward(extraRewarder.address);

    const MockConvexTokenFactory = await ethers.getContractFactory(
      "MockAuraToken"
    );
    aura = await MockConvexTokenFactory.deploy();
    const MockBoosterFactory = await ethers.getContractFactory("MockBooster");
    booster = await MockBoosterFactory.deploy();

    const wAuraPoolsFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.WAuraPools
    );
    wAuraPools = <WAuraPools>(
      await upgrades.deployProxy(wAuraPoolsFactory, [
        aura.address,
        booster.address,
        stashToken.address,
      ])
    );

    await booster.addPool(
      lpToken.address,
      stakingToken.address,
      generateRandomAddress(),
      auraRewarder.address,
      generateRandomAddress()
    );

    await lpToken.mintWithAmount(utils.parseEther("10000000"));
    await lpToken.approve(wAuraPools.address, utils.parseEther("10000000"));

    await booster.setRewardMultipliers(
      auraRewarder.address,
      await booster.REWARD_MULTIPLIER_DENOMINATOR()
    );
  });

  describe("#initialize", () => {
    it("check initial values", async () => {
      expect(await wAuraPools.AURA()).to.be.eq(aura.address);
      expect(await wAuraPools.auraPools()).to.be.eq(booster.address);
      expect(await wAuraPools.STASH_AURA()).to.be.eq(stashToken.address);
    });

    it("should revert initializing twice", async () => {
      await expect(
        wAuraPools.initialize(aura.address, booster.address, stashToken.address)
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

      it("calculate reward[0] when its decimals is not 18", async () => {
        await lpToken.setDecimals(8);

        expect(await lpToken.decimals()).to.be.eq(8);

        const rewardPerToken = utils.parseEther("150");
        await auraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(
          rewardPerToken
            .sub(auraPerShare)
            .mul(amount)
            .div(BigNumber.from(10).pow(8))
        );
      });

      it("return 0 if rewardPerToken is lower than stRewardPerShare", async () => {
        const rewardPerToken = utils.parseEther("50");
        await auraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][0]).to.be.eq(0);
      });
    });

    describe("calculate reward[1]", () => {
      const rewardPerToken = utils.parseEther("150");
      let reward0: BigNumber;

      beforeEach(async () => {
        await auraRewarder.setRewardPerToken(rewardPerToken);

        reward0 = rewardPerToken
          .sub(auraPerShare)
          .mul(amount)
          .div(BigNumber.from(10).pow(18));
      });

      it("return 0 if AURA total supply is initial amount", async () => {
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

        reward0 = rewardPerToken
          .sub(auraPerShare)
          .mul(auraMaxSupply)
          .div(BigNumber.from(10).pow(18));

        const res = await wAuraPools.pendingRewards(tokenId, auraMaxSupply);
        expect(res[1][0]).to.be.eq(reward0);
        expect(res[1][1]).to.be.eq(await getAuraMintAmount(reward0));
      });

      it("return 0 if cliff is equal or greater than totalCliffs (when supply is same as max)", async () => {
        const auraMaxSupply = await aura.EMISSIONS_MAX_SUPPLY();
        await aura.mintTestTokens(stakingToken.address, auraMaxSupply);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][1]).to.be.eq(0);
      });
    });

    describe("calculate extraRewards", () => {
      const tokenId = 0;
      const pid = 0;
      const amount = utils.parseEther("100");
      const prevRewardPerToken = utils.parseEther("50");

      beforeEach(async () => {
        await extraRewarder.setRewardPerToken(prevRewardPerToken);
        await wAuraPools.connect(alice).mint(pid, amount);
      });

      it("calculate reward[2] when its decimals is 18", async () => {
        const rewardPerToken = utils.parseEther("150");
        await extraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[0][2]).to.be.eq(extraRewardToken.address);
        expect(res[1][2]).to.be.eq(
          rewardPerToken
            .sub(prevRewardPerToken)
            .mul(amount)
            .div(BigNumber.from(10).pow(18))
        );
      });

      it("calculate reward[2] when its decimals is not 18", async () => {
        await lpToken.setDecimals(8);

        expect(await lpToken.decimals()).to.be.eq(8);

        const rewardPerToken = utils.parseEther("150");
        await extraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[0][2]).to.be.eq(extraRewardToken.address);
        expect(res[1][2]).to.be.eq(
          rewardPerToken
            .sub(prevRewardPerToken)
            .mul(amount)
            .div(BigNumber.from(10).pow(8))
        );
      });

      it("return 0 if rewardPerToken is lower than stRewardPerShare", async () => {
        const rewardPerToken = utils.parseEther("50");
        await extraRewarder.setRewardPerToken(rewardPerToken);

        const res = await wAuraPools.pendingRewards(tokenId, amount);
        expect(res[1][2]).to.be.eq(0);
      });
    });
  });

  describe("#mint", () => {
    const pid = BigNumber.from(0);
    const amount = utils.parseEther("100");
    const auraRewardPerToken = utils.parseEther("50");
    const extraRewardPerToken = utils.parseEther("40");
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(auraRewardPerToken);

    beforeEach(async () => {
      await auraRewarder.setRewardPerToken(auraRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);
    });

    it("deposit into auraPools", async () => {
      await wAuraPools.mint(pid, amount);

      expect(await auraRewarder.balanceOf(wAuraPools.address)).to.be.eq(amount);
      expect(await lpToken.balanceOf(wAuraPools.address)).to.be.eq(0);
      expect(await lpToken.balanceOf(booster.address)).to.be.eq(amount);
      expect(await stakingToken.balanceOf(auraRewarder.address)).to.be.eq(
        amount
      );
    });

    it("mint ERC1155 NFT", async () => {
      await wAuraPools.mint(pid, amount);

      expect(await wAuraPools.balanceOf(alice.address, tokenId)).to.be.eq(
        amount
      );
    });

    it("sync extra reward info", async () => {
      await wAuraPools.mint(pid, amount);

      expect(
        await wAuraPools.accExtPerShare(tokenId, extraRewarder.address)
      ).to.be.eq(extraRewardPerToken);

      expect(await wAuraPools.extraRewardsLength()).to.be.eq(1);
      expect(await wAuraPools.extraRewardsIdx(extraRewarder.address)).to.be.eq(
        1
      );
      expect(await wAuraPools.extraRewards(0)).to.be.eq(extraRewarder.address);
    });

    it("keep existing extra reward info when syncing", async () => {
      await wAuraPools.mint(pid, amount);
      await wAuraPools.mint(pid, amount);

      expect(await wAuraPools.extraRewardsLength()).to.be.eq(1);
      expect(await wAuraPools.extraRewardsIdx(extraRewarder.address)).to.be.eq(
        1
      );
      expect(await wAuraPools.extraRewards(0)).to.be.eq(extraRewarder.address);
    });
  });

  describe("#burn", () => {
    const pid = BigNumber.from(0);
    const mintAmount = utils.parseEther("100");
    const amount = utils.parseEther("60");
    const auraRewardPerToken = utils.parseEther("50");
    const extraRewardPerToken = utils.parseEther("40");
    const newauraRewardPerToken = utils.parseEther("60");
    const newExtraRewardPerToken = utils.parseEther("70");
    const tokenId = pid.mul(BigNumber.from(2).pow(240)).add(auraRewardPerToken);

    beforeEach(async () => {
      await auraRewarder.setRewardPerToken(auraRewardPerToken);
      await extraRewarder.setRewardPerToken(extraRewardPerToken);

      await wAuraPools.mint(pid, mintAmount);

      await rewardToken.mintTo(
        auraRewarder.address,
        utils.parseEther("10000000000")
      );
      await extraRewardToken.mintTo(
        extraRewarder.address,
        utils.parseEther("10000000000")
      );

      await auraRewarder.setRewardPerToken(newauraRewardPerToken);
      await extraRewarder.setRewardPerToken(newExtraRewardPerToken);

      const res = await wAuraPools.pendingRewards(tokenId, amount);
      await aura.mintTestTokensManually(wAuraPools.address, res[1][1]);
      await auraRewarder.setReward(wAuraPools.address, res[1][0]);
      await extraRewarder.setReward(wAuraPools.address, res[1][2]);
    });

    it("withdraw from auraPools", async () => {
      const balBefore = await lpToken.balanceOf(alice.address);

      await wAuraPools.burn(tokenId, amount);

      expect(await auraRewarder.balanceOf(wAuraPools.address)).to.be.eq(
        mintAmount.sub(amount)
      );
      expect(await lpToken.balanceOf(wAuraPools.address)).to.be.eq(0);
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

      await wAuraPools.burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);
      // expect(await aura.balanceOf(alice.address)).to.be.eq(res[1][1]);
      expect(await extraRewardToken.balanceOf(alice.address)).to.be.eq(
        res[1][2]
      );
    });

    it("claim extra reward manually due to extra info mismatch", async () => {
      const res = await wAuraPools.pendingRewards(tokenId, amount);

      await auraRewarder.clearExtraRewards();
      await wAuraPools.burn(tokenId, amount);

      expect(await rewardToken.balanceOf(alice.address)).to.be.eq(res[1][0]);
      // expect(await aura.balanceOf(alice.address)).to.be.eq(res[1][1]);
      expect(await extraRewardToken.balanceOf(alice.address)).to.be.eq(
        res[1][2]
      );
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
