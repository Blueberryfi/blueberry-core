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
  ProtocolConfig,
} from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  CrvProtocol,
  evm_mine_blocks,
  currentTime,
  setupCrvProtocol,
  fork,
} from "../helpers";
import SpellABI from "../../abi/CurveSpell.json";
import chai, { expect } from "chai";
import { near } from "../assertions/near";
import { roughlyNear } from "../assertions/roughlyNear";
import { BigNumber, utils } from "ethers";
import { getParaswapCalldata } from "../helpers/paraswap";

chai.use(near);
chai.use(roughlyNear);

const CUSDC = ADDRESS.bUSDC;
const CDAI = ADDRESS.bDAI;
const CCRV = ADDRESS.bCRV;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const ETH_PRICE = 1600;
const GAUGE_ID = ADDRESS.CRV_GAUGE_3CrvId;
const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;

describe("Curve Spell", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: CurveSpell;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let wgauge: WCurveGauge;
  let bank: BlueBerryBank;
  let protocol: CrvProtocol;
  let config: ProtocolConfig;

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

    protocol = await setupCrvProtocol();
    bank = protocol.bank;
    spell = protocol.curveSpell;
    wgauge = protocol.wgauge;
    werc20 = protocol.werc20;
    mockOracle = protocol.mockOracle;
    stableOracle = protocol.stableOracle;
    volatileOracle = protocol.volatileOracle;
    tricryptoOracle = protocol.tricryptoOracle;
    config = protocol.config;
  });

  describe("Constructor", () => {
    it("should revert when zero address is provided in param", async () => {
      const CurveSpell = await ethers.getContractFactory(
        CONTRACT_NAMES.CurveSpell
      );
      await expect(
        upgrades.deployProxy(CurveSpell, [
          ethers.constants.AddressZero,
          werc20.address,
          WETH,
          wgauge.address,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(CurveSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(CurveSpell, [
          bank.address,
          ethers.constants.AddressZero,
          WETH,
          wgauge.address,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(CurveSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(CurveSpell, [
          bank.address,
          werc20.address,
          ethers.constants.AddressZero,
          wgauge.address,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(CurveSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(CurveSpell, [
          bank.address,
          werc20.address,
          WETH,
          ethers.constants.AddressZero,
          stableOracle.address,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(CurveSpell, "ZERO_ADDRESS");
      await expect(
        upgrades.deployProxy(CurveSpell, [
          bank.address,
          werc20.address,
          WETH,
          wgauge.address,
          ethers.constants.AddressZero,
          AUGUSTUS_SWAPPER,
          TOKEN_TRANSFER_PROXY,
        ])
      ).to.be.revertedWithCustomError(CurveSpell, "ZERO_ADDRESS");
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

  describe("Curve Gauge Farming Position", () => {
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
              farmingPoolId: GAUGE_ID,
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
              farmingPoolId: GAUGE_ID,
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
              farmingPoolId: GAUGE_ID,
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
              farmingPoolId: GAUGE_ID + 1,
            },
            0,
          ])
        )
      ).to.be.revertedWithCustomError(spell, "INCORRECT_LP");
    });
    it("should be able to farm USDC on Curve pool", async () => {
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
            farmingPoolId: GAUGE_ID,
          },
          0,
        ])
      );

      const bankInfo = await bank.getBankInfo(USDC);
      console.log("USDC Bank Info:", bankInfo);

      const pos = await bank.positions(positionId);
      console.log("Position Info:", pos);
      console.log("Position Value:", await bank.callStatic.getPositionValue(1));
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(wgauge.address);
      expect(pos.debtToken).to.be.equal(USDC);
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;
      // expect(
      //   await wgauge.balanceOf(bank.address, collId)
      // ).to.be.equal(pos.collateralSize);

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
        depositAmount.mul(50).div(10000)
      );
    });
    it("should not revert when another token exists with balance", async () => {
      // transfer 1 wei DAI to check tx success.
      await dai.connect(admin).transfer(spell.address, 1);

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
            farmingPoolId: GAUGE_ID,
          },
          0,
        ])
      );

      const bankInfo = await bank.getBankInfo(USDC);
      console.log("USDC Bank Info:", bankInfo);

      const pos = await bank.positions(positionId);
      console.log("Position Info:", pos);
      console.log("Position Value:", await bank.callStatic.getPositionValue(1));
      expect(pos.owner).to.be.equal(admin.address);
      expect(pos.collToken).to.be.equal(wgauge.address);
      expect(pos.debtToken).to.be.equal(USDC);
      expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

      const afterTreasuryBalance = await crv.balanceOf(treasury.address);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(
        depositAmount.mul(50).div(10000)
      );
    });

    it("should be able to get pendingReward info", async () => {
      evm_mine_blocks(1000);

      const positionId = (await bank.nextPositionId()).sub(1);
      const position = await bank.positions(positionId);

      const pendingRewardsInfo = await wgauge.callStatic.pendingRewards(
        position.collId,
        position.collateralSize
      );

      expect(pendingRewardsInfo[0][0]).to.be.equal(CRV);
      expect(pendingRewardsInfo[1][0]).to.be.gte(0);
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
    //   ).to.be.revertedWithCustomError(spell, "INCORRECT_LP");
    // })
    it("should revert if block timestamp is greater than deadline", async () => {
      // Manually transfer CRV rewards to spell
      await crv.transfer(spell.address, utils.parseUnits("10", 18));

      const deadline = await currentTime();
      const positionId = (await bank.nextPositionId()).sub(1);
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
              amountOutMin: 1,
            },
            [],
            [],
            false,
            deadline,
          ])
        )
      )
        .to.be.revertedWithCustomError(spell, "EXPIRED")
        .withArgs(deadline);
    });

    it("should revert if received amount is lower than slippage", async () => {
      evm_mine_blocks(1000);

      // Manually transfer CRV rewards to spell
      const amount = utils.parseUnits("10", 18);
      await crv.transfer(spell.address, amount);

      const positionId = (await bank.nextPositionId()).sub(1);
      const iface = new ethers.utils.Interface(SpellABI);

      const rewardFeeRatio = await config.rewardFee();

      const expectedAmount = amount.sub(amount.mul(rewardFeeRatio).div(10000));
      const swapData = await getParaswapCalldata(
        CRV,
        USDC,
        expectedAmount,
        spell.address,
        100
      );

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
            [expectedAmount],
            [swapData.data],
            false,
            7777777777,
          ])
        )
      ).to.be.revertedWith("Not enough coins removed");
    });
    it("should be able to harvest on Curve Gauge", async () => {
      // Manually transfer CRV rewards to spell
      const amount = utils.parseUnits("10", 18);
      await crv.transfer(spell.address, amount);

      const beforeTreasuryBalance = await crv.balanceOf(treasury.address);
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeCrvBalance = await crv.balanceOf(admin.address);

      const positionId = (await bank.nextPositionId()).sub(1);
      const iface = new ethers.utils.Interface(SpellABI);

      const rewardFeeRatio = await config.rewardFee();

      const expectedAmount = amount.sub(amount.mul(rewardFeeRatio).div(10000));
      const swapData = await getParaswapCalldata(
        CRV,
        USDC,
        expectedAmount,
        spell.address,
        100
      );

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
          [expectedAmount],
          [swapData.data],
          false,
          7777777777,
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
