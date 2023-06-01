import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  MockBank,
  MockParaswap,
  MockParaswapTransferProxy,
  BlueBerryBank,
  IWETH,
  MockOracle,
  WERC20,
  MockWETH,
  WCurveGauge,
  ERC20,
  CurveSpell,
  CurveOracle,
  WAuraPools,
  ICvxPools,
  IRewarder,
  AuraSpell,
  ShortLongSpell__factory,
  ShortLongSpell,
} from "../../typechain-types";
import { ethers, upgrades } from "hardhat";
import { constants } from "ethers";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { AuraProtocol, evm_mine_blocks, setupAuraProtocol } from "../helpers";
import SpellABI from "../../abi/AuraSpell.json";
import chai, { expect } from "chai";
import { solidity } from "ethereum-waffle";
import { near } from "../assertions/near";
import { roughlyNear } from "../assertions/roughlyNear";
import { BigNumber, Contract, utils } from "ethers";

chai.use(solidity);
chai.use(near);
chai.use(roughlyNear);

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

describe("ShortLongSpell", () => {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let aura: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let spell: ShortLongSpell;
  let curveOracle: CurveOracle;
  let waura: WAuraPools;
  let bank: MockBank;
  let protocol: AuraProtocol;
  let auraBooster: ICvxPools;
  let auraRewarder: IRewarder;
  let tokenTransferProxy: MockParaswapTransferProxy;
  let augustusSwapper: MockParaswap;

  beforeEach(async () => {
    [owner, alice, treasury] = await ethers.getSigners();
    const ShortLongSpell = await ethers.getContractFactory(
      CONTRACT_NAMES.ShortLongSpell
    );

    const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
    werc20 = <WERC20>await upgrades.deployProxy(WERC20);

    const MockWethFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.MockWETH
    );
    weth = <IWETH>await MockWethFactory.deploy();

    const MockBankFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.MockBank
    );
    bank = <MockBank>await MockBankFactory.deploy();

    const MockParaswapTransferProxyFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.MockParaswapTransferProxy
    );
    tokenTransferProxy = <MockParaswapTransferProxy>(
      await MockParaswapTransferProxyFactory.deploy()
    );

    const MockParaswapFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.MockParaswap
    );
    augustusSwapper = <MockParaswap>(
      await MockParaswapFactory.deploy(tokenTransferProxy.address)
    );

    const ShortLongSpellFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.ShortLongSpell
    );

    spell = <ShortLongSpell>(
      await upgrades.deployProxy(ShortLongSpellFactory, [
        bank.address,
        werc20.address,
        weth.address,
        augustusSwapper.address,
        tokenTransferProxy.address,
      ])
    );

    // usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    // dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    // crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
    // aura = <ERC20>await ethers.getContractAt("ERC20", AURA);
    // usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
    // weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
    // auraBooster = <ICvxPools>(
    //   await ethers.getContractAt("ICvxPools", ADDRESS.AURA_BOOSTER)
    // );
    // const poolInfo = await auraBooster.poolInfo(ADDRESS.AURA_UDU_POOL_ID);
    // auraRewarder = <IRewarder>(
    //   await ethers.getContractAt("IRewarder", poolInfo.crvRewards)
    // );

    // protocol = await setupAuraProtocol();
    // bank = protocol.bank;
    // spell = protocol.auraSpell;
    // waura = protocol.waura;
    // werc20 = protocol.werc20;
    // mockOracle = protocol.mockOracle;
    // curveOracle = protocol.curveOracle;
  });

  describe("Constructor", () => {
    let ShortLongSpellFactory: ShortLongSpell__factory;

    beforeEach(async () => {
      ShortLongSpellFactory = await ethers.getContractFactory(
        CONTRACT_NAMES.ShortLongSpell
      );
    });

    it("should revert when bank is address(0)", async () => {
      await expect(
        upgrades.deployProxy(ShortLongSpellFactory, [
          constants.AddressZero,
          werc20.address,
          weth.address,
          augustusSwapper.address,
          tokenTransferProxy.address,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("should revert when werc20 is address(0)", async () => {
      await expect(
        upgrades.deployProxy(ShortLongSpellFactory, [
          bank.address,
          constants.AddressZero,
          weth.address,
          augustusSwapper.address,
          tokenTransferProxy.address,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("should revert when weth is address(0)", async () => {
      await expect(
        upgrades.deployProxy(ShortLongSpellFactory, [
          bank.address,
          werc20.address,
          constants.AddressZero,
          augustusSwapper.address,
          tokenTransferProxy.address,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("should revert when augustus swapper is address(0)", async () => {
      await expect(
        upgrades.deployProxy(ShortLongSpellFactory, [
          bank.address,
          werc20.address,
          weth.address,
          constants.AddressZero,
          tokenTransferProxy.address,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("should revert when token transfer proxy is address(0)", async () => {
      await expect(
        upgrades.deployProxy(ShortLongSpellFactory, [
          bank.address,
          werc20.address,
          weth.address,
          augustusSwapper.address,
          constants.AddressZero,
        ])
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("Check initial values", async () => {
      expect(await spell.bank()).to.eq(bank.address);
      expect(await spell.werc20()).to.eq(werc20.address);
      expect(await spell.WETH()).to.eq(weth.address);
      expect(await spell.augustusSwapper()).to.eq(augustusSwapper.address);
      expect(await spell.tokenTransferProxy()).to.eq(
        tokenTransferProxy.address
      );
      expect(await spell.owner()).to.eq(owner.address);
      expect(await werc20.isApprovedForAll(spell.address, bank.address)).to.be
        .true;
    });

    it("should revert initializing twice", async () => {
      await expect(
        spell.initialize(
          bank.address,
          werc20.address,
          weth.address,
          augustusSwapper.address,
          constants.AddressZero
        )
      ).to.be.revertedWith("Initializable: contract is already initialized");
    });
  });

  // TODO: move to BasicSpell unit test
  describe("#addStrategy", () => {
    it("should revert when msg.sender is not owner", async () => {
      await expect(
        spell.connect(alice).addStrategy(weth.address, 10)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should revert when vault is address(0)", async () => {
      await expect(
        spell.connect(owner).addStrategy(constants.AddressZero, 10)
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("should revert when maxPosSize is 0", async () => {
      await expect(
        spell.connect(owner).addStrategy(weth.address, 0)
      ).to.be.revertedWith("ZERO_AMOUNT");
    });

    it("should add new strategy", async () => {
      await spell.connect(owner).addStrategy(weth.address, 10);

      const strategy = await spell.strategies(0);
      expect(strategy.vault).to.eq(weth.address);
      expect(strategy.maxPositionSize).to.eq(10);
    });

    it("should emit StrategyAdded event", async () => {
      const tx = await spell.connect(owner).addStrategy(weth.address, 10);

      await expect(tx)
        .to.emit(spell, "StrategyAdded")
        .withArgs(0, weth.address, 10);
    });
  });
});
