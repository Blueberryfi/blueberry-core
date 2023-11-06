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
  PoolEscrow,
  PoolEscrowFactory,
} from "../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import { deployBTokens } from "./money-market";

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const CUSDC = ADDRESS.bUSDC;
const CDAI = ADDRESS.bDAI;
const CCRV = ADDRESS.bCRV;
const ETH = ADDRESS.ETH;
const STETH = ADDRESS.STETH;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const USDT = ADDRESS.USDT;
const DAI = ADDRESS.DAI;
const SUSD = ADDRESS.SUSD;
const FRAX = ADDRESS.FRAX;
const CRV = ADDRESS.CRV;
const CVX = ADDRESS.CVX;
const ETH_PRICE = 1600;

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

  let escrowBase: PoolEscrow;
  let escrowFactory: PoolEscrowFactory;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueBerryBank;
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let daiSoftVault: SoftVault;
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
    utils.parseUnits("30"),
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits("30"),
    0,
    [WETH, DAI],
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
    utils.parseUnits("40"),
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
    [ETH, WETH, STETH, USDC, CRV, DAI, USDT, FRAX, CVX, SUSD],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
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
      USDT,
      FRAX,
      CVX,
      SUSD,
      ADDRESS.CRV_3Crv,
      ADDRESS.CRV_FRAX3Crv,
      ADDRESS.CRV_SUSD,
      ADDRESS.CRV_CRVETH,
      ADDRESS.CRV_STETH,
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
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
      volatileOracle.address,
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

  const escrowBaseFactory = await ethers.getContractFactory("PoolEscrow");
  escrowBase = await escrowBaseFactory.deploy();

  await escrowBase.deployed();

  const escrowFactoryFactory = await ethers.getContractFactory(
    "PoolEscrowFactory"
  );
  escrowFactory = await escrowFactoryFactory.deploy(escrowBase.address);

  await escrowFactory.deployed();

  const WConvexPoolsFactory = await ethers.getContractFactory(
    CONTRACT_NAMES.WConvexPools
  );

  wconvex = <WConvexPools>(
    await upgrades.deployProxy(
      WConvexPoolsFactory,
      [CVX, ADDRESS.CVX_BOOSTER, escrowFactory.address],
      { unsafeAllow: ["delegatecall"] }
    )
  );

  escrowFactory.initialize(wconvex.address, ADDRESS.CVX_BOOSTER);

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
  await convexSpell.addStrategy(
    ADDRESS.CRV_3Crv,
    utils.parseUnits("100", 18),
    utils.parseUnits("2000", 18)
  );
  await convexSpell.addStrategy(
    ADDRESS.CRV_FRAX3Crv,
    utils.parseUnits("100", 18),
    utils.parseUnits("2000", 18)
  );
  await convexSpell.addStrategy(
    ADDRESS.CRV_SUSD,
    utils.parseUnits("100", 18),
    utils.parseUnits("2000", 18)
  );
  await convexSpell.addStrategy(
    ADDRESS.CRV_STETH,
    utils.parseUnits("100", 18),
    utils.parseUnits("2000", 18)
  );
  await convexSpell.setCollateralsMaxLTVs(
    0,
    [USDC, CRV, DAI],
    [30000, 30000, 30000]
  );
  await convexSpell.setCollateralsMaxLTVs(
    1,
    [USDC, CRV, DAI],
    [30000, 30000, 30000]
  );
  await convexSpell.setCollateralsMaxLTVs(2, [USDC, CRV, DAI], [300, 300, 300]);
  await convexSpell.setCollateralsMaxLTVs(3, [USDC, DAI], [30000, 30000]);
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
  await bank.whitelistTokens([WETH, USDC, CRV, DAI], [true, true, true, true]);
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

  wethSoftVault = <SoftVault>(
    await upgrades.deployProxy(
      SoftVault,
      [config.address, bWETH.address, "Interest Bearing WETH", "ibWETH"],
      { unsafeAllow: ["delegatecall"] }
    )
  );
  await wethSoftVault.deployed();
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
