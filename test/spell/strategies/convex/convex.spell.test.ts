import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  BlueBerryBank,
  ERC20,
  ConvexSpell,
  WConvexPools,
  ICvxPools,
  IRewarder,
  ProtocolConfig,
} from "../../../../typechain-types";
import { ethers } from "hardhat";
import { ADDRESS } from "../../../../constant";
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

const ETH = ADDRESS.ETH;
const WETH = ADDRESS.WETH;
const DAI = ADDRESS.DAI;
const POOL_ID = ADDRESS.CVX_EthStEth_Id;

describe("Convex Spell - ETH/stETH", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let dai: ERC20;
  let spell: ConvexSpell;
  let wconvex: WConvexPools;
  let bank: BlueBerryBank;
  let protocol: CvxProtocol;
  let cvxBooster: ICvxPools;
  let crvRewarder: IRewarder;
  let config: ProtocolConfig;
  const depositAmount = utils.parseUnits("1000", 18); // DAI
  const borrowAmount = utils.parseUnits("1", 18); // ETH
  const iface = new ethers.utils.Interface(SpellABI);

  const STRATEGY_ID = 3;

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();
    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    cvxBooster = <ICvxPools>(
      await ethers.getContractAt("ICvxPools", ADDRESS.CVX_BOOSTER)
    );
    const poolInfo = await cvxBooster.poolInfo(POOL_ID);
    crvRewarder = <IRewarder>(
      await ethers.getContractAt("IRewarder", poolInfo.crvRewards)
    );

    protocol = await setupCvxProtocol();
    bank = protocol.bank;
    spell = protocol.convexSpell;
    wconvex = protocol.wconvex;
    config = protocol.config;

    await dai.approve(bank.address, ethers.constants.MaxUint256);
  });

  it("should be able to farm ETH on Convex", async () => {
    const positionId = await bank.nextPositionId();
    const beforeTreasuryBalance = await dai.balanceOf(treasury.address);
    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData("openPositionFarm", [
        {
          strategyId: STRATEGY_ID,
          collToken: DAI,
          borrowToken: WETH,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: POOL_ID,
        },
        0,
      ])
    );

    const bankInfo = await bank.getBankInfo(WETH);

    const pos = await bank.positions(positionId);

    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(wconvex.address);
    expect(pos.debtToken).to.be.equal(WETH);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await dai.balanceOf(treasury.address);
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
      depositAmount.mul(50).div(10000)
    );
  });

  it("should be able to harvest on Convex", async () => {
    await evm_mine_blocks(1000);

    const positionId = (await bank.nextPositionId()).sub(1);
    const position = await bank.positions(positionId);

    const totalEarned = await crvRewarder.earned(wconvex.address);

    const pendingRewardsInfo = await wconvex.callStatic.pendingRewards(
      position.collId,
      position.collateralSize
    );

    const rewardFeeRatio = await config.rewardFee();

    const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
      reward.mul(BigNumber.from(10000).sub(rewardFeeRatio)).div(10000)
    );

    const swapDatas = await Promise.all(
      pendingRewardsInfo.tokens.map((token, i) => {
        if (expectedAmounts[i].gt(0)) {
          return getParaswapCalldata(
            token,
            WETH,
            expectedAmounts[i],
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
            strategyId: STRATEGY_ID,
            collToken: DAI,
            borrowToken: WETH,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: "0x",
          },
          amounts: expectedAmounts,
          swapDatas: swapDatas.map((item) => item.data),
          isKilled: false,
        },
      ])
    );
    const afterETHBalance = await admin.getBalance();
    const afterDaiBalance = await dai.balanceOf(admin.address);

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
});