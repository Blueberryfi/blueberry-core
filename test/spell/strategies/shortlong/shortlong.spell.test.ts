import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  BlueBerryBank,
  MockOracle,
  WERC20,
  ERC20,
  ShortLongSpell,
  SoftVault,
} from "../../../../typechain-types";
import { ethers } from "hardhat";
import { ADDRESS } from "../../../../constant";
import {
  ShortLongProtocol,
  evm_mine_blocks,
  fork,
  setupShortLongProtocol,
} from "../../../helpers";
import SpellABI from "../../../../abi/ShortLongSpell.json";
import chai, { expect } from "chai";
import { near } from "../../../assertions/near";
import { roughlyNear } from "../../../assertions/roughlyNear";
import { BigNumber, utils } from "ethers";
import { getParaswapCalldata } from "../../../helpers/paraswap";

chai.use(near);
chai.use(roughlyNear);

const WBTC = ADDRESS.WBTC;
const LINK = ADDRESS.LINK;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;

describe("ShortLong Spell", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let crv: ERC20;
  let dai: ERC20;
  let wbtc: ERC20;
  let weth: ERC20;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: ShortLongSpell;
  let bank: BlueBerryBank;
  let protocol: ShortLongProtocol;
  let daiSoftVault: SoftVault;
  let linkSoftVault: SoftVault;

  const iface = new ethers.utils.Interface(SpellABI);

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    wbtc = <ERC20>await ethers.getContractAt("ERC20", WBTC);
    weth = <ERC20>await ethers.getContractAt("ERC20", WETH);

    protocol = await setupShortLongProtocol();
    bank = protocol.bank;
    spell = protocol.shortLongSpell;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    daiSoftVault = protocol.daiSoftVault;
    linkSoftVault = protocol.linkSoftVault;

    await usdc.approve(bank.address, ethers.constants.MaxUint256);
    await crv.approve(bank.address, ethers.constants.MaxUint256);
    await wbtc.approve(bank.address, ethers.constants.MaxUint256);
    await weth.approve(bank.address, ethers.constants.MaxUint256);
    await dai.approve(bank.address, ethers.constants.MaxUint256);
  });

  it("should be able to farm DAI (collateral: WBTC, borrowToken: DAI)", async () => {
    await testFarm(
      1,
      WBTC,
      DAI,
      LINK,
      utils.parseUnits("0.1", 8),
      utils.parseUnits("100", 18),
      0,
      wbtc
    );
  });

  it("should be able to close position", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      1,
      WBTC,
      DAI,
      LINK,
      linkSoftVault,
      utils.parseUnits("0.1", 8),
      dai,
      utils.parseUnits("10", 18),
      wbtc
    );
  });

  it("should be able to farm DAI (collateral: WETH, borrowToken: DAI)", async () => {
    await testFarm(
      1,
      WETH,
      DAI,
      LINK,
      utils.parseUnits("1", 18),
      utils.parseUnits("100", 18),
      0,
      weth
    );
  });

  it("should be able to close position", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      1,
      WETH,
      DAI,
      LINK,
      linkSoftVault,
      utils.parseUnits("1", 18),
      dai,
      utils.parseUnits("10", 18),
      weth
    );
  });

  it("should be able to farm DAI (collateral: DAI, borrowToken: DAI)", async () => {
    await testFarm(
      1,
      DAI,
      DAI,
      LINK,
      utils.parseUnits("1000", 18),
      utils.parseUnits("100", 18),
      0,
      dai
    );
  });

  it("should be able to close position", async () => {
    const positionId = (await bank.nextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      1,
      DAI,
      DAI,
      LINK,
      linkSoftVault,
      utils.parseUnits("1", 18),
      dai,
      utils.parseUnits("10", 18),
      dai
    );
  });

  async function testFarm(
    strategyId: number,
    collToken: string,
    borrowToken: string,
    swapToken: string,
    depositAmount: BigNumber,
    borrowAmount: BigNumber,
    farmingPoolId: number,
    colTokenContract: any
  ) {
    const positionId = await bank.nextPositionId();
    const beforeTreasuryBalance = await colTokenContract.balanceOf(
      treasury.address
    );
    const swapData = await getParaswapCalldata(
      borrowToken,
      swapToken,
      borrowAmount,
      spell.address,
      100
    );

    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData("openPosition", [
        {
          strategyId,
          collToken,
          borrowToken: borrowToken,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId,
        },
        swapData.data,
      ])
    );

    const bankInfo = await bank.getBankInfo(DAI);
    console.log("USDC Bank Info:", bankInfo);

    const pos = await bank.positions(positionId);
    console.log("Position Info:", pos);
    console.log(
      "Position Value:",
      await bank.callStatic.getPositionValue(positionId)
    );
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(werc20.address);
    expect(pos.debtToken).to.be.equal(borrowToken);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await colTokenContract.balanceOf(
      treasury.address
    );
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
      depositAmount.mul(50).div(10000)
    );
  }

  async function testClosePosition(
    positionId: BigNumber,
    strategyId: number,
    collToken: string,
    borrowToken: string,
    swapToken: string,
    softVault: SoftVault,
    depositAmount: BigNumber,
    rewardToken: any,
    rewardAmount: BigNumber,
    collTokenContract: any
  ) {
    await evm_mine_blocks(10000);
    const position = await bank.positions(positionId);

    const swapAmount = await softVault.callStatic.withdraw(
      position.collateralSize
    );

    // Manually transfer reward to spell
    await rewardToken.transfer(spell.address, rewardAmount);

    const beforeTreasuryBalance = await collTokenContract.balanceOf(
      treasury.address
    );
    const beforeColTokenBalance = await collTokenContract.balanceOf(
      admin.address
    );
    const beforeBorrowTokenBalance = await rewardToken.balanceOf(admin.address);

    const swapData = await getParaswapCalldata(
      swapToken,
      borrowToken,
      swapAmount,
      spell.address,
      100
    );

    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData("closePosition", [
        {
          strategyId,
          collToken,
          borrowToken: borrowToken,
          amountRepay: ethers.constants.MaxUint256,
          amountPosRemove: ethers.constants.MaxUint256,
          amountShareWithdraw: ethers.constants.MaxUint256,
          amountOutMin: 1,
        },
        swapData.data,
      ])
    );
    const afterColTokenBalance = await collTokenContract.balanceOf(
      admin.address
    );
    const afterBorrowTokenBalance = await rewardToken.balanceOf(admin.address);
    console.log(
      "Collateral Token Balance Change:",
      afterColTokenBalance.sub(beforeColTokenBalance)
    );
    console.log(
      "Borrow Token Balance Change:",
      afterBorrowTokenBalance.sub(beforeBorrowTokenBalance)
    );
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterBorrowTokenBalance.sub(beforeBorrowTokenBalance)).to.be.gte(
      depositAmount.sub(depositFee).sub(withdrawFee)
    );

    const afterTreasuryBalance = await collTokenContract.balanceOf(
      treasury.address
    );
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(
      withdrawFee.div(2)
    );
  }
});
