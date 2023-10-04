import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, utils, Contract } from "ethers";
import { ethers, upgrades } from "hardhat";
import {
  BlueBerryBank,
  CoreOracle,
  IWETH,
  MockOracle,
  SoftVault,
  WERC20,
  ProtocolConfig,
  IComptroller,
  ERC20,
  IUniswapV2Router02,
  HardVault,
  FeeManager,
  UniV3WrappedLib,
  CurveStableOracle,
  CurveVolatileOracle,
  CurveTricryptoOracle,
  ShortLongSpell,
  Comptroller,
} from "../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { deployBTokens } from "./money-market";

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const WBTC = ADDRESS.WBTC;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const USDT = ADDRESS.USDT;
const DAI = ADDRESS.DAI;
const FRAX = ADDRESS.FRAX;
const CRV = ADDRESS.CRV;
const AURA = ADDRESS.AURA;
const BAL = ADDRESS.BAL;
const LINK = ADDRESS.LINK;
const ETH_PRICE = 1600;
const BTC_PRICE = 26000;
const LINK_PRICE = 7;

export interface ShortLongProtocol {
  werc20: WERC20;
  mockOracle: MockOracle;
  stableOracle: CurveStableOracle;
  volatileOracle: CurveVolatileOracle;
  tricryptoOracle: CurveTricryptoOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueBerryBank;
  shortLongSpell: ShortLongSpell;
  usdcSoftVault: SoftVault;
  crvSoftVault: SoftVault;
  daiSoftVault: SoftVault;
  linkSoftVault: SoftVault;
  hardVault: HardVault;
  feeManager: FeeManager;
  uniV3Lib: UniV3WrappedLib;
  bUSDC: Contract;
  bICHI: Contract;
  bCRV: Contract;
  bDAI: Contract;
  bMIM: Contract;
  bLINK: Contract;
  bOHM: Contract;
  bSUSHI: Contract;
  bBAL: Contract;
  bALCX: Contract;
  bWETH: Contract;
  bWBTC: Contract;
}

