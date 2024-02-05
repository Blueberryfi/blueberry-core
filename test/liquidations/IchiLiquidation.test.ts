import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import chai, { expect } from "chai";
import { BigNumber, constants, utils } from "ethers";
import { ethers, upgrades, network } from "hardhat";
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
  AuraLiquidator,
  SoftVault,
} from "../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import SpellABI from "../../abi/AuraSpell.json";

import { solidity } from "ethereum-waffle";
import { near } from "../assertions/near";
import { roughlyNear } from "../assertions/roughlyNear";
import {
  AuraProtocol,
  evm_increaseTime,
  evm_mine_blocks,
  setupAuraProtocol,
} from "../helpers";
import { liquidator } from "../../typechain-types/contracts";
import { ichi } from "../../typechain-types/contracts/interfaces";

chai.use(solidity);
chai.use(near);
chai.use(roughlyNear);

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const BAL = ADDRESS.BAL;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const AURA = ADDRESS.AURA;
const POOL_ID = ADDRESS.AURA_UDU_POOL_ID;
const WPOOL_ID = ADDRESS.AURA_WETH_AURA_ID;
const SWAPROUTER = ADDRESS.SWAP_ROUTER;
const POOL_ADDRESSES_PROVIDER = ADDRESS.POOL_ADDRESSES_PROVIDER;
const BALANCER_POOL = ADDRESS.BAL_AURA_WETH_POOL;

