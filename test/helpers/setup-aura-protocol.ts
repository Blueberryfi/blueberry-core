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
  StableBPTOracle,
  WAuraBooster,
  AuraSpell,
  Comptroller,
  PoolEscrow,
  PoolEscrowFactory,
  IAuraBooster,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { deployBTokens } from './money-market';
import { deploySoftVaults } from './markets';
import { faucetToken } from './paraswap';

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
const WSTETH = ADDRESS.wstETH;
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
  feeManager: FeeManager;
  uniV3Lib: UniV3WrappedLib;
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

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
  dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
  crv = <ERC20>await ethers.getContractAt('ERC20', CRV);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
  console.log('Deployed WETH');
  // Prepare USDC
  // deposit 1000 eth -> 1000 WETH
  await weth.deposit({ value: utils.parseUnits('1000') });

  // swap 40 WETH -> USDC, 40 WETH -> DAI
  await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
  const uniV2Router = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('100'),
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('100'),
    0,
    [WETH, DAI],
    admin.address,
    ethers.constants.MaxUint256
  );
  
  await faucetToken(CRV, utils.parseUnits('100000'), admin, 100);
  await faucetToken(USDC, utils.parseUnits('100000'), admin, 100);
  await faucetToken(DAI, utils.parseUnits('100000'), admin, 100);
  await faucetToken(WSTETH, utils.parseUnits('100000'), admin, 100);
  await faucetToken(WETH, utils.parseUnits('100000'), admin, 100);

  // Swap 40 weth -> crv
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  const sushiRouter = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.SUSHI_ROUTER)
  );
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('100'),
    0,
    [WETH, CRV],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Try to swap some crv to usdc -> Swap router test
  await crv.approve(ADDRESS.SUSHI_ROUTER, 0);
  await crv.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('100'),
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
    [WETH, WSTETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
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
  console.log('Price Set');
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
    [WETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU, WSTETH],
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
    ]
  );

  const StableBPTOracle = await ethers.getContractFactory(CONTRACT_NAMES.StableBPTOracle);

  const stableBptOracle = <StableBPTOracle>(
    await upgrades.deployProxy(
      StableBPTOracle,
      [ADDRESS.BALANCER_VAULT, oracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    )
  );

  stableBptOracle.registerBpt(ADDRESS.BAL_WSTETH_WETH);

  oracle.setRoutes([ADDRESS.BAL_WSTETH_WETH], [stableBptOracle.address]);
  
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

  await auraSpell.addStrategy(ADDRESS.BAL_UDU, utils.parseUnits('10', 18), utils.parseUnits('20000', 18));
  await auraSpell.addStrategy(ADDRESS.BAL_AURA_STABLE, utils.parseUnits('10', 18), utils.parseUnits('20000', 18));
  await auraSpell.addStrategy(ADDRESS.BAL_WSTETH_WETH, utils.parseUnits('10', 18), utils.parseUnits('20000', 18));
  await auraSpell.setCollateralsMaxLTVs(0, [USDC, CRV, DAI], [30000, 30000, 30000]);
  await auraSpell.setCollateralsMaxLTVs(1, [USDC, CRV, DAI], [30000, 30000, 30000]);
  await auraSpell.setCollateralsMaxLTVs(2, [USDC, CRV, DAI], [30000, 30000, 30000]);

  // Setup Bank
  await bank.whitelistSpells([auraSpell.address], [true]);
  await bank.whitelistTokens([USDC, DAI, CRV, WSTETH], [true, true, true, true]);
  await bank.whitelistERC1155([werc20.address, waura.address], true);

  await deploySoftVaults(config, bank, comptroller, bTokens.bTokens, admin, alice);
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
    uniV3Lib: LibInstance,
  };
};
