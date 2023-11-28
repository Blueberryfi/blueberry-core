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
  ICurvePool,
} from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  CvxProtocol,
  setupCvxProtocol,
  evm_mine_blocks,
  fork,
  takeSnapshot,
  revertToSnapshot,
  impersonateAccount,
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
const WETH = ADDRESS.WETH;
const BAL = ADDRESS.BAL;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const CVX = ADDRESS.CVX;
const POOL_ID_FRAXUSDC = ADDRESS.CVX_FraxUsdc_Id;

describe("Convex Spell", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let cvx: ERC20;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: ConvexSpell;
  let wconvex: WConvexPools;
  let bank: BlueBerryBank;
  let protocol: CvxProtocol;
  let cvxBooster: ICvxPools;
  let crvRewarder: IRewarder;
  let config: ProtocolConfig;
  let stableOracle: CurveStableOracle;

  before(async () => {
    await fork(1, 15050720);

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    cvx = <ERC20>await ethers.getContractAt("ERC20", CVX);
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    cvxBooster = <ICvxPools>(
      await ethers.getContractAt("ICvxPools", ADDRESS.CVX_BOOSTER)
    );
    const poolInfo = await cvxBooster.poolInfo(POOL_ID_FRAXUSDC);
    crvRewarder = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo.crvRewards)
    );

    protocol = await setupCvxProtocol(true);
    bank = protocol.bank;
    spell = protocol.convexSpell;
    wconvex = protocol.wconvex;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    config = protocol.config;
    stableOracle = protocol.stableOracle;
  });

  describe("Convex Pool Farming Position", () => {
    const depositAmount = utils.parseUnits("500", 18); // CRV => $100
    const borrowAmount = utils.parseUnits("250", 6); // USDC
    const iface = new ethers.utils.Interface(SpellABI);

    before(async () => {
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await crv.approve(bank.address, ethers.constants.MaxUint256);
    });

    it("should be able to farm USDC on Convex", async () => {
      const positionId = await bank.nextPositionId();
      const beforeTreasuryBalance = await crv.balanceOf(treasury.address);
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData("openPositionFarm", [
          {
            strategyId: 7,
            collToken: CRV,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: POOL_ID_FRAXUSDC,
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

      const rewarderBalance = await crvRewarder.balanceOf(wconvex.address);
      expect(rewarderBalance).to.be.equal(pos.collateralSize);
    });

    it("should be able to withdraw when pool is killed", async () => {
      let snapshotId = await takeSnapshot();

      await evm_mine_blocks(100000);

      const pool = <ICurvePool>(
        await ethers.getContractAt("ICurvePool", ADDRESS.CRV_FRAXUSDC_POOL)
      );
      const ownerAddr = await pool.owner();
      await admin.sendTransaction({
        to: ownerAddr,
        value: ethers.utils.parseEther("1"),
      });
      await impersonateAccount(ownerAddr);
      const owner = await ethers.getSigner(ownerAddr);

      // kill the pool
      await pool.connect(owner).kill_me();

      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const totalEarned = await crvRewarder.earned(wconvex.address);
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

      const poolInfo = await stableOracle.callStatic.getPoolInfo(
        ADDRESS.CRV_FRAXUSDC
      );
      console.log("Pool info", poolInfo);

      const poolTokensSwapData = await Promise.all(
        poolInfo.coins.map((token, idx) => {
          if (token.toLowerCase() !== USDC.toLowerCase()) {
            return getParaswapCalldata(
              token,
              USDC,
              ethers.utils.parseEther("100"),
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
      expectedAmounts.push(
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("100")
      );
      swapDatas.push(...poolTokensSwapData);

      const amountToSwap = utils.parseUnits("200", 18);
      const swapData = (
        await getParaswapCalldata(CRV, USDC, amountToSwap, spell.address, 100)
      ).data;

      const beforeTreasuryBalance = await crv.balanceOf(treasury.address);
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeCrvBalance = await crv.balanceOf(admin.address);

      const iface = new ethers.utils.Interface(SpellABI);
      await bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData("closePositionFarm", [
          {
            param: {
              strategyId: 7,
              collToken: CRV,
              borrowToken: USDC,
              amountRepay: ethers.constants.MaxUint256,
              amountPosRemove: ethers.constants.MaxUint256,
              amountShareWithdraw: ethers.constants.MaxUint256,
              amountOutMin: 1,
              amountToSwap,
              swapData,
            },
            amounts: expectedAmounts,
            swapDatas: swapDatas.map((item) => item.data),
            isKilled: true,
          },
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
        depositAmount.sub(depositFee).sub(withdrawFee).sub(amountToSwap)
      );

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      // Plus rewards fee
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(
        withdrawFee
      );

      await revertToSnapshot(snapshotId);
    });
  });
});
