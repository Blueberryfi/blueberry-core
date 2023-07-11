import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  BlueBerryBank,
  IWETH,
  MockOracle,
  WERC20,
  WCurveGauge,
  ERC20,
  CurveSpell,
  CurveStableOracle,
  CurveVolatileOracle,
  CurveTricryptoOracle,
  ConvexSpell,
  WConvexPools,
  ICvxPools,
  IRewarder,
  ProtocolConfig,
} from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  CvxProtocol,
  setupCvxProtocol,
  evm_mine_blocks,
  fork,
} from "../helpers";
import SpellABI from "../../abi/ConvexSpell.json";
import chai, { expect } from "chai";
import { near } from "../assertions/near";
import { roughlyNear } from "../assertions/roughlyNear";
import { BigNumber, utils } from "ethers";
import { getParaswapCalldata } from "../helpers/paraswap";

chai.use(near);
chai.use(roughlyNear);

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const CUSDC = ADDRESS.bUSDC;
const CDAI = ADDRESS.bDAI;
const CCRV = ADDRESS.bCRV;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const CVX = ADDRESS.CVX;
const POOL_ID_1 = ADDRESS.CVX_3Crv_Id;
const POOL_ID_2 = ADDRESS.CVX_CrvEth_Id;
const POOL_ID_3 = ADDRESS.CVX_Susd_Id;

