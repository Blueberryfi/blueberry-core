import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, utils, Contract } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
  BlueberryBank,
  CoreOracle,
  IWETH,
  MockOracle,
  SoftVault,
  WERC20,
  ProtocolConfig,
  ERC20,
  IUniswapV2Router02,
  HardVault,
  FeeManager,
  UniV3WrappedLib,
  CurveStableOracle,
  CurveVolatileOracle,
  CurveTricryptoOracle,
  WConvexBooster,
  ConvexSpell,
  Comptroller,
  PoolEscrow,
  PoolEscrowFactory,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { deployBTokens } from './money-market';
import { impersonateAccount } from '.';
import { deploySoftVaults } from './markets';

/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable prefer-const */

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const CUSDC = ADDRESS.bUSDC;
const CDAI = ADDRESS.bDAI;
const CCRV = ADDRESS.bCRV;
const ETH = ADDRESS.ETH;
const STETH = ADDRESS.STETH;
const FRXETH = ADDRESS.FRXETH;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const USDT = ADDRESS.USDT;
const DAI = ADDRESS.DAI;
const MIM = ADDRESS.MIM;
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
  wconvex: WConvexBooster;
  mockOracle: MockOracle;
  stableOracle: CurveStableOracle;
  volatileOracle: CurveVolatileOracle;
  tricryptoOracle: CurveTricryptoOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueberryBank;
  convexSpell: ConvexSpell;
  convexSpellWithVolatileOracle: ConvexSpell;

  feeManager: FeeManager;
  uniV3Lib: UniV3WrappedLib;
}

