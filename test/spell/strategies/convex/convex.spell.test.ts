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
const WBTC = ADDRESS.WBTC;
const WstETH = ADDRESS.wstETH;
const LINK = ADDRESS.LINK;
const POOL_ID_STETH = ADDRESS.CVX_EthStEth_Id;
const POOL_ID_FRXETH = ADDRESS.CVX_FraxEth_Id;
const POOL_ID_MIM = ADDRESS.CVX_MIM_Id;
const POOL_ID_CVXCRV = ADDRESS.CVX_CvxCrv_Id;

describe("Convex Spells", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let dai: ERC20;
  let wbtc: ERC20;
  let wstETH: ERC20;
  let link: ERC20;
  let weth: IWETH;
  let spell: ConvexSpell;
  let wconvex: WConvexPools;
  let bank: BlueBerryBank;
  let protocol: CvxProtocol;
  let cvxBooster: ICvxPools;
  let crvRewarder1: IRewarder;
  let crvRewarder2: IRewarder;
  let config: ProtocolConfig;
  const depositAmount = utils.parseUnits("1000", 18); // DAI
  const borrowAmount = utils.parseUnits("1", 18); // ETH
  const iface = new ethers.utils.Interface(SpellABI);

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();

    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    wbtc = <ERC20>await ethers.getContractAt("ERC20", WBTC);
    wstETH = <ERC20>await ethers.getContractAt("ERC20", WstETH);
    link = <ERC20>await ethers.getContractAt("ERC20", LINK);
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

    protocol = await setupCvxProtocol();
    bank = protocol.bank;
    spell = protocol.convexSpell;
    wconvex = protocol.wconvex;
    config = protocol.config;

    await dai.approve(bank.address, ethers.constants.MaxUint256);
    await weth.approve(bank.address, ethers.constants.MaxUint256);
    await wbtc.approve(bank.address, ethers.constants.MaxUint256);
    await wstETH.approve(bank.address, ethers.constants.MaxUint256);
    await link.approve(bank.address, ethers.constants.MaxUint256);
  });

  it("should be able to farm ETH on Convex ETH/stETH pool", async () => {
    const positionId = await bank.nextPositionId();
    const beforeTreasuryBalance = await dai.balanceOf(treasury.address);
    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData("openPositionFarm", [
        {
          strategyId: 4,
          collToken: DAI,
          borrowToken: WETH,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: POOL_ID_STETH,
        },
        0,
      ])
    );

    const bankInfo = await bank.getBankInfo(WETH);
    console.log("WETH Bank Info:", bankInfo);

    const pos = await bank.positions(positionId);
    console.log("Position Info:", pos);
    console.log(
      "Position Value:",
      await bank.callStatic.getPositionValue(positionId)
    );
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(wconvex.address);
    expect(pos.debtToken).to.be.equal(WETH);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await dai.balanceOf(treasury.address);
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
      depositAmount.mul(50).div(10000)
    );

    const rewarderBalance = await crvRewarder1.balanceOf(wconvex.address);
    expect(rewarderBalance).to.be.equal(pos.collateralSize);
  });

  it("should be able to harvest on Convex", async () => {
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
            WETH,
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

    // Manually transfer ETH rewards to spell
    await admin.sendTransaction({
      from: admin.address,
      to: spell.address,
      value: utils.parseUnits("0.1", 18),
    });

    const beforeTreasuryBalance = await dai.balanceOf(treasury.address);
    const beforeETHBalance = await admin.getBalance();
    const beforeDaiBalance = await dai.balanceOf(admin.address);

    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData("closePositionFarm", [
        {
          param: {
            strategyId: 4,
            collToken: DAI,
            borrowToken: WETH,
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
    const afterDaiBalance = await dai.balanceOf(admin.address);
    console.log("ETH Balance Change:", afterETHBalance.sub(beforeETHBalance));
    console.log("DAI Balance Change:", afterDaiBalance.sub(beforeDaiBalance));
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterDaiBalance.sub(beforeDaiBalance)).to.be.gte(
      depositAmount.sub(depositFee).sub(withdrawFee)
    );

    const afterTreasuryBalance = await dai.balanceOf(treasury.address);
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(
      withdrawFee
    );
  });

  it("should be able to farm ETH on Convex frxETH/ETH pool", async () => {
    await testFarm(
      3,                                  // Strategy ID
      WBTC,                               // Collateral Token
      WETH,                               // Borrow Token
      utils.parseUnits("0.1", 8),         // Deposit Amount
      utils.parseUnits("0.2", 18),        // Borrow Amount
      POOL_ID_FRXETH,                     // Pool ID
      wbtc,                               // Collateral Token Contract
      crvRewarder2,                       // Pool Rewarder
    );
  });

  async function testFarm(
    strategyId: number,
    collToken: string,
    borrowToken: string,
    depositAmount: BigNumber,
    borrowAmount: BigNumber,
    poolId: number,
    colTokenContract: ERC20,
    crvRewarder: IRewarder,
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
});
