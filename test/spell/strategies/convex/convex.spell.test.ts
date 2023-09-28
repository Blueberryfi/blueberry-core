import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  BlueBerryBank,
  IWETH,
  ERC20,
  ConvexSpell,
  WConvexPools,
  ICvxPools,
  IRewarder,
  ProtocolConfig,
} from "../../../../typechain-types";
import { ethers } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../../../constant";
import {
  CvxProtocol,
  setupCvxProtocol,
  evm_mine_blocks,
  fork,
} from "../../../helpers";
import SpellABI from "../../../../abi/ConvexSpell.json";
import chai, { expect } from "chai";
import { near } from "../../../assertions/near";
import { roughlyNear } from "../../../assertions/roughlyNear";
import { BigNumber, utils } from "ethers";
import { getParaswapCalldata } from "../../../helpers/paraswap";

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const DAI = ADDRESS.DAI;
const USDC = ADDRESS.USDC;
const CRV = ADDRESS.CRV;
const WBTC = ADDRESS.WBTC;
const WstETH = ADDRESS.wstETH;
const LINK = ADDRESS.LINK;
const MIM = ADDRESS.MIM;
const POOL_ID_STETH = ADDRESS.CVX_EthStEth_Id;
const POOL_ID_FRXETH = ADDRESS.CVX_FraxEth_Id;
const POOL_ID_MIM = ADDRESS.CVX_MIM_Id;
const POOL_ID_CVXCRV = ADDRESS.CVX_CvxCrv_Id;