export const setupCvxProtocol = async (minimized: boolean = false): Promise<CvxProtocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let wconvex: WConvexBooster;
  let mockOracle: MockOracle;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let oracle: CoreOracle;
  let convexSpell: ConvexSpell;
  let convexSpellWithVolatileOracle: ConvexSpell;

  let escrowFactory: PoolEscrowFactory;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueberryBank;

  let comptroller: Comptroller;

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
  dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
  crv = <ERC20>await ethers.getContractAt('ERC20', CRV);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

  // Prepare USDC
  // deposit 80 eth -> 80 WETH
  await weth.deposit({ value: utils.parseUnits('100') });

  // swap 40 WETH -> USDC, 40 WETH -> DAI
  await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
  const uniV2Router = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [WETH, WBTC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [WETH, DAI],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [WETH, MIM],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [WETH, LINK],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Swap 40 weth -> crv
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  const sushiRouter = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.SUSHI_ROUTER)
  );
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [WETH, CRV],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Try to swap some crv to usdc -> Swap router test
  await crv.approve(ADDRESS.SUSHI_ROUTER, 0);
  await crv.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('10'),
    0,
    [CRV, WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Transfer wstETH from whale
  const wstETHWhale = minimized
    ? '0xb013Ce9a2ccf40b2097Da5B36E2d1e7ccFFbB77d'
    : '0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d';
  await admin.sendTransaction({
    to: wstETHWhale,
    value: utils.parseEther('10'),
  });
  await impersonateAccount(wstETHWhale);
  const whale1 = await ethers.getSigner(wstETHWhale);
  const wstETH = <ERC20>await ethers.getContractAt('ERC20', WstETH);
  await wstETH.connect(whale1).transfer(admin.address, utils.parseUnits('30'));
  // Transfer MIM from whale
  const mimWhale = '0x5f0DeE98360d8200b20812e174d139A1a633EDd2';
  await impersonateAccount(mimWhale);
  const whale2 = await ethers.getSigner(mimWhale);
  const mim = <ERC20>await ethers.getContractAt('ERC20', MIM);
  await mim.connect(whale2).transfer(admin.address, utils.parseUnits('10000'));

  const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
  const LibInstance = await LinkedLibFactory.deploy();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [ETH, WETH, STETH, WstETH, FRXETH, WBTC, LINK, USDC, CRV, CVXCRV, DAI, MIM, USDT, FRAX, CVX, ADDRESS.CRV_3Crv],
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
    ]
  );

  const CurveStableOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveStableOracle);
  stableOracle = <CurveStableOracle>(
    await upgrades.deployProxy(
      CurveStableOracleFactory,
      [ADDRESS.CRV_ADDRESS_PROVIDER, mockOracle.address, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  await stableOracle.deployed();

  const CurveVolatileOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveVolatileOracle);
  volatileOracle = <CurveVolatileOracle>(
    await upgrades.deployProxy(
      CurveVolatileOracleFactory,
      [ADDRESS.CRV_ADDRESS_PROVIDER, mockOracle.address, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  await volatileOracle.deployed();

  const CurveTricryptoOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveTricryptoOracle);
  tricryptoOracle = <CurveTricryptoOracle>(
    await upgrades.deployProxy(
      CurveTricryptoOracleFactory,
      [ADDRESS.CRV_ADDRESS_PROVIDER, mockOracle.address, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  await tricryptoOracle.deployed();

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
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
      WBTC,
      WstETH,
      LINK,
      ADDRESS.CRV_FRXETH,
      ADDRESS.CRV_CVXCRV_CRV,
      ADDRESS.CRV_3Crv,
      ADDRESS.CRV_FRAX3Crv,
      ADDRESS.CRV_CVXETH,
      ADDRESS.CRV_STETH,
      ADDRESS.CRV_MIM3CRV,
      ADDRESS.CRV_FRAXUSDC,
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
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
      volatileOracle.address,
      stableOracle.address,
      stableOracle.address,
      stableOracle.address,
    ]
  );

  await stableOracle.registerCurveLp(ADDRESS.CRV_FRXETH);
  await stableOracle.registerCurveLp(ADDRESS.CRV_CVXCRV_CRV);
  await stableOracle.registerCurveLp(ADDRESS.CRV_3Crv);
  await stableOracle.registerCurveLp(ADDRESS.CRV_FRAX3Crv);
  await volatileOracle.registerCurveLp(ADDRESS.CRV_CVXETH);
  await stableOracle.registerCurveLp(ADDRESS.CRV_STETH);
  await stableOracle.registerCurveLp(ADDRESS.CRV_MIM3CRV);
  await stableOracle.registerCurveLp(ADDRESS.CRV_FRAXUSDC);

  const bTokens = await deployBTokens(admin.address, oracle.address);
  comptroller = bTokens.comptroller;

  // Deploy Bank
  const Config = await ethers.getContractFactory('ProtocolConfig');
  config = <ProtocolConfig>await upgrades.deployProxy(Config, [treasury.address, admin.address], {
    unsafeAllow: ['delegatecall'],
  });
  await config.deployed();
  // config.startVaultWithdrawFee();

  const FeeManager = await ethers.getContractFactory('FeeManager');
  feeManager = <FeeManager>await upgrades.deployProxy(FeeManager, [config.address, admin.address], {
    unsafeAllow: ['delegatecall'],
  });
  await feeManager.deployed();
  await config.setFeeManager(feeManager.address);

  const BlueberryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueberryBank);
  bank = <BlueberryBank>await upgrades.deployProxy(BlueberryBank, [oracle.address, config.address, admin.address], {
    unsafeAllow: ['delegatecall'],
  });
  await bank.deployed();

  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  werc20 = <WERC20>await upgrades.deployProxy(WERC20, [admin.address], { unsafeAllow: ['delegatecall'] });
  await werc20.deployed();

  const escrowFactoryFactory = await ethers.getContractFactory('PoolEscrowFactory');
  escrowFactory = <PoolEscrowFactory>await upgrades.deployProxy(escrowFactoryFactory, [admin.address], {
    unsafeAllow: ['delegatecall'],
  });
  await escrowFactory.deployed();

  const WConvexBoosterFactory = await ethers.getContractFactory(CONTRACT_NAMES.WConvexBooster);

  wconvex = <WConvexBooster>await upgrades.deployProxy(
    WConvexBoosterFactory,
    [CVX, ADDRESS.CVX_BOOSTER, escrowFactory.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  await wconvex.deployed();
  // Deploy CRV spell
  const ConvexSpell = await ethers.getContractFactory(CONTRACT_NAMES.ConvexSpell);
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
        admin.address,
      ],
      { unsafeAllow: ['delegatecall'] }
    )
  );
  await convexSpell.deployed();
  // await curveSpell.setSwapRouter(ADDRESS.SUSHI_ROUTER);
  const curveLPs = [
    ADDRESS.CRV_3Crv, // 0  - ||||||||| 0
    ADDRESS.CRV_FRAX3Crv, // 1  - ||||||1
    ADDRESS.CRV_FRXETH, // 2
    ADDRESS.CRV_STETH, // 3  - |||||||| 3
    ADDRESS.CRV_MIM3CRV, // 4
    ADDRESS.CRV_CVXCRV_CRV, // 5
    ADDRESS.CRV_FRAXUSDC, // 6 -||||||| 4
  ];
  for (let i = 0; i < curveLPs.length; i++) {
    await convexSpell.addStrategy(curveLPs[i], utils.parseUnits('100', 18), utils.parseUnits('2000', 18));
    await convexSpell.setCollateralsMaxLTVs(
      i,
      [USDC, CRV, DAI, WBTC, WstETH, LINK, WETH, MIM, curveLPs[i]],
      [30000, 30000, 30000, 30000, 30000, 30000, 30000, 30000, 30000]
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
        admin.address,
      ],
      { unsafeAllow: ['delegatecall'] }
    )
  );
  await convexSpellWithVolatileOracle.deployed();
  await convexSpellWithVolatileOracle.addStrategy(
    ADDRESS.CRV_CVXETH,
    utils.parseUnits('0.5', 18),
    utils.parseUnits('2000', 18)
  );
  await convexSpellWithVolatileOracle.setCollateralsMaxLTVs(0, [USDC, CRV, DAI], [30000, 30000, 30000]);

  // Setup Bank
  await bank.whitelistSpells([convexSpell.address, convexSpellWithVolatileOracle.address], [true, true]);
  await bank.whitelistTokens(
    [
      WETH,
      USDC,
      CRV,
      DAI,
      WBTC,
      WstETH,
      LINK,
      WETH,
      MIM,
      ADDRESS.CRV_STETH,
      ADDRESS.CRV_FRXETH,
      ADDRESS.CRV_MIM3CRV,
      ADDRESS.CRV_CVXCRV_CRV,
    ],
    [true, true, true, true, true, true, true, true, true, true, true, true, true]
  );
  await bank.whitelistERC1155([werc20.address, wconvex.address], true);

  await deploySoftVaults(config, bank, comptroller, bTokens.bTokens, admin, alice);

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
    uniV3Lib: LibInstance,
  };
};
