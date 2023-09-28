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
  WConvexPools,
  ConvexSpell,
  Comptroller,
  MockBToken,
} from "../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { deployBTokens } from "./money-market";
import { impersonateAccount } from ".";

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const ETH = ADDRESS.ETH;
const STETH = ADDRESS.STETH;
const FRXETH = ADDRESS.FRXETH;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const USDT = ADDRESS.USDT;
const DAI = ADDRESS.DAI;
const MIM = ADDRESS.MIM;
const SUSD = ADDRESS.SUSD;
const FRAX = ADDRESS.FRAX;
const CRV = ADDRESS.CRV;
const CVXCRV = ADDRESS.CVXCRV;
const CVX = ADDRESS.CVX;
const WBTC = ADDRESS.WBTC;
const WstETH = ADDRESS.wstETH;
const LINK = ADDRESS.LINK;
const ETH_PRICE = 1600;
const BTC_PRICE = 26000;
const LINK_PRICE = 7;

export interface CvxProtocol {
  werc20: WERC20;
  wconvex: WConvexPools;
  mockOracle: MockOracle;
  stableOracle: CurveStableOracle;
  volatileOracle: CurveVolatileOracle;
  tricryptoOracle: CurveTricryptoOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueBerryBank;
  convexSpell: ConvexSpell;
  convexSpellWithVolatileOracle: ConvexSpell;
  usdcSoftVault: SoftVault;
  crvSoftVault: SoftVault;
  daiSoftVault: SoftVault;
  wethSoftVault: SoftVault;
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

export const setupCvxProtocol = async (): Promise<CvxProtocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let wconvex: WConvexPools;
  let mockOracle: MockOracle;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let oracle: CoreOracle;
  let convexSpell: ConvexSpell;
  let convexSpellWithVolatileOracle: ConvexSpell;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueBerryBank;
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let mimSoftVault: SoftVault;
  let daiSoftVault: SoftVault;
  let linkSoftVault: SoftVault;
  let wstETHSoftVault: SoftVault;
  let wethSoftVault: SoftVault;
  let wbtcSoftVault: SoftVault;
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
  let bWstETH: Contract;

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
  dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
  crv = <ERC20>await ethers.getContractAt("ERC20", CRV);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