export const setupShortLongProtocol = async (): Promise<ShortLongProtocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let link: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let oracle: CoreOracle;
  let shortLongSpell: ShortLongSpell;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueBerryBank;
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let daiSoftVault: SoftVault;
  let linkSoftVault: SoftVault;
  let wbtcSoftVault: SoftVault;
  let wethSoftVault: SoftVault;
  let hardVault: HardVault;

  let comptroller: Comptroller;
  let bUSDC: Contract;
  let bICHI: Contract;
  let bCRV: Contract;
  let bDAI: Contract;
  let bMIM: Contract;
  let bLINK: Contract;
  let bOHM: Contract;
  let bSUSHI: Contract;
  let bBAL: Contract;
  let bALCX: Contract;
  let bWETH: Contract;
  let bWBTC: Contract;

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
  dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
  crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
  link = <ERC20>await ethers.getContractAt("ERC20", LINK);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

  // Prepare USDC
  // deposit 200 eth -> 200 WETH
  await weth.deposit({ value: utils.parseUnits("200") });

  // swap 40 WETH -> USDC, 40 WETH -> DAI
  await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
  const uniV2Router = <IUniswapV2Router02>(
    await ethers.getContractAt(
      CONTRACT_NAMES.IUniswapV2Router02,
      ADDRESS.UNI_V2_ROUTER
    )
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [WETH, DAI],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [WETH, LINK],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [WETH, WBTC],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Swap 40 weth -> crv
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  const sushiRouter = <IUniswapV2Router02>(
    await ethers.getContractAt(
      CONTRACT_NAMES.IUniswapV2Router02,
      ADDRESS.SUSHI_ROUTER
    )
  );
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [WETH, CRV],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Try to swap some crv to usdc -> Swap router test
  await crv.approve(ADDRESS.SUSHI_ROUTER, 0);
  await crv.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [CRV, WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );

  const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
  const LibInstance = await LinkedLibFactory.deploy();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [WETH, WBTC, LINK, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(BTC_PRICE),
      BigNumber.from(10).pow(18).mul(LINK_PRICE),
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18), // $1
    ]
  );

  const CurveStableOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.CurveStableOracle
  );
  stableOracle = <CurveStableOracle>(
    await CurveStableOracleFactory.deploy(
      mockOracle.address,
      ADDRESS.CRV_ADDRESS_PROVIDER
    )
  );
  await stableOracle.deployed();

  const CurveVolatileOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.CurveVolatileOracle
  );
  volatileOracle = <CurveVolatileOracle>(
    await CurveVolatileOracleFactory.deploy(
      mockOracle.address,
      ADDRESS.CRV_ADDRESS_PROVIDER
    )
  );
  await volatileOracle.deployed();

  const CurveTricryptoOracleFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.CurveTricryptoOracle
  );
  tricryptoOracle = <CurveTricryptoOracle>(
    await CurveTricryptoOracleFactory.deploy(
      mockOracle.address,
      ADDRESS.CRV_ADDRESS_PROVIDER
    )
  );
  await tricryptoOracle.deployed();

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>(
    await upgrades.deployProxy(CoreOracle, { unsafeAllow: ["delegatecall"] })
  );
  await oracle.deployed();

  await oracle.setRoutes(
    [WETH, WBTC, LINK, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
    [
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
    ]
  );

  let bTokens = await deployBTokens(admin.address, oracle.address);
  comptroller = bTokens.comptroller;
  bUSDC = bTokens.bUSDC;
  bICHI = bTokens.bICHI;
  bCRV = bTokens.bCRV;
  bDAI = bTokens.bDAI;
  bMIM = bTokens.bMIM;
  bLINK = bTokens.bLINK;
  bOHM = bTokens.bOHM;
  bSUSHI = bTokens.bSUSHI;
  bBAL = bTokens.bBAL;
  bALCX = bTokens.bALCX;
  bWETH = bTokens.bWETH;
  bWBTC = bTokens.bWBTC;

  // Deploy Bank
  const Config = await ethers.getContractFactory("ProtocolConfig");
  config = <ProtocolConfig>await upgrades.deployProxy(
    Config,
    [treasury.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );
  await config.deployed();
  // config.startVaultWithdrawFee();

  const FeeManager = await ethers.getContractFactory("FeeManager");
  feeManager = <FeeManager>await upgrades.deployProxy(
    FeeManager,
    [config.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );
  await feeManager.deployed();
  await config.setFeeManager(feeManager.address);

  const BlueBerryBank = await ethers.getContractFactory(
    CONTRACT_NAMES.BlueBerryBank
  );
  bank = <BlueBerryBank>(
    await upgrades.deployProxy(
      BlueBerryBank,
      [oracle.address, config.address],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await bank.deployed();

  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  werc20 = <WERC20>(
    await upgrades.deployProxy(WERC20, { unsafeAllow: ["delegatecall"] })
  );
  await werc20.deployed();

  // Deploy CRV spell
  const ShortLongSpell = await ethers.getContractFactory(
    CONTRACT_NAMES.ShortLongSpell
  );
  shortLongSpell = <ShortLongSpell>(
    await upgrades.deployProxy(
      ShortLongSpell,
      [
        bank.address,
        werc20.address,
        WETH,
        AUGUSTUS_SWAPPER,
        TOKEN_TRANSFER_PROXY,
      ],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await shortLongSpell.deployed();
  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);

  usdcSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bUSDC.address, "Interest Bearing USDC", "ibUSDC"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await usdcSoftVault.deployed();

  daiSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bDAI.address, "Interest Bearing DAI", "ibDAI"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await daiSoftVault.deployed();

  crvSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bCRV.address, "Interest Bearing CRV", "ibCRV"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await crvSoftVault.deployed();

  linkSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bLINK.address, "Interest Bearing LINK", "ibLINK"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await linkSoftVault.deployed();

  wbtcSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bWBTC.address, "Interest Bearing WBTC", "ibWBTC"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await wbtcSoftVault.deployed();

  wethSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bWETH.address, "Interest Bearing WETH", "ibWETH"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await wethSoftVault.deployed();

  await mockOracle.setPrice(
    [
      daiSoftVault.address,
      wbtcSoftVault.address,
      wethSoftVault.address,
      linkSoftVault.address,
    ],
    [
      BigNumber.from(10).pow(16), // $1
      BigNumber.from(10).pow(16).mul(BTC_PRICE),
      BigNumber.from(10).pow(16).mul(ETH_PRICE),
      BigNumber.from(10).pow(16).mul(LINK_PRICE),
    ]
  );
  await oracle.setRoutes(
    [daiSoftVault.address, wbtcSoftVault.address, linkSoftVault.address],
    [mockOracle.address, mockOracle.address, mockOracle.address]
  );

  await shortLongSpell.addStrategy(
    daiSoftVault.address,
    utils.parseUnits("10", 18),
    utils.parseUnits("2000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    0,
    [USDC, USDT, DAI],
    [30000, 30000, 30000]
  );

  await shortLongSpell.addStrategy(
    linkSoftVault.address,
    utils.parseUnits("10", 18),
    utils.parseUnits("2000", 18)
  );
  await shortLongSpell.setCollateralsMaxLTVs(
    1,
    [WBTC, DAI, WETH],
    [30000, 30000, 30000]
  );

  // Setup Bank
  await bank.whitelistSpells([shortLongSpell.address], [true]);
  await bank.whitelistTokens(
    [USDC, USDT, DAI, CRV, WETH, WBTC, LINK],
    [true, true, true, true, true, true, true]
  );
  await bank.whitelistERC1155([werc20.address], true);

  const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
  hardVault = <HardVault>await upgrades.deployProxy(
    HardVault,
    [config.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );

  await bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 9000);
  await bank.addBank(DAI, daiSoftVault.address, hardVault.address, 8500);
  await bank.addBank(CRV, crvSoftVault.address, hardVault.address, 9000);
  await bank.addBank(LINK, linkSoftVault.address, hardVault.address, 9000);
  await bank.addBank(WBTC, wbtcSoftVault.address, hardVault.address, 9000);
  await bank.addBank(WETH, wethSoftVault.address, hardVault.address, 9000);

  // Whitelist bank contract on compound
  await comptroller._setCreditLimit(
    bank.address,
    bUSDC.address,
    utils.parseUnits("3000000")
  );
  await comptroller._setCreditLimit(
    bank.address,
    bCRV.address,
    utils.parseUnits("3000000")
  );
  await comptroller._setCreditLimit(
    bank.address,
    bDAI.address,
    utils.parseUnits("3000000")
  );
  await comptroller._setCreditLimit(
    bank.address,
    bLINK.address,
    utils.parseUnits("3000000")
  );
  await comptroller._setCreditLimit(
    bank.address,
    bWBTC.address,
    utils.parseUnits("3000000")
  );

  await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
  await usdc.transfer(alice.address, utils.parseUnits("500", 6));
  await usdcSoftVault.deposit(utils.parseUnits("5000", 6));

  await crv.approve(crvSoftVault.address, ethers.constants.MaxUint256);
  await crv.transfer(alice.address, utils.parseUnits("500", 18));
  await crvSoftVault.deposit(utils.parseUnits("5000", 18));

  await dai.approve(daiSoftVault.address, ethers.constants.MaxUint256);
  await dai.transfer(alice.address, utils.parseUnits("500", 18));
  await daiSoftVault.deposit(utils.parseUnits("5000", 18));

  await link.approve(linkSoftVault.address, ethers.constants.MaxUint256);
  await linkSoftVault.deposit(utils.parseUnits("2000", 18));

  console.log(
    "CRV Balance:",
    utils.formatEther(await crv.balanceOf(admin.address))
  );
  console.log(
    "USDC Balance:",
    utils.formatUnits(await usdc.balanceOf(admin.address), 6)
  );
  console.log(
    "DAI Balance:",
    utils.formatEther(await dai.balanceOf(admin.address))
  );

  return {
    werc20,
    mockOracle,
    stableOracle,
    volatileOracle,
    tricryptoOracle,
    oracle,
    config,
    feeManager,
    bank,
    shortLongSpell,
    usdcSoftVault,
    crvSoftVault,
    daiSoftVault,
    linkSoftVault,
    hardVault,
    uniV3Lib: LibInstance,
    bUSDC,
    bICHI,
    bCRV,
    bDAI,
    bMIM,
    bLINK,
    bOHM,
    bSUSHI,
    bBAL,
    bALCX,
    bWETH,
    bWBTC,
  };
};