describe("Bank Liquidator Aura", () => {
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
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let liquidator: AuraLiquidator;

  before(async () => {
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
    usdcSoftVault = protocol.usdcSoftVault;
    crvSoftVault = protocol.crvSoftVault;

    const LiquidatorInstance = await ethers.getContractFactory(
      CONTRACT_NAMES.AuraLiquidator
    );
    liquidator = <AuraLiquidator>await upgrades.deployProxy(
      LiquidatorInstance,
      [
        POOL_ADDRESSES_PROVIDER,
        bank.address,
        spell.address,
        SWAPROUTER,
        BALANCER_POOL,
        usdc.address,
        AURA,
      ],
      {
        unsafeAllow: ["delegatecall"],
      }
    );

    console.log("Liquidator: ", liquidator.address);
  });

  beforeEach(async () => {});

  describe("Liquidation", () => {
    const depositAmount = utils.parseUnits("100", 18); // worth of $400
    const borrowAmount = utils.parseUnits("300", 6);
    const iface = new ethers.utils.Interface(SpellABI);
    let positionId: BigNumber;

    beforeEach(async () => {
      await mockOracle.setPrice(
        [CRV],
        [
          BigNumber.from(10).pow(18).mul(5), // $5
        ]
      );
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await crv.approve(bank.address, 0);
      await crv.approve(bank.address, ethers.constants.MaxUint256);
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
      positionId = (await bank.nextPositionId()).sub(1);
    });

    it("should be able to liquidate the position => (OV - PV)/CV = LT", async () => {
      await evm_increaseTime(4 * 3600);
      await evm_mine_blocks(10);
      let positionInfo = await bank.getPositionInfo(positionId);
      let debtValue = await bank.callStatic.getDebtValue(positionId);
      let positionValue = await bank.callStatic.getPositionValue(positionId);
      let risk = await bank.callStatic.getPositionRisk(positionId);
      console.log("Debt Value:", utils.formatUnits(debtValue));
      console.log("Position Value:", utils.formatUnits(positionValue));
      console.log("Position Risk:", utils.formatUnits(risk, 2), "%");
      console.log(
        "Position Size:",
        utils.formatUnits(positionInfo.collateralSize)
      );

      const pendingRewardsInfo = await waura.callStatic.pendingRewards(
        positionInfo.collId,
        positionInfo.collateralSize
      );
      console.log("Pending Rewards:", pendingRewardsInfo);

      console.log("===CRV token dumped from $5 to $0.00004===");
      await mockOracle.setPrice(
        [CRV],
        [
          BigNumber.from(10).pow(13).mul(4), // $0.00004
        ]
      );
      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.callStatic.getDebtValue(positionId);
      positionValue = await bank.callStatic.getPositionValue(positionId);
      risk = await bank.callStatic.getPositionRisk(positionId);
      console.log("Cur Pos:", positionInfo);
      console.log("Debt Value:", utils.formatUnits(debtValue));
      console.log("Position Value:", utils.formatUnits(positionValue));
      console.log("Position Risk:", utils.formatUnits(risk, 2), "%");
      console.log(
        "Position Size:",
        utils.formatUnits(positionInfo.collateralSize)
      );

      expect(await bank.isLiquidatable(positionId)).to.be.true;
      console.log("Is Liquidatable:", await bank.isLiquidatable(positionId));

      console.log("===Portion Liquidated===");
      const liqAmount = utils.parseUnits("100", 6);
      await usdc.connect(alice).approve(bank.address, liqAmount);
      await expect(
        bank.connect(alice).liquidate(positionId, USDC, liqAmount)
      ).to.be.emit(bank, "Liquidate");

      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.getDebtValue(positionId);
      positionValue = await bank.getPositionValue(positionId);
      risk = await bank.getPositionRisk(positionId);
      console.log("Cur Pos:", positionInfo);
      console.log("Debt Value:", utils.formatUnits(debtValue));
      console.log("Position Value:", utils.formatUnits(positionValue));
      console.log("Position Risk:", utils.formatUnits(risk, 2), "%");
      console.log(
        "Position Size:",
        utils.formatUnits(positionInfo.collateralSize)
      );

      const colToken = await ethers.getContractAt(
        "ERC1155Upgradeable",
        positionInfo.collToken
      );
      const uVToken = await ethers.getContractAt(
        "ERC20Upgradeable",
        crvSoftVault.address
      );
      console.log(
        "Liquidator's Position Balance:",
        utils.formatUnits(
          await colToken.balanceOf(alice.address, positionInfo.collId)
        )
      );
      console.log(
        "Liquidator's Collateral Balance:",
        utils.formatUnits(await uVToken.balanceOf(alice.address))
      );

      console.log("===Full Liquidate===");
      let prevUSDCBalance = await usdc.balanceOf(alice.address);
      await liquidator.connect(alice).liquidate(positionId);
      let afterUSDCBalance = await usdc.balanceOf(alice.address);
      expect(afterUSDCBalance.sub(prevUSDCBalance)).to.gt(0);

      positionInfo = await bank.getPositionInfo(positionId);
      debtValue = await bank.getDebtValue(positionId);
      positionValue = await bank.getPositionValue(positionId);
      risk = await bank.getPositionRisk(positionId);
      const collateralBalance = await colToken.balanceOf(
        alice.address,
        positionInfo.collId
      );
      console.log("Cur Pos:", positionInfo);
      console.log("Debt Value:", utils.formatUnits(debtValue));
      console.log("Position Value:", utils.formatUnits(positionValue));
      console.log("Position Risk:", utils.formatUnits(risk, 2), "%");
      console.log(
        "Position Size:",
        utils.formatUnits(positionInfo.collateralSize)
      );
      console.log(
        "Liquidator's Position Balance:",
        utils.formatUnits(
          await colToken.balanceOf(alice.address, positionInfo.collId)
        )
      );
      console.log(
        "Liquidator's Collateral Balance:",
        utils.formatUnits(await uVToken.balanceOf(alice.address))
      );

      let beforeCrvBalance = await crv.balanceOf(alice.address);
      await waura
        .connect(alice)
        .burn(positionInfo.collId, ethers.constants.MaxUint256);
      let afterCrvBalance = await crv.balanceOf(alice.address);
      console.log(
        "Liquidator's CRV Balance:",
        utils.formatUnits(afterCrvBalance.sub(beforeCrvBalance), 18)
      );
    });
  });
});