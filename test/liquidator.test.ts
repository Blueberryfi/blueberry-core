import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import chai, { expect } from "chai";
import { BigNumber, constants, utils } from "ethers";
import { ethers, upgrades, network } from "hardhat";
import {
  BlueBerryBank,
  CoreOracle,
  IchiSpell,
  IWETH,
  SoftVault,
  MockOracle,
  IchiVaultOracle,
  WERC20,
  WIchiFarm,
  ProtocolConfig,
  MockIchiVault,
  ERC20,
  MockIchiV2,
  MockIchiFarm,
  HardVault,
  FeeManager,
  Liquidator,
} from "../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../constant";
import SpellABI from "../abi/IchiSpell.json";

import { solidity } from "ethereum-waffle";
import { near } from "./assertions/near";
import { roughlyNear } from "./assertions/roughlyNear";
import { Protocol, setupProtocol } from "./setup-test";
import { evm_mine_blocks } from "./helpers";

chai.use(solidity);
chai.use(near);
chai.use(roughlyNear);

const CUSDC = ADDRESS.bUSDC;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId
const SWAPROUTER = ADDRESS.SWAP_ROUTER;
const POOL_ADDRESSES_PROVIDER = ADDRESS.POOL_ADDRESSES_PROVIDER;

describe("Bank", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let ichiOracle: IchiVaultOracle;
  let oracle: CoreOracle;
  let spell: IchiSpell;
  let wichi: WIchiFarm;
  let bank: BlueBerryBank;
  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let usdcSoftVault: SoftVault;
  let ichiSoftVault: SoftVault;
  let hardVault: HardVault;
  let ichiFarm: MockIchiFarm;
  let ichiVault: MockIchiVault;
  let protocol: Protocol;
  let liquidator: Liquidator;

  before(async () => {
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`,
          },
        },
      ],
    });

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    ichi = <MockIchiV2>await ethers.getContractAt("MockIchiV2", ICHI);
    ichiV1 = <ERC20>await ethers.getContractAt("ERC20", ICHIV1);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

    protocol = await setupProtocol();
    config = protocol.config;
    feeManager = protocol.feeManager;
    bank = protocol.bank;
    spell = protocol.spell;
    ichiFarm = protocol.ichiFarm;
    ichiVault = protocol.ichi_USDC_ICHI_Vault;
    wichi = protocol.wichi;
    werc20 = protocol.werc20;
    oracle = protocol.oracle;
    mockOracle = protocol.mockOracle;
    usdcSoftVault = protocol.usdcSoftVault;
    ichiSoftVault = protocol.ichiSoftVault;
    hardVault = protocol.hardVault;

    const LiquidatorInstance = await ethers.getContractFactory(
      CONTRACT_NAMES.Liquidator
    );
    liquidator = <Liquidator>(
      await upgrades.deployProxy(LiquidatorInstance, [
        POOL_ADDRESSES_PROVIDER,
        bank.address,
        SWAPROUTER,
        usdc.address,
        ichi.address,
      ])
    );
    await liquidator.deployed();

    console.log("Liquidator: ", liquidator.address);
  });

  beforeEach(async () => {});

  describe("Constructor", () => {
    it("should revert Bank deployment when invalid args provided", async () => {
      const BlueBerryBank = await ethers.getContractFactory(
        CONTRACT_NAMES.BlueBerryBank
      );
      await expect(
        upgrades.deployProxy(BlueBerryBank, [
          ethers.constants.AddressZero,
          config.address,
          feeManager.address,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");

      await expect(
        upgrades.deployProxy(BlueBerryBank, [
          oracle.address,
          ethers.constants.AddressZero,
          feeManager.address,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");

      await expect(
        upgrades.deployProxy(BlueBerryBank, [
          oracle.address,
          config.address,
          ethers.constants.AddressZero,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");
    });
    it("should initialize states on constructor", async () => {
      const BlueBerryBank = await ethers.getContractFactory(
        CONTRACT_NAMES.BlueBerryBank
      );
      const bank = <BlueBerryBank>(
        await upgrades.deployProxy(BlueBerryBank, [
          oracle.address,
          config.address,
          feeManager.address,
        ])
      );
      await bank.deployed();

      expect(await bank._GENERAL_LOCK()).to.be.equal(1);
      expect(await bank._IN_EXEC_LOCK()).to.be.equal(1);
      expect(await bank.POSITION_ID()).to.be.equal(ethers.constants.MaxUint256);
      expect(await bank.SPELL()).to.be.equal(
        "0x0000000000000000000000000000000000000001"
      );
      expect(await bank.oracle()).to.be.equal(oracle.address);
      expect(await bank.config()).to.be.equal(config.address);
      expect(await bank.nextPositionId()).to.be.equal(1);
      expect(await bank.bankStatus()).to.be.equal(15);
    });
  });

  describe("Liquidation", () => {
    const depositAmount = utils.parseUnits("100", 18); // worth of $400
    const borrowAmount = utils.parseUnits("300", 6);
    const iface = new ethers.utils.Interface(SpellABI);

    beforeEach(async () => {
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(18).mul(5), // $5
        ]
      );
      await usdc.approve(bank.address, ethers.constants.MaxUint256);
      await ichi.approve(bank.address, ethers.constants.MaxUint256);
      await bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData("openPositionFarm", [
          {
            strategyId: 0,
            collToken: ICHI,
            borrowToken: USDC,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPid: ICHI_VAULT_PID,
          },
        ])
      );
    });

    it("should be able to liquidate the position => (OV - PV)/CV = LT", async () => {
      await evm_mine_blocks(10);
      await ichiVault.rebalance(-260400, -260200, -260800, -260600, 0);
      let positionInfo = await bank.getPositionInfo(1);
      let debtValue = await bank.getDebtValue(1);
      let positionValue = await bank.getPositionValue(1);
      let risk = await bank.getPositionRisk(1);
      console.log("Debt Value:", utils.formatUnits(debtValue));
      console.log("Position Value:", utils.formatUnits(positionValue));
      console.log("Position Risk:", utils.formatUnits(risk, 2), "%");
      console.log(
        "Position Size:",
        utils.formatUnits(positionInfo.collateralSize)
      );

      const pendingIchi = await ichiFarm.pendingIchi(
        ICHI_VAULT_PID,
        wichi.address
      );
      console.log("Pending ICHI:", utils.formatUnits(pendingIchi, 9));
      await ichiV1.transfer(ichiFarm.address, pendingIchi.mul(100));
      await ichiFarm.updatePool(ICHI_VAULT_PID);

      console.log("===ICHI token dumped from $5 to $1===");
      await mockOracle.setPrice(
        [ICHI],
        [
          BigNumber.from(10).pow(17).mul(10), // $0.5
        ]
      );
      positionInfo = await bank.getPositionInfo(1);
      debtValue = await bank.getDebtValue(1);
      positionValue = await bank.getPositionValue(1);
      risk = await bank.getPositionRisk(1);
      console.log("Cur Pos:", positionInfo);
      console.log("Debt Value:", utils.formatUnits(debtValue));
      console.log("Position Value:", utils.formatUnits(positionValue));
      console.log("Position Risk:", utils.formatUnits(risk, 2), "%");
      console.log(
        "Position Size:",
        utils.formatUnits(positionInfo.collateralSize)
      );

      expect(await bank.isLiquidatable(1)).to.be.true;
      console.log("Is Liquidatable:", await bank.isLiquidatable(1));

      console.log("===Portion Liquidated===");
      const liqAmount = utils.parseUnits("100", 6);
      await usdc.connect(alice).approve(bank.address, liqAmount);
      await expect(
        bank.connect(alice).liquidate(1, USDC, liqAmount)
      ).to.be.emit(bank, "Liquidate");

      positionInfo = await bank.getPositionInfo(1);
      debtValue = await bank.getDebtValue(1);
      positionValue = await bank.getPositionValue(1);
      risk = await bank.getPositionRisk(1);
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
        ichiSoftVault.address
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
      await liquidator.connect(alice).liquidate(1);
      let afterUSDCBalance = await usdc.balanceOf(alice.address);
      expect(afterUSDCBalance.sub(prevUSDCBalance)).to.gt(0);

      positionInfo = await bank.getPositionInfo(1);
      debtValue = await bank.getDebtValue(1);
      positionValue = await bank.getPositionValue(1);
      risk = await bank.getPositionRisk(1);
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
      console.log("Liquidator's Position Balance:", collateralBalance);
      console.log(
        "Liquidator's Collateral Balance:",
        await uVToken.balanceOf(alice.address)
      );

      let beforeIchiBalance = await ichi.balanceOf(alice.address);
      await wichi
        .connect(alice)
        .burn(positionInfo.collId, ethers.constants.MaxUint256);
      let afterIchiBalance = await ichi.balanceOf(alice.address);
      console.log(
        "Liquidator's ICHI Balance:",
        utils.formatUnits(afterIchiBalance.sub(beforeIchiBalance), 18)
      );

      const lpBalance = await ichiVault.balanceOf(alice.address);
      await ichiVault.connect(alice).withdraw(lpBalance, alice.address);
    });
  });
});