describe("Convex Spells", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let dai: ERC20;
  let usdc: ERC20;
  let crv: ERC20;
  let wbtc: ERC20;
  let wstETH: ERC20;
  let link: ERC20;
  let mim: ERC20;
  let weth: IWETH;
  let spell: ConvexSpell;
  let wconvex: WConvexPools;
  let bank: BlueBerryBank;
  let protocol: CvxProtocol;
  let cvxBooster: ICvxPools;
  let crvRewarder1: IRewarder;
  let crvRewarder2: IRewarder;
  let crvRewarder3: IRewarder;
  let crvRewarder4: IRewarder;
  let config: ProtocolConfig;
  const iface = new ethers.utils.Interface(SpellABI);

  before(async () => {
    await fork(17089048);

    [admin, alice, treasury] = await ethers.getSigners();

    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    wbtc = <ERC20>await ethers.getContractAt("ERC20", WBTC);
    wstETH = <ERC20>await ethers.getContractAt("ERC20", WstETH);
    link = <ERC20>await ethers.getContractAt("ERC20", LINK);
    mim = <ERC20>await ethers.getContractAt("ERC20", MIM);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

    cvxBooster = <ICvxPools>(
      await ethers.getContractAt("ICvxPools", ADDRESS.CVX_BOOSTER)
    );
    const poolInfo1 = await cvxBooster.poolInfo(POOL_ID_STETH);
    crvRewarder1 = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo1.crvRewards)
    );
    const poolInfo2 = await cvxBooster.poolInfo(POOL_ID_FRXETH);
    crvRewarder2 = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo2.crvRewards)
    );
    const poolInfo3 = await cvxBooster.poolInfo(POOL_ID_MIM);
    crvRewarder3 = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo3.crvRewards)
    );
    const poolInfo4 = await cvxBooster.poolInfo(POOL_ID_CVXCRV);
    crvRewarder4 = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo4.crvRewards)
    );

    protocol = await setupCvxProtocol();
    bank = protocol.bank;
    spell = protocol.convexSpell;
    wconvex = protocol.wconvex;
    config = protocol.config;

    await dai.approve(bank.address, ethers.constants.MaxUint256);
    await mim.approve(bank.address, ethers.constants.MaxUint256);
    await weth.approve(bank.address, ethers.constants.MaxUint256);
    await wbtc.approve(bank.address, ethers.constants.MaxUint256);
    await wstETH.approve(bank.address, ethers.constants.MaxUint256);
    await link.approve(bank.address, ethers.constants.MaxUint256);
  });

  it("should be able to farm ETH on Convex stETH/ETH pool collateral WBTC", async () => {
    await testFarm(
      4,
      WBTC,
      WETH,
      utils.parseUnits("0.1", 8),
      utils.parseUnits("1", 18),
      POOL_ID_STETH,
      wbtc,
      crvRewarder1
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      WBTC,
      WETH,
      utils.parseUnits("0.1", 8),
      crvRewarder1,
      weth,
      utils.parseUnits("0.1", 18),
      wbtc
    );
  });

  it("should be able to farm ETH on Convex stETH/ETH pool collateral wstETH", async () => {
    await testFarm(
      4,
      WstETH,
      WETH,
      utils.parseUnits("1", 18),
      utils.parseUnits("0.5", 18),
      POOL_ID_STETH,
      wstETH,
      crvRewarder1
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      WstETH,
      WETH,
      utils.parseUnits("1", 18),
      crvRewarder1,
      weth,
      utils.parseUnits("0.1", 18),
      wstETH
    );
  });

  it("should be able to farm ETH on Convex stETH/ETH pool collateral WETH", async () => {
    await testFarm(
      4,
      WETH,
      WETH,
      utils.parseUnits("1", 18),
      utils.parseUnits("0.5", 18),
      POOL_ID_STETH,
      weth,
      crvRewarder1
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      WETH,
      WETH,
      utils.parseUnits("1", 18),
      crvRewarder1,
      weth,
      utils.parseUnits("0.1", 18),
      weth
    );
  });

  it("should be able to farm ETH on Convex stETH/ETH pool collateral DAI", async () => {
    await testFarm(
      4,
      DAI,
      WETH,
      utils.parseUnits("1000", 18),
      utils.parseUnits("1", 18),
      POOL_ID_STETH,
      dai,
      crvRewarder1
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      DAI,
      WETH,
      utils.parseUnits("1000", 18),
      crvRewarder1,
      weth,
      utils.parseUnits("0.1", 18),
      dai
    );
  });

  it("should be able to farm ETH on Convex stETH/ETH pool collateral LINK", async () => {
    await testFarm(
      4,
      LINK,
      WETH,
      utils.parseUnits("500", 18),
      utils.parseUnits("0.5", 18),
      POOL_ID_STETH,
      link,
      crvRewarder1
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      LINK,
      WETH,
      utils.parseUnits("500", 18),
      crvRewarder1,
      weth,
      utils.parseUnits("0.1", 18),
      link
    );
  });

  it("should be able to farm ETH on Convex frxETH/ETH pool collateral WBTC", async () => {
    await testFarm(
      3,
      WBTC,
      WETH,
      utils.parseUnits("0.1", 8),
      utils.parseUnits("0.2", 18),
      POOL_ID_FRXETH,
      wbtc,
      crvRewarder2
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      WBTC,
      WETH,
      utils.parseUnits("0.1", 8),
      crvRewarder2,
      weth,
      utils.parseUnits("0.1", 18),
      wbtc
    );
  });

  it("should be able to farm ETH on Convex frxETH/ETH pool collateral WstETH", async () => {
    await testFarm(
      3,
      WstETH,
      WETH,
      utils.parseUnits("0.5", 18),
      utils.parseUnits("0.2", 18),
      POOL_ID_FRXETH,
      wstETH,
      crvRewarder2
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      WstETH,
      WETH,
      utils.parseUnits("0.5", 18),
      crvRewarder2,
      weth,
      utils.parseUnits("0.1", 18),
      wstETH
    );
  });

  it("should be able to farm ETH on Convex frxETH/ETH pool collateral WETH", async () => {
    await testFarm(
      3,
      WETH,
      WETH,
      utils.parseUnits("0.5", 18),
      utils.parseUnits("0.2", 18),
      POOL_ID_FRXETH,
      weth,
      crvRewarder2
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      WETH,
      WETH,
      utils.parseUnits("0.5", 18),
      crvRewarder2,
      weth,
      utils.parseUnits("0.1", 18),
      weth
    );
  });

  it("should be able to farm ETH on Convex frxETH/ETH pool collateral DAI", async () => {
    await testFarm(
      3,
      DAI,
      WETH,
      utils.parseUnits("1000", 18),
      utils.parseUnits("1", 18),
      POOL_ID_FRXETH,
      dai,
      crvRewarder2
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      DAI,
      WETH,
      utils.parseUnits("1000", 18),
      crvRewarder2,
      weth,
      utils.parseUnits("0.1", 18),
      dai
    );
  });

  it("should be able to farm ETH on Convex frxETH/ETH pool collateral LINK", async () => {
    await testFarm(
      3,
      LINK,
      WETH,
      utils.parseUnits("500", 18),
      utils.parseUnits("1", 18),
      POOL_ID_FRXETH,
      link,
      crvRewarder2
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      LINK,
      WETH,
      utils.parseUnits("500", 18),
      crvRewarder2,
      weth,
      utils.parseUnits("0.1", 18),
      link
    );
  });

  it("should be able to farm DAI on Convex MIM3CRV pool collateral MIM", async () => {
    await testFarm(
      5,
      MIM,
      DAI,
      utils.parseUnits("1000", 18),
      utils.parseUnits("1000", 18),
      POOL_ID_MIM,
      mim,
      crvRewarder3
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      5,
      MIM,
      DAI,
      utils.parseUnits("1000", 18),
      crvRewarder3,
      dai,
      utils.parseUnits("100", 18),
      mim
    );
  });

  it("should be able to farm USDC on Convex MIM3CRV pool collateral MIM", async () => {
    await testFarm(
      5,
      MIM,
      USDC,
      utils.parseUnits("1000", 18),
      utils.parseUnits("1000", 6),
      POOL_ID_MIM,
      mim,
      crvRewarder3
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      5,
      MIM,
      USDC,
      utils.parseUnits("1000", 18),
      crvRewarder3,
      usdc,
      utils.parseUnits("100", 6),
      mim
    );
  });

  it("should be able to farm CRV on Convex cvxCRV/CRV pool collateral WBTC", async () => {
    await testFarm(
      6,
      WBTC,
      CRV,
      utils.parseUnits("0.1", 8),
      utils.parseUnits("100", 18),
      POOL_ID_CVXCRV,
      wbtc,
      crvRewarder4
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      6,
      WBTC,
      CRV,
      utils.parseUnits("0.1", 8),
      crvRewarder4,
      crv,
      utils.parseUnits("10", 18),
      wbtc
    );
  });

  it("should be able to farm CRV on Convex cvxCRV/CRV pool collateral WETH", async () => {
    await testFarm(
      6,
      WETH,
      CRV,
      utils.parseUnits("1", 18),
      utils.parseUnits("100", 18),
      POOL_ID_CVXCRV,
      weth,
      crvRewarder4
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      6,
      WETH,
      CRV,
      utils.parseUnits("1", 18),
      crvRewarder4,
      crv,
      utils.parseUnits("10", 18),
      weth
    );
  });

  it("should be able to farm CRV on Convex cvxCRV/CRV pool collateral DAI", async () => {
    await testFarm(
      6,
      DAI,
      CRV,
      utils.parseUnits("1000", 18),
      utils.parseUnits("100", 18),
      POOL_ID_CVXCRV,
      dai,
      crvRewarder4
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      6,
      DAI,
      CRV,
      utils.parseUnits("1000", 18),
      crvRewarder4,
      crv,
      utils.parseUnits("10", 18),
      dai
    );
  });

  it("should be able to farm CRV on Convex cvxCRV/CRV pool collateral LINK", async () => {
    await testFarm(
      6,
      LINK,
      CRV,
      utils.parseUnits("500", 18),
      utils.parseUnits("100", 18),
      POOL_ID_CVXCRV,
      link,
      crvRewarder4
    );
  });

  it("should be able to harvest on Convex", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testHarvest(
      positionId,
      6,
      LINK,
      CRV,
      utils.parseUnits("500", 18),
      crvRewarder4,
      crv,
      utils.parseUnits("10", 18),
      link
    );
  });

  async function testFarm(
    strategyId: number,
    collToken: string,
    borrowToken: string,
    depositAmount: BigNumber,
    borrowAmount: BigNumber,
    poolId: number,
    colTokenContract: any,
    crvRewarder: IRewarder
  ) {
    const positionId = await bank.nextPositionId();
    const beforeTreasuryBalance = await colTokenContract.balanceOf(
      treasury.address
    );
    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData("openPositionFarm", [
        {
          strategyId,
          collToken,
          borrowToken,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: poolId,
        },
        0,
      ])
    );

    const bankInfo = await bank.getBankInfo(borrowToken);
    console.log("Bank Info:", bankInfo);

    const pos = await bank.positions(positionId);
    console.log("Position Info:", pos);
    console.log(
      "Position Value:",
      await bank.callStatic.getPositionValue(positionId)
    );
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(wconvex.address);
    expect(pos.debtToken).to.be.equal(borrowToken);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await colTokenContract.balanceOf(
      treasury.address
    );
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
      depositAmount.mul(50).div(10000)
    );

    const rewarderBalance = await crvRewarder.balanceOf(wconvex.address);
    expect(rewarderBalance).to.be.equal(pos.collateralSize);
  }

  async function testHarvest(
    positionId: BigNumber,
    strategyId: number,
    collToken: string,
    borrowToken: string,
    depositAmount: BigNumber,
    crvRewarder: IRewarder,
    rewardToken: any,
    rewardAmount: BigNumber,
    collTokenContract: any
  ) {
    await evm_mine_blocks(1000);

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
        if (
          expectedAmounts[idx].gt(0) &&
          token.toLowerCase() !== borrowToken.toLowerCase()
        ) {
          return getParaswapCalldata(
            token,
            borrowToken,
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

    // Manually transfer reward to spell
    await rewardToken.transfer(spell.address, rewardAmount);

    const beforeTreasuryBalance = await collTokenContract.balanceOf(
      treasury.address
    );
    const beforeETHBalance = await admin.getBalance();
    const beforeColBalance = await collTokenContract.balanceOf(admin.address);

    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData("closePositionFarm", [
        {
          param: {
            strategyId,
            collToken,
            borrowToken,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
          amounts: expectedAmounts,
          swapDatas: swapDatas.map((item) => item.data),
          isKilled: false,
        },
      ])
    );
    const afterETHBalance = await admin.getBalance();
    const afterColBalance = await collTokenContract.balanceOf(admin.address);
    console.log("ETH Balance Change:", afterETHBalance.sub(beforeETHBalance));
    console.log(
      "Collateral Balance Change:",
      afterColBalance.sub(beforeColBalance)
    );
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterColBalance.sub(beforeColBalance)).to.be.gte(
      depositAmount.sub(depositFee).sub(withdrawFee)
    );

    const afterTreasuryBalance = await collTokenContract.balanceOf(
      treasury.address
    );
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(
      withdrawFee.sub(1)
    );
  }
});