describe("Convex Spell", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let cvx: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: ConvexSpell;
  let volatileSpell: ConvexSpell;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let wconvex: WConvexPools;
  let bank: BlueBerryBank;
  let protocol: CvxProtocol;
  let cvxBooster: ICvxPools;
  let crvRewarder1: IRewarder;
  let crvRewarder2: IRewarder;
  let config: ProtocolConfig;

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    cvx = <ERC20>await ethers.getContractAt("ERC20", CVX);
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
    cvxBooster = <ICvxPools>(
      await ethers.getContractAt("ICvxPools", ADDRESS.CVX_BOOSTER)
    );
    const poolInfo1 = await cvxBooster.poolInfo(POOL_ID_1);
    crvRewarder1 = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo1.crvRewards)
    );
    const poolInfo2 = await cvxBooster.poolInfo(POOL_ID_2);
    crvRewarder2 = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo2.crvRewards)
    );

    protocol = await setupCvxProtocol();
    bank = protocol.bank;
    spell = protocol.convexSpell;
    volatileSpell = protocol.convexSpellWithVolatileOracle;
    wconvex = protocol.wconvex;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    stableOracle = protocol.stableOracle;
    volatileOracle = protocol.volatileOracle;
    tricryptoOracle = protocol.tricryptoOracle;
    config = protocol.config;
  });

  describe("Constructor", () => {
    it("should revert when zero address is provided in param", async () => {
      const ConvexSpell = await ethers.getContractFactory(
        CONTRACT_NAMES.ConvexSpell
      );
      await expect(
        upgrades.deployProxy(ConvexSpell, [
          ethers.constants.AddressZero,
          werc20.address,
          WETH,
          wconvex.address,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(ConvexSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(ConvexSpell, [
          bank.address,
          ethers.constants.AddressZero,
          WETH,
          wconvex.address,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(ConvexSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(ConvexSpell, [
          bank.address,
          werc20.address,
          ethers.constants.AddressZero,
          wconvex.address,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(ConvexSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(ConvexSpell, [
          bank.address,
          werc20.address,
          WETH,
          ethers.constants.AddressZero,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(ConvexSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(ConvexSpell, [
          bank.address,
          werc20.address,
          WETH,
          wconvex.address,
          ethers.constants.AddressZero,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(ConvexSpell, "ZERO_ADDRESS");
    });
    it("should revert initializing twice", async () => {
      await expect(
        spell.initialize(
          bank.address,
          werc20.address,
          WETH,
          ethers.constants.AddressZero,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY
        )
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  describe("Owner", () => {
    it("should fail to add strategy as non-owner", async () => {
      await expect(
        spell
          .connect(alice)
          .addStrategy(
            ADDRESS.CRV_3Crv,
            utils.parseUnits("100", 18),
            utils.parseUnits("2000", 18)
          )
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Convex Pool Farming Position", () => {
    const depositAmount = utils.parseUnits("100", 18); // CRV => $100
    const borrowAmount = utils.parseUnits("250", 6); // USDC
    const iface = new ethers.utils.Interface(SpellABI);

    before(async () => {
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await crv.approve(bank.address, ethers.constants.MaxUint256);
    });

    it("should revert when opening position exceeds max LTV", async () => {
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData("openPositionFarm", [
            {
              strategyId: 0,
              collToken: CRV,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount.mul(4),
              farmingPoolId: POOL_ID_1,
            },
            0,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "EXCEED_MAX_LTV");
    });
    it("should revert when opening a position for non-existing strategy", async () => {
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData("openPositionFarm", [
            {
              strategyId: 5,
              collToken: CRV,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: POOL_ID_1,
            },
            0,
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, "STRATEGY_NOT_EXIST")
        .withArgs(spell.address, 5);
    });
    it("should revert when opening a position for non-existing collateral", async () => {
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData("openPositionFarm", [
            {
              strategyId: 0,
              collToken: WETH,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: POOL_ID_1,
            },
            0,
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, "COLLATERAL_NOT_EXIST")
        .withArgs(0, WETH);
    });
    it("should revert when opening a position for incorrect farming pool id", async () => {
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData("openPositionFarm", [
            {
              strategyId: 0,
              collToken: CRV,
              borrowToken: USDC,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: POOL_ID_1 + 1,
            },
            0,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "INCORRECT_LP");
    });

    it("should be able to farm USDC on Convex", async () => {
      const positionId = await bank.nextPositionId();
      const beforeTreasuryBalance = await crv.balanceOf(treasury.address);
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData("openPositionFarm", [
          {
            strategyId: 0,
            collToken: CRV,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: POOL_ID_1,
          },
          0,
        ])
      );

      const bankInfo = await bank.getBankInfo(USDC);
      console.log("USDC Bank Info:", bankInfo);

      const pos = await bank.positions(positionId);
      console.log("Position Info:", pos);
      console.log(
        "Position Value:",
        await bank.callStatic.getPositionValue(positionId)
      );
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(wconvex.address);
      expect(pos.debtToken).to.be.equal(USDC);
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      // expect(
      //   await wgauge.balanceOf(bank.address, collId)
      // ).to.be.equal(pos.collateralSize);

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
        depositAmount.mul(50).div(10000)
      );

      const rewarderBalance = await crvRewarder1.balanceOf(wconvex.address);
      expect(rewarderBalance).to.be.equal(pos.collateralSize);
    });

    it("should be able to get multiple rewards", async () => {
      let positionId = await bank.nextPositionId();
      positionId = positionId.sub(1);
      const position = await bank.positions(positionId);

      const beforeSenderCrvBalance = await crv.balanceOf(admin.address);
      const beforeTreasuryCvxBalance = await cvx.balanceOf(admin.address);

      await evm_mine_blocks(10);

      const pendingRewardsInfo = await wconvex.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );
      const crvPendingReward = pendingRewardsInfo.rewards[0];
      const cvxPendingReward = pendingRewardsInfo.rewards[1];

      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData("openPositionFarm", [
          {
            strategyId: 0,
            collToken: CRV,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: POOL_ID_1,
          },
          0,
        ])
      );

      const afterSenderCrvBalance = await crv.balanceOf(admin.address);
      const afterSenderCvxBalance = await cvx.balanceOf(admin.address);
      // before - out + in = after => after + out = before + in
      expect(afterSenderCrvBalance.add(depositAmount)).to.be.roughlyNear(
        beforeSenderCrvBalance.add(crvPendingReward)
      );
      expect(
        afterSenderCvxBalance.sub(beforeTreasuryCvxBalance)
      ).to.be.roughlyNear(cvxPendingReward);
    });

    it("should be able to get position risk ratio", async () => {
      const positionId = (await bank.nextPositionId()).sub(1);
      let pv = await bank.callStatic.getPositionValue(positionId);
      let ov = await bank.callStatic.getDebtValue(positionId);
      let cv = await bank.callStatic.getIsolatedCollateralValue(positionId);
      let risk = await bank.callStatic.getPositionRisk(positionId);
      console.log("PV:", utils.formatUnits(pv));
      console.log("OV:", utils.formatUnits(ov));
      console.log("CV:", utils.formatUnits(cv));
      console.log("Prev Position Risk", utils.formatUnits(risk, 2), "%");
      await mockOracle.setPrice(
        [USDC, CRV],
        [
          BigNumber.from(10).pow(17).mul(15), // $1
          BigNumber.from(10).pow(17).mul(5), // $0.4
        ]
      );
      risk = await bank.callStatic.getPositionRisk(positionId);
      pv = await bank.callStatic.getPositionValue(positionId);
      ov = await bank.callStatic.getDebtValue(positionId);
      cv = await bank.callStatic.getIsolatedCollateralValue(positionId);
      console.log("=======");
      console.log("PV:", utils.formatUnits(pv));
      console.log("OV:", utils.formatUnits(ov));
      console.log("CV:", utils.formatUnits(cv));
      console.log("Position Risk", utils.formatUnits(risk, 2), "%");
    });
    // TODO: Find another USDC curve pool
    // it("should revert increasing existing position when diff pos param given", async () => {
    //   const positionId = (await bank.nextPositionId()).sub(1);
    //   await expect(
    //     bank.execute(
    //       positionId,
    //       spell.address,
    //       iface.encodeFunctionData("openPositionFarm", [{
    //         strategyId: 1,
    //         collToken: CRV,
    //         borrowToken: USDC,
    //         collAmount: depositAmount,
    //         borrowAmount: borrowAmount,
    //         farmingPoolId: 0
    //       }, 0])
    //     )
    //   ).to.be.revertedWithCustomError(spell, "INCORRECT_LP");
    // })

    it("should revert if received amount is lower than slippage", async () => {
      await evm_mine_blocks(1000);
      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const totalEarned = await crvRewarder1.earned(wconvex.address);
      console.log("Wrapper Total Earned:", utils.formatUnits(totalEarned));

      const pendingRewardsInfo = await wconvex.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );
      console.log("Pending Rewards", pendingRewardsInfo);

      const rewardFeeRatio = await config.rewardFee();

      const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
        reward.mul(BigNumber.from(10000).sub(rewardFeeRatio)).div(10000)
      );

      const swapDatas = await Promise.all(
        pendingRewardsInfo.tokens.map((token, idx) => {
          if (expectedAmounts[idx].gt(0)) {
            return getParaswapCalldata(
              token,
              USDC,
              expectedAmounts[idx],
              spell.address,
              100
            );
          } else {
            return {
              data: "0x00",
            };
          }
        })
      );

      // Manually transfer CRV rewards to spell
      await crv.transfer(spell.address, utils.parseUnits("10", 18));

      const iface = new ethers.utils.Interface(SpellABI);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData("closePositionFarm", [
            {
              strategyId: 0,
              collToken: CRV,
              borrowToken: USDC,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: utils.parseUnits("1000", 18),
            },
            expectedAmounts,
            swapDatas.map((item) => item.data),
          ])
        )
      ).to.be.revertedWith("Not enough coins removed");
    });

    it("should fail to close position for non-existing strategy", async () => {
      const positionId = (await bank.nextPositionId()).sub(1);

      const iface = new ethers.utils.Interface(SpellABI);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData("closePositionFarm", [
            {
              strategyId: 5,
              collToken: CRV,
              borrowToken: USDC,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: utils.parseUnits("1000", 18),
            },
            [],
            [],
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, "STRATEGY_NOT_EXIST")
        .withArgs(spell.address, 5);
    });

    it("should fail to close position for non-existing collateral", async () => {
      const positionId = (await bank.nextPositionId()).sub(1);

      const iface = new ethers.utils.Interface(SpellABI);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData("closePositionFarm", [
            {
              strategyId: 0,
              collToken: WETH,
              borrowToken: USDC,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: utils.parseUnits("1000", 18),
            },
            [],
            [],
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, "COLLATERAL_NOT_EXIST")
        .withArgs(0, WETH);
    });

    it("should be able to harvest on Convex 1", async () => {
      await evm_mine_blocks(1000);
      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const debtAmount = await bank.callStatic.currentPositionDebt(positionId);

      const totalEarned = await crvRewarder1.earned(wconvex.address);
      console.log("Wrapper Total Earned:", utils.formatUnits(totalEarned));

      const pendingRewardsInfo = await wconvex.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );
      console.log("Pending Rewards", pendingRewardsInfo);

      const rewardFeeRatio = await config.rewardFee();

      // Manually transfer CRV rewards to spell
      const rewardAmount = utils.parseUnits("10", 18);
      await crv.transfer(spell.address, rewardAmount);

      const expectedAmounts = pendingRewardsInfo.rewards.map((reward, idx) => {
        if (pendingRewardsInfo.tokens[idx] == ADDRESS.CRV && reward.isZero()) {
          reward = rewardAmount;
        }
        return reward
          .mul(BigNumber.from(10000).sub(rewardFeeRatio))
          .div(10000)
          .div(2);
      });

      const swapDatas = await Promise.all(
        pendingRewardsInfo.tokens.map((token, idx) => {
          if (expectedAmounts[idx].gt(0)) {
            return getParaswapCalldata(
              token,
              USDC,
              expectedAmounts[idx],
              spell.address,
              100
            );
          } else {
            return {
              data: "0x00",
            };
          }
        })
      );

      // Manually transfer USDC rewards to spell
      await usdc.transfer(spell.address, utils.parseUnits("10", 6));

      const iface = new ethers.utils.Interface(SpellABI);
      await expect(
        bank.execute(
          positionId,
          spell.address,
          iface.encodeFunctionData("closePositionFarm", [
            {
              strategyId: 0,
              collToken: CRV,
              borrowToken: USDC,
              amountRepay: debtAmount.div(2),
              amountPosRemove: position.collateralSize.div(2),
              amountShareWithdraw: position.underlyingVaultShare.div(2),
              amountOutMin: 1,
            },
            expectedAmounts,
            swapDatas.map((item) => item.data),
          ])
        )
      ).to.be.revertedWithCustomError(spell, "EXCEED_MAX_LTV");
    });

    it("should be able to harvest on Convex 2", async () => {
      await evm_mine_blocks(1000);

      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const totalEarned = await crvRewarder1.earned(wconvex.address);
      console.log("Wrapper Total Earned:", utils.formatUnits(totalEarned));

      const pendingRewardsInfo = await wconvex.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );
      console.log("Pending Rewards", pendingRewardsInfo);

      const rewardFeeRatio = await config.rewardFee();

      const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
        reward.mul(BigNumber.from(10000).sub(rewardFeeRatio)).div(10000)
      );

      const swapDatas = await Promise.all(
        pendingRewardsInfo.tokens.map((token, idx) => {
          if (expectedAmounts[idx].gt(0)) {
            return getParaswapCalldata(
              token,
              USDC,
              expectedAmounts[idx],
              spell.address,
              100
            );
          } else {
            return {
              data: "0x00",
            };
          }
        })
      );

      // Manually transfer USDC rewards to spell
      await usdc.transfer(spell.address, utils.parseUnits("10", 6));

      const beforeTreasuryBalance = await crv.balanceOf(treasury.address);
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeCrvBalance = await crv.balanceOf(admin.address);

      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData("closePositionFarm", [
          {
            strategyId: 0,
            collToken: CRV,
            borrowToken: USDC,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
          },
          expectedAmounts,
          swapDatas.map((item) => item.data),
        ])
      );
      const afterUSDCBalance = await usdc.balanceOf(admin.address);
      const afterCrvBalance = await crv.balanceOf(admin.address);
      console.log(
        "USDC Balance Change:",
        afterUSDCBalance.sub(beforeUSDCBalance)
      );
      console.log("CRV Balance Change:", afterCrvBalance.sub(beforeCrvBalance));
      const depositFee = depositAmount.mul(50).div(10000);
      const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
      expect(afterCrvBalance.sub(beforeCrvBalance)).to.be.gte(
        depositAmount.sub(depositFee).sub(withdrawFee)
      );

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      // Plus rewards fee
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(
        withdrawFee
      );
    });

    it("should be able to farm CRV on Convex", async () => {
      const positionId = await bank.nextPositionId();
      const beforeTreasuryBalance = await crv.balanceOf(treasury.address);
      await bank.execute(
        0,
        volatileSpell.address,
        iface.encodeFunctionData("openPositionFarm", [
          {
            strategyId: 0,
            collToken: CRV,
            borrowToken: CRV,
            collAmount: depositAmount,
            borrowAmount: utils.parseUnits("1", 18),
            farmingPoolId: POOL_ID_2,
          },
          0,
        ])
      );

      const bankInfo = await bank.getBankInfo(CRV);
      console.log("CRV Bank Info:", bankInfo);

      const pos = await bank.positions(positionId);
      console.log("Position Info:", pos);
      console.log(
        "Position Value:",
        await bank.callStatic.getPositionValue(positionId)
      );
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(wconvex.address);
      expect(pos.debtToken).to.be.equal(CRV);
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
        depositAmount.mul(50).div(10000)
      );

      const rewarderBalance = await crvRewarder2.balanceOf(wconvex.address);
      expect(rewarderBalance).to.be.equal(pos.collateralSize);
    });

    it("should be fail to farm DAI on Convex", async () => {
      await expect(
        bank.execute(
          0,
          spell.address,
          iface.encodeFunctionData("openPositionFarm", [
            {
              strategyId: 2,
              collToken: CRV,
              borrowToken: DAI,
              collAmount: depositAmount,
              borrowAmount: borrowAmount,
              farmingPoolId: POOL_ID_3,
            },
            0,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "EXCEED_MIN_POS_SIZE");
    });
  });
});