  // Prepare USDC
  // deposit 80 eth -> 80 WETH
  await weth.deposit({ value: utils.parseUnits("100") });

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
    [WETH, WBTC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits("10"),
    0,
    [WETH, WstETH],
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
    [WETH, MIM],
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

  // Transfer wstETH from whale
  const wstETHWhale = "0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d";
  await admin.sendTransaction({
    to: wstETHWhale,
    value: utils.parseEther("10"),
  });
  await impersonateAccount(wstETHWhale);
  const whale1 = await ethers.getSigner(wstETHWhale);
  let wstETH = <ERC20>await ethers.getContractAt("ERC20", WstETH);
  await wstETH.connect(whale1).transfer(admin.address, utils.parseUnits("30"));

  // Transfer MIM from whale
  const mimWhale = "0x5f0DeE98360d8200b20812e174d139A1a633EDd2";
  await impersonateAccount(mimWhale);
  const whale2 = await ethers.getSigner(mimWhale);
  let mim = <ERC20>await ethers.getContractAt("ERC20", MIM);
  await mim.connect(whale2).transfer(admin.address, utils.parseUnits("10000"));

  const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
  const LibInstance = await LinkedLibFactory.deploy();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [
      ETH,
      WETH,
      STETH,
      WstETH,
      FRXETH,
      WBTC,
      LINK,
      USDC,
      CRV,
      CVXCRV,
      DAI,
      MIM,
      USDT,
      FRAX,
      CVX,
      SUSD,
      ADDRESS.CRV_3Crv
    ],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
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

  let poolInfo = await volatileOracle.callStatic.getPoolInfo(
    ADDRESS.CRV_CRVETH
  );
  await volatileOracle.setLimiter(
    ADDRESS.CRV_CRVETH,
    poolInfo.virtualPrice.mul(99).div(100)
  );

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
    [
      WETH,
      USDC,
      CRV,
      DAI,
      MIM,
      USDT,
      FRAX,
      CVX,
      SUSD,
      WBTC,
      WstETH,
      LINK,
      ADDRESS.CRV_FRXETH,
      ADDRESS.CRV_CVXCRV_CRV,
      ADDRESS.CRV_3Crv,
      ADDRESS.CRV_FRAX3Crv,
      ADDRESS.CRV_SUSD,
      ADDRESS.CRV_CRVETH,
      ADDRESS.CRV_STETH,
      ADDRESS.CRV_MIM3CRV,
    ],
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
      mockOracle.address,
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
      volatileOracle.address,
      stableOracle.address,
      stableOracle.address,
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
  bWstETH = bTokens.bWstETH;

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

  const WConvexPools = await ethers.getContractFactory(
    CONTRACT_NAMES.WConvexPools
  );
  wconvex = <WConvexPools>await upgrades.deployProxy(
    WConvexPools,
    [CVX, ADDRESS.CVX_BOOSTER],
    {
      unsafeAllow: ["delegatecall"],
    }
  );
  await wconvex.deployed();

  // Deploy CRV spell
  const ConvexSpell = await ethers.getContractFactory(
    CONTRACT_NAMES.ConvexSpell
  );
  convexSpell = <ConvexSpell>(
    await upgrades.deployProxy(
      ConvexSpell,
      [
        bank.address,
        werc20.address,
        WETH,
        wconvex.address,
        stableOracle.address,
        AUGUSTUS_SWAPPER,
        TOKEN_TRANSFER_PROXY,
      ],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await convexSpell.deployed();
  // await curveSpell.setSwapRouter(ADDRESS.SUSHI_ROUTER);
  const curveLPs = [
    ADDRESS.CRV_3Crv, // 0
    ADDRESS.CRV_FRAX3Crv, // 1
    ADDRESS.CRV_SUSD, // 2
    ADDRESS.CRV_FRXETH, // 3
    ADDRESS.CRV_STETH, // 4
    ADDRESS.CRV_MIM3CRV, // 5
    ADDRESS.CRV_CVXCRV_CRV, // 6
  ];
  for (let i = 0; i < curveLPs.length; i++) {
    await convexSpell.addStrategy(
      curveLPs[i],
      utils.parseUnits("100", 18),
      utils.parseUnits("2000", 18)
    );
    await convexSpell.setCollateralsMaxLTVs(
      i,
      [USDC, CRV, DAI, WBTC, WstETH, LINK, WETH, MIM],
      [30000, 30000, 30000, 30000, 30000, 30000, 30000, 30000]
    );
  }
  convexSpellWithVolatileOracle = <ConvexSpell>(
    await upgrades.deployProxy(
      ConvexSpell,
      [
        bank.address,
        werc20.address,
        WETH,
        wconvex.address,
        volatileOracle.address,
        AUGUSTUS_SWAPPER,
        TOKEN_TRANSFER_PROXY,
      ],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await convexSpellWithVolatileOracle.deployed();
  await convexSpellWithVolatileOracle.addStrategy(
    ADDRESS.CRV_CRVETH,
    utils.parseUnits("0.5", 18),
    utils.parseUnits("2000", 18)
  );
  await convexSpellWithVolatileOracle.setCollateralsMaxLTVs(
    0,
    [USDC, CRV, DAI],
    [30000, 30000, 30000]
  );

  // Setup Bank
  await bank.whitelistSpells(
    [convexSpell.address, convexSpellWithVolatileOracle.address],
    [true, true]
  );
  await bank.whitelistTokens(
    [USDC, CRV, DAI, WBTC, WstETH, LINK, WETH, MIM],
    [true, true, true, true, true, true, true, true]
  );
  await bank.whitelistERC1155([werc20.address, wconvex.address], true);

  const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
  hardVault = <HardVault>await upgrades.deployProxy(
    HardVault,
    [config.address],
    {
      unsafeAllow: ["delegatecall"],
    }
  );

  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
  usdcSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bUSDC.address, "Interest Bearing USDC", "ibUSDC"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await usdcSoftVault.deployed();
  await bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 9000);

  daiSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bDAI.address, "Interest Bearing DAI", "ibDAI"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await daiSoftVault.deployed();
  await bank.addBank(DAI, daiSoftVault.address, hardVault.address, 8500);

  crvSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bCRV.address, "Interest Bearing CRV", "ibCRV"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await crvSoftVault.deployed();
  await bank.addBank(CRV, crvSoftVault.address, hardVault.address, 9000);

  mimSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bMIM.address, "Interest Bearing MIM", "ibMIM"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await mimSoftVault.deployed();
  await bank.addBank(MIM, mimSoftVault.address, hardVault.address, 8500);

  linkSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bLINK.address, "Interest Bearing LINK", "ibLINK"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await linkSoftVault.deployed();
  await bank.addBank(LINK, linkSoftVault.address, hardVault.address, 9000);

  wstETHSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bWstETH.address, "Interest Bearing WstETH", "ibWstETH"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await wstETHSoftVault.deployed();
  await bank.addBank(WstETH, wstETHSoftVault.address, hardVault.address, 8500);

  wethSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bWETH.address, "Interest Bearing WETH", "ibWETH"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await wethSoftVault.deployed();
  await bank.addBank(WETH, wethSoftVault.address, hardVault.address, 9000);

  wbtcSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bWBTC.address, "Interest Bearing WBTC", "ibWBTC"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await wbtcSoftVault.deployed();
  await bank.addBank(WBTC, wbtcSoftVault.address, hardVault.address, 9000);

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
    bWBTC.address,
    utils.parseUnits("3000000")
  );
  await comptroller._setCreditLimit(
    bank.address,
    bWstETH.address,
    utils.parseUnits("3000000")
  );
  await comptroller._setCreditLimit(
    bank.address,
    bWETH.address,
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

  await weth.deposit({ value: utils.parseUnits("100") });
  await weth.approve(wethSoftVault.address, ethers.constants.MaxUint256);
  await wethSoftVault.deposit(utils.parseUnits("100", 18));

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
    wconvex,
    mockOracle,
    stableOracle,
    volatileOracle,
    tricryptoOracle,
    oracle,
    config,
    feeManager,
    bank,
    convexSpell,
    convexSpellWithVolatileOracle,
    usdcSoftVault,
    crvSoftVault,
    daiSoftVault,
    wethSoftVault,
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
