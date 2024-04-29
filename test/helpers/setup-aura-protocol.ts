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
  WAuraBooster,
  AuraSpell,
  Comptroller,
  PoolEscrow,
  PoolEscrowFactory,
  IAuraBooster,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { deployBTokens } from './money-market';

/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable prefer-const */

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const STASH_AURA = ADDRESS.STASH_AURA;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const USDT = ADDRESS.USDT;
const DAI = ADDRESS.DAI;
const FRAX = ADDRESS.FRAX;
const CRV = ADDRESS.CRV;
const AURA = ADDRESS.AURA;
const BAL = ADDRESS.BAL;
const ETH_PRICE = 1600;

export interface AuraProtocol {
  werc20: WERC20;
  waura: WAuraBooster;
  mockOracle: MockOracle;
  stableOracle: CurveStableOracle;
  volatileOracle: CurveVolatileOracle;
  tricryptoOracle: CurveTricryptoOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueberryBank;
  auraSpell: AuraSpell;
  auraBooster: IAuraBooster;
  usdcSoftVault: SoftVault;
  crvSoftVault: SoftVault;
  daiSoftVault: SoftVault;
  hardVault: HardVault;
  feeManager: FeeManager;
  uniV3Lib: UniV3WrappedLib;
  bUSDC: Contract;
  bICHI: Contract;
  bCRV: Contract;
  bDAI: Contract;
  bMIM: Contract;
  bLINK: Contract;
  // bSUSHI: Contract;
  bBAL: Contract;
  //bALCX: Contract;
  bWETH: Contract;
  bWBTC: Contract;
}

