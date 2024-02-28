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
  SoftVaultOracle,
  ShortLongSpell,
  Comptroller,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { deployBTokens } from './money-market';
import { impersonateAccount } from '.';
import { deploySoftVaults } from './markets';
import { faucetToken } from './paraswap';

/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable prefer-const */

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const WBTC = ADDRESS.WBTC;
const WETH = ADDRESS.WETH;
const WstETH = ADDRESS.wstETH;
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

const MIN_POS_SIZE = utils.parseUnits('20', 18); // 20 USD
const MAX_POS_SIZE = utils.parseUnits('2000000', 18); // 2000000 USD
const MAX_LTV = 300000; // 300,000 USD
const CREDIT_LIMIT = utils.parseUnits('3000000000'); // 300M USD

export interface ShortLongProtocol {
  werc20: WERC20;
  mockOracle: MockOracle;
  stableOracle: CurveStableOracle;
  volatileOracle: CurveVolatileOracle;
  tricryptoOracle: CurveTricryptoOracle;
  softVaultOracle: SoftVaultOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueberryBank;
  shortLongSpell: ShortLongSpell;
  feeManager: FeeManager;
  uniV3Lib: UniV3WrappedLib;
}

export const setupShortLongProtocol = async (): Promise<ShortLongProtocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let crv: ERC20;
  let link: ERC20;
  let wbtc: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let mockOracle: MockOracle;
  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let softVaultOracle: SoftVaultOracle;
  let oracle: CoreOracle;
  let shortLongSpell: ShortLongSpell;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueberryBank;
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let daiSoftVault: SoftVault;
  let linkSoftVault: SoftVault;
  let wbtcSoftVault: SoftVault;
  let wethSoftVault: SoftVault;
  let wstETHSoftVault: SoftVault;
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
  //let bALCX: Contract;
  let bWETH: Contract;
  let bWBTC: Contract;
  let bWstETH: Contract;

  const initialDeposit = utils.parseUnits('200');
  const initialSwapAmount = utils.parseUnits('10');

  const strategyDepositInUsd = '1000';
  const vaultLiquidityInUsd = '5000';

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
  dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
  crv = <ERC20>await ethers.getContractAt('ERC20', CRV);
  link = <ERC20>await ethers.getContractAt('ERC20', LINK);
  wbtc = <ERC20>await ethers.getContractAt('ERC20', WBTC);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
  // Prepare USDC
  // deposit 200 eth -> 200 WETH
  await weth.deposit({ value: initialDeposit });

  // swap 40 WETH -> USDC, 40 WETH -> DAI
  await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);

  const uniV2Router = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
  );

  // WETH -> USDC
  await uniV2Router.swapExactTokensForTokens(
    initialSwapAmount,
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  );
  // WETH -> DAI
  await uniV2Router.swapExactTokensForTokens(
    initialSwapAmount,
    0,
    [WETH, DAI],
    admin.address,
    ethers.constants.MaxUint256
  );
  // WETH -> LINK
  await uniV2Router.swapExactTokensForTokens(
    initialSwapAmount,
    0,
    [WETH, LINK],
    admin.address,
    ethers.constants.MaxUint256
  );
  // WETH -> WBTC
  await uniV2Router.swapExactTokensForTokens(
    initialSwapAmount,
    0,
    [WETH, WBTC],
    admin.address,
    ethers.constants.MaxUint256
  );
  // Swap 40 weth -> crv
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);

  const sushiRouter = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.SUSHI_ROUTER)
  );
  // WETH -> CRV
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
  const wstETHWhale = '0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d';

  await admin.sendTransaction({
    to: wstETHWhale,
    value: utils.parseEther('10'),
  });
  
  await impersonateAccount(wstETHWhale);
  const whale1 = await ethers.getSigner(wstETHWhale);
  const wstETH = <ERC20>await ethers.getContractAt('ERC20', WstETH);

  await wstETH.connect(whale1).transfer(admin.address, utils.parseUnits('5000'));

  await faucetToken(CRV, utils.parseUnits('100000'), admin, 100);
  await faucetToken(USDC, utils.parseUnits('100000', 6), admin, 100);
  await faucetToken(DAI, utils.parseUnits('100000'), admin, 100);
  await faucetToken(WETH, utils.parseUnits('100000'), admin, 100);
  await faucetToken(WBTC, utils.parseUnits('100000', 8), admin, 100);
  await faucetToken(LINK, utils.parseUnits('100000'), admin, 100);

  const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
  const LibInstance = await LinkedLibFactory.deploy();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [WETH, WBTC, LINK, WstETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(BTC_PRICE),
      BigNumber.from(10).pow(18).mul(LINK_PRICE),
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

  const SoftVaultOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SoftVaultOracle);
  softVaultOracle = <SoftVaultOracle>await upgrades.deployProxy(
    SoftVaultOracleFactory,
    [mockOracle.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  await softVaultOracle.deployed();

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
  await oracle.deployed();

  await oracle.setRoutes(
    [WETH, WBTC, LINK, WstETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU],
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
    ]
  );

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

  // Deploy CRV spell
  const ShortLongSpell = await ethers.getContractFactory(CONTRACT_NAMES.ShortLongSpell);
  shortLongSpell = <ShortLongSpell>(
    await upgrades.deployProxy(
      ShortLongSpell,
      [bank.address, werc20.address, WETH, AUGUSTUS_SWAPPER, TOKEN_TRANSFER_PROXY, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );
  await shortLongSpell.deployed();
  // Setup Bank
  await bank.whitelistSpells([shortLongSpell.address], [true]);
  await bank.whitelistTokens(
    [USDC, USDT, DAI, CRV, WETH, WBTC, LINK, WstETH],
    [true, true, true, true, true, true, true, true]
  );
  await bank.whitelistERC1155([werc20.address], true);

  const softVaults: SoftVault[] = await deploySoftVaults(config, bank, comptroller, bTokens.bTokens, admin, alice);
  const strategyUnderlying = new Set([DAI, LINK, WBTC, WstETH]);

  for (let i = 0; i < softVaults.length; i++) {
    await softVaultOracle.registerSoftVault(softVaults[i].address);
    await oracle.setRoutes([softVaults[i].address], [softVaultOracle.address]);
    const underlyingToken = await softVaults[i].getUnderlyingToken();

    if (strategyUnderlying.has(underlyingToken)) {
      await shortLongSpell.addStrategy(softVaults[i].address, MIN_POS_SIZE, MAX_POS_SIZE);
    }
  }

  await shortLongSpell.setCollateralsMaxLTVs(0, [USDC, USDT, DAI], [MAX_LTV, MAX_LTV, MAX_LTV]);
  await shortLongSpell.setCollateralsMaxLTVs(1, [WBTC, DAI, WETH], [MAX_LTV, MAX_LTV, MAX_LTV]);
  await shortLongSpell.setCollateralsMaxLTVs(2, [WBTC, DAI, WETH, WstETH], [MAX_LTV, MAX_LTV, MAX_LTV, MAX_LTV]);
  await shortLongSpell.setCollateralsMaxLTVs(3, [WBTC, DAI, WETH], [MAX_LTV, MAX_LTV, MAX_LTV]);
  await shortLongSpell.setCollateralsMaxLTVs(4, [WBTC, DAI, WETH, WstETH], [MAX_LTV, MAX_LTV, MAX_LTV, MAX_LTV]);

  return {
    werc20,
    mockOracle,
    stableOracle,
    volatileOracle,
    tricryptoOracle,
    softVaultOracle,
    oracle,
    config,
    feeManager,
    bank,
    shortLongSpell,
    uniV3Lib: LibInstance,
  };
};
