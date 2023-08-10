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
  WAuraPools,
  ICvxPools,
  IRewarder,
  AuraSpell,
  ProtocolConfig,
} from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { AuraProtocol, evm_mine_blocks, setupAuraProtocol } from "../helpers";
import SpellABI from "../../abi/AuraSpell.json";
import chai, { expect } from "chai";
import { near } from "../assertions/near";
import { roughlyNear } from "../assertions/roughlyNear";
import { BigNumber, utils } from "ethers";
import { getParaswapCalldata } from "../helpers/paraswap";
import { fork } from "../helpers";

chai.use(near);
chai.use(roughlyNear);

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const CUSDC = ADDRESS.bUSDC;
const CDAI = ADDRESS.bDAI;
const CCRV = ADDRESS.bCRV;
const BAL = ADDRESS.BAL;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const AURA = ADDRESS.AURA;
const POOL_ID = ADDRESS.AURA_UDU_POOL_ID;
const WPOOL_ID = ADDRESS.AURA_WETH_AURA_ID;

describe("Aura Spell", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let aura: ERC20;
  let bal: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: AuraSpell;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let waura: WAuraPools;
  let bank: BlueBerryBank;
  let protocol: AuraProtocol;
  let auraBooster: ICvxPools;
  let auraRewarder: IRewarder;
  let config: ProtocolConfig;

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    aura = <ERC20>await ethers.getContractAt("ERC20", AURA);
    bal = <ERC20>await ethers.getContractAt("ERC20", BAL);
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
    auraBooster = <ICvxPools>(
      await ethers.getContractAt("ICvxPools", ADDRESS.AURA_BOOSTER)
    );
    const poolInfo = await auraBooster.poolInfo(ADDRESS.AURA_UDU_POOL_ID);
    auraRewarder = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo.crvRewards)
    );

    protocol = await setupAuraProtocol();
    bank = protocol.bank;
    spell = protocol.auraSpell;
    waura = protocol.waura;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    stableOracle = protocol.stableOracle;
    volatileOracle = protocol.volatileOracle;
    tricryptoOracle = protocol.tricryptoOracle;
    config = protocol.config;
  });

  describe("Constructor", () => {
    it("should revert when zero address is provided in param", async () => {
      const AuraSpell = await ethers.getContractFactory(
        CONTRACT_NAMES.AuraSpell
      );
      await expect(
        upgrades.deployProxy(AuraSpell, [
          ethers.constants.AddressZero,
          werc20.address,
          WETH,
          waura.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(spell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(AuraSpell, [
          bank.address,
          ethers.constants.AddressZero,
          WETH,
          waura.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(spell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(AuraSpell, [
          bank.address,
          werc20.address,
          ethers.constants.AddressZero,
          waura.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(spell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(AuraSpell, [
          bank.address,
          werc20.address,
          WETH,
          ethers.constants.AddressZero,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(spell, "ZERO_ADDRESS");
    });
    it("should revert initializing twice", async () => {
      await expect(
        spell.initialize(
          bank.address,
          werc20.address,
          WETH,
          ethers.constants.AddressZero,
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

  describe("Aura Pool Farming Position", () => {
    const depositAmount = utils.parseUnits("100", 18); // CRV => $100
    const borrowAmount = utils.parseUnits("250", 6); // USDC
    const iface = new ethers.utils.Interface(SpellABI);

    beforeEach(async () => {
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await crv.approve(bank.address, 0);
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
              farmingPoolId: POOL_ID,
            },
            1,
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
              farmingPoolId: POOL_ID,
            },
            1,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "STRATEGY_NOT_EXIST");
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
              farmingPoolId: POOL_ID,
            },
            1,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "COLLATERAL_NOT_EXIST");
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
              farmingPoolId: 0,
            },
            1,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "INCORRECT_LP");
    });

    it("should be able to farm USDC on Aura", async () => {
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
            farmingPoolId: POOL_ID,
          },
          1,
        ])
      );

      const bankInfo = await bank.getBankInfo(USDC);
      console.log("USDC Bank Info:", bankInfo);

      const pos = await bank.positions(positionId);
      console.log("Position Info:", pos);
      console.log("Position Value:", await bank.callStatic.getPositionValue(1));
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(waura.address);
      expect(pos.debtToken).to.be.equal(USDC);
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      // expect(
      //   await wgauge.balanceOf(bank.address, collId)
      // ).to.be.equal(pos.collateralSize);

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
        depositAmount.mul(50).div(10000)
      );

      const rewarderBalance = await auraRewarder.balanceOf(waura.address);
      expect(rewarderBalance).to.be.equal(pos.collateralSize);
    });

    it("should be able to get multiple rewards", async () => {
      let positionId = await bank.nextPositionId();
      positionId = positionId.sub(1);
      const position = await bank.positions(positionId);

      const beforeSenderBalBalance = await bal.balanceOf(admin.address);
      const beforeTreasuryAuraBalance = await aura.balanceOf(admin.address);

      await evm_mine_blocks(10);

      const pendingRewardsInfo = await waura.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );
      const balPendingReward = pendingRewardsInfo.rewards[0];
      const auraPendingReward = pendingRewardsInfo.rewards[1];

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
            farmingPoolId: POOL_ID,
          },
          1,
        ])
      );

      const afterSenderBalBalance = await bal.balanceOf(admin.address);
      const afterSenderAuraBalance = await aura.balanceOf(admin.address);

      expect(
        afterSenderBalBalance.sub(beforeSenderBalBalance)
      ).to.be.roughlyNear(balPendingReward);
      expect(
        afterSenderAuraBalance.sub(beforeTreasuryAuraBalance)
      ).to.be.roughlyNear(auraPendingReward);
    });

    it("should be able to get position risk ratio", async () => {
      let risk = await bank.callStatic.getPositionRisk(1);
      let pv = await bank.callStatic.getPositionValue(1);
      let ov = await bank.callStatic.getDebtValue(1);
      let cv = await bank.callStatic.getIsolatedCollateralValue(1);
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
      risk = await bank.callStatic.getPositionRisk(1);
      pv = await bank.callStatic.getPositionValue(1);
      ov = await bank.callStatic.getDebtValue(1);
      cv = await bank.callStatic.getIsolatedCollateralValue(1);
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
    //   ).to.be.revertedWithCustomError(spell, "INCORRECT_PID")
    // })

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
              amountOutMin: 1,
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
              amountOutMin: 1,
            },
            [],
            [],
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, "COLLATERAL_NOT_EXIST")
        .withArgs(0, WETH);
    });

    it("should be able to close portion of position without withdrawing isolated collaterals", async () => {
      await evm_mine_blocks(1000);
      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const debtAmount = await bank.callStatic.currentPositionDebt(positionId);

      const totalEarned = await auraRewarder.earned(waura.address);
      console.log("Wrapper Total Earned:", utils.formatUnits(totalEarned));

      const pendingRewardsInfo = await waura.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );

      const rewardFeeRatio = await config.rewardFee();

      const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
        reward.sub(reward.mul(rewardFeeRatio).div(10000))
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

      console.log("Pending Rewards", pendingRewardsInfo);

      // Manually transfer CRV rewards to spell
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

    it("should be able to harvest on Aura", async () => {
      await evm_mine_blocks(1000);
      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const totalEarned = await auraRewarder.earned(waura.address);
      console.log("Wrapper Total Earned:", utils.formatUnits(totalEarned));

      const pendingRewardsInfo = await waura.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );

      const rewardFeeRatio = await config.rewardFee();

      const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
        reward.sub(reward.mul(rewardFeeRatio).div(10000))
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

      console.log("Pending Rewards", pendingRewardsInfo);

      // Manually transfer CRV rewards to spell
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
  });
});