export const setupAuraProtocol = async (): Promise<AuraProtocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let waura: WAuraBooster;
  let mockOracle: MockOracle;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let oracle: CoreOracle;
  let auraSpell: AuraSpell;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueberryBank;
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let daiSoftVault: SoftVault;
  let hardVault: HardVault;

  let escrowBase: PoolEscrow;
  let escrowFactory: PoolEscrowFactory;

  let comptroller: Comptroller;
  let bUSDC: Contract;
  let bICHI: Contract;
  let bCRV: Contract;
  let bDAI: Contract;
  let bMIM: Contract;
  let bLINK: Contract;
  let bSUSHI: Contract;
  let bBAL: Contract;
  //let bALCX: Contract;
  let bWETH: Contract;
  let bWBTC: Contract;
  let bTokenAdmin: Contract;

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
    utils.parseUnits('30'),
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('30'),
    0,
    [WETH, DAI],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Swap 40 weth -> crv
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  const sushiRouter = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.SUSHI_ROUTER)
  );
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('40'),
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

  const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
  const LibInstance = await LinkedLibFactory.deploy();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [WETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
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
      [mockOracle.address, ADDRESS.CRV_ADDRESS_PROVIDER, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  await stableOracle.deployed();

  const CurveVolatileOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveVolatileOracle);
  volatileOracle = <CurveVolatileOracle>(
    await upgrades.deployProxy(
      CurveVolatileOracleFactory,
      [mockOracle.address, ADDRESS.CRV_ADDRESS_PROVIDER, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  await volatileOracle.deployed();

  const CurveTricryptoOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CurveTricryptoOracle);
  tricryptoOracle = <CurveTricryptoOracle>(
    await upgrades.deployProxy(
      CurveTricryptoOracleFactory,
      [mockOracle.address, ADDRESS.CRV_ADDRESS_PROVIDER, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );

  await tricryptoOracle.deployed();

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
  await oracle.deployed();

  await oracle.setRoutes(
    [WETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
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
    ]
  );

  const bTokens = await deployBTokens(admin.address);
  comptroller = bTokens.comptroller;
  bUSDC = bTokens.bUSDC;
  bICHI = bTokens.bICHI;
  bCRV = bTokens.bCRV;
  bDAI = bTokens.bDAI;
  bMIM = bTokens.bMIM;
  bLINK = bTokens.bLINK;
  // bSUSHI = bTokens.bSUSHI;
  bBAL = bTokens.bBAL;
  //bALCX = bTokens.bALCX;
  bWETH = bTokens.bWETH;
  bWBTC = bTokens.bWBTC;
  bTokenAdmin = bTokens.bTokenAdmin;

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

  const balancerVault = await ethers.getContractAt('IBalancerVault', ADDRESS.BALANCER_VAULT);

  const WAuraBooster = await ethers.getContractFactory(CONTRACT_NAMES.WAuraBooster);
  waura = <WAuraBooster>await upgrades.deployProxy(
    WAuraBooster,
    [AURA, ADDRESS.AURA_BOOSTER, escrowFactory.address, balancerVault.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  await waura.deployed();

  // Deploy CRV spell
  const AuraSpell = await ethers.getContractFactory(CONTRACT_NAMES.AuraSpell);
  auraSpell = <AuraSpell>(
    await upgrades.deployProxy(
      AuraSpell,
      [bank.address, werc20.address, WETH, waura.address, AUGUSTUS_SWAPPER, TOKEN_TRANSFER_PROXY, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );
  await auraSpell.deployed();

  const auraBooster = <IAuraBooster>await ethers.getContractAt('IAuraBooster', ADDRESS.AURA_BOOSTER);

  // await curveSpell.setSwapRouter(ADDRESS.SUSHI_ROUTER);
  await auraSpell.addStrategy(ADDRESS.BAL_UDU, utils.parseUnits('100', 18), utils.parseUnits('2000', 18));
  await auraSpell.addStrategy(ADDRESS.BAL_AURA_STABLE, utils.parseUnits('100', 18), utils.parseUnits('2000', 18));
  await auraSpell.setCollateralsMaxLTVs(0, [USDC, CRV, DAI], [30000, 30000, 30000]);
  await auraSpell.setCollateralsMaxLTVs(1, [USDC, CRV, DAI], [30000, 30000, 30000]);

  // Setup Bank
  await bank.whitelistSpells([auraSpell.address], [true]);
  await bank.whitelistTokens([USDC, DAI, CRV], [true, true, true]);
  await bank.whitelistERC1155([werc20.address, waura.address], true);
  console.log('Bank address:', bank.address);
  const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
  hardVault = <HardVault>await upgrades.deployProxy(HardVault, [config.address, admin.address], {
    unsafeAllow: ['delegatecall'],
  });

  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
  usdcSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bUSDC.address, 'Interest Bearing USDC', 'ibUSDC', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await usdcSoftVault.deployed();
  await bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 9000);
  await bTokenAdmin._setSoftVault(bUSDC.address, usdcSoftVault.address);

  daiSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bDAI.address, 'Interest Bearing DAI', 'ibDAI', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await daiSoftVault.deployed();
  await bank.addBank(DAI, daiSoftVault.address, hardVault.address, 8500);
  await bTokenAdmin._setSoftVault(bDAI.address, daiSoftVault.address);

  crvSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bCRV.address, 'Interest Bearing CRV', 'ibCRV', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await crvSoftVault.deployed();
  await bank.addBank(CRV, crvSoftVault.address, hardVault.address, 9000);
  await bTokenAdmin._setSoftVault(bCRV.address, crvSoftVault.address);

  // Whitelist bank contract on compound
  await comptroller._setCreditLimit(bank.address, bUSDC.address, utils.parseUnits('3000000'));
  await comptroller._setCreditLimit(bank.address, bCRV.address, utils.parseUnits('3000000'));
  await comptroller._setCreditLimit(bank.address, bDAI.address, utils.parseUnits('3000000'));

  await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
  await usdc.transfer(alice.address, utils.parseUnits('500', 6));
  await usdcSoftVault.deposit(utils.parseUnits('5000', 6));

  await crv.approve(crvSoftVault.address, ethers.constants.MaxUint256);
  await crv.transfer(alice.address, utils.parseUnits('500', 18));
  await crvSoftVault.deposit(utils.parseUnits('5000', 18));

  await dai.approve(daiSoftVault.address, ethers.constants.MaxUint256);
  await dai.transfer(alice.address, utils.parseUnits('500', 18));
  await daiSoftVault.deposit(utils.parseUnits('5000', 18));

  console.log('CRV Balance:', utils.formatEther(await crv.balanceOf(admin.address)));
  console.log('USDC Balance:', utils.formatUnits(await usdc.balanceOf(admin.address), 6));
  console.log('DAI Balance:', utils.formatEther(await dai.balanceOf(admin.address)));

  return {
    werc20,
    waura,
    mockOracle,
    stableOracle,
    volatileOracle,
    tricryptoOracle,
    oracle,
    config,
    feeManager,
    bank,
    auraSpell,
    auraBooster,
    usdcSoftVault,
    crvSoftVault,
    daiSoftVault,
    hardVault,
    uniV3Lib: LibInstance,
    bUSDC,
    bICHI,
    bCRV,
    bDAI,
    bMIM,
    bLINK,
    // bSUSHI,
    bBAL,
    //bALCX,
    bWETH,
    bWBTC,
  };
};
