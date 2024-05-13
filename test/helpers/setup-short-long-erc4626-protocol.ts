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
  ERC4626Oracle,
  ERC4626,
  ShortLongSpell_ERC4626,
  WApxEth,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { deployBTokens } from './money-market';
import { impersonateAccount } from '.';

/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable prefer-const */

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const WBTC = ADDRESS.WBTC;
const WETH = ADDRESS.WETH;
const WstETH = ADDRESS.wstETH;
const ApxETH = ADDRESS.apxETH;
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

export interface ShortLongERC4626Protocol {
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
  usdcSoftVault: SoftVault;
  crvSoftVault: SoftVault;
  daiSoftVault: SoftVault;
  linkSoftVault: SoftVault;
  wbtcSoftVault: SoftVault;
  wstETHSoftVault: SoftVault;
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
  //bALCX: Contract;
  bWETH: Contract;
  bWBTC: Contract;
  wApxEth: Contract;
}

export const setupShortLongERC4626Protocol = async (): Promise<ShortLongERC4626Protocol> => {
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
  let WERC4626Oracle: ERC4626Oracle; //TODO: create a derived contract for this called HardVaultOracle that extends ERC4626Oracle
  let oracle: CoreOracle;
  let shortLongSpell_ERC4626: ShortLongSpell_ERC4626;

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
  let bApxETH: Contract;
  let wApxEth: WApxEth;

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

  const WApxEth = await ethers.getContractFactory('WApxEth');
  wApxEth = <WApxEth>await upgrades.deployProxy(WApxEth, [ADDRESS.apxETH, admin.address], {
    unsafeAllow: ['delegatecall'],
  });
  await wApxEth.deployed();
  console.log('WApxEth: ', wApxEth.address);

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
  const apxETHWhale = '0x41dda7bE30130cEbd867f439a759b9e7Ab2569e9';

  await admin.sendTransaction({
    to: wstETHWhale,
    value: utils.parseEther('10'),
  });

  await impersonateAccount(wstETHWhale);
  const whale1 = await ethers.getSigner(wstETHWhale);
  const wstETH = <ERC20>await ethers.getContractAt('ERC20', WstETH);
  await wstETH.connect(whale1).transfer(admin.address, utils.parseUnits('30'));

  await impersonateAccount(apxETHWhale);
  const whale2 = await ethers.getSigner(apxETHWhale);
  const apxETH = <ERC4626>await ethers.getContractAt('ERC4626', ApxETH);
  await apxETH.connect(whale2).transfer(admin.address, utils.parseUnits('100'));

  const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
  const LibInstance = await LinkedLibFactory.deploy();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [WETH, WBTC, LINK, WstETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU, ApxETH, ADDRESS.pxETH],
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
      BigNumber.from(10).pow(18), // $1,
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
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

  const HardVaultOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.ERC4626Oracle);
  WERC4626Oracle = <ERC4626Oracle>await upgrades.deployProxy(
    HardVaultOracleFactory,
    [mockOracle.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );

  await WERC4626Oracle.deployed();

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
  await oracle.deployed();

  await oracle.setRoutes(
    [WETH, WBTC, LINK, WstETH, USDC, CRV, DAI, USDT, FRAX, AURA, BAL, ADDRESS.BAL_UDU, ApxETH],
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
      mockOracle.address,
    ]
  );

  const bTokens = await deployBTokens(admin.address, oracle.address);
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
  //bALCX = bTokens.bALCX;
  bWETH = bTokens.bWETH;
  bWBTC = bTokens.bWBTC;
  bWstETH = bTokens.bWstETH;
  bApxETH = bTokens.bApxETH;

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
  const ShortLongSpell_ERC4626 = await ethers.getContractFactory(CONTRACT_NAMES.ShortLongSpell_ERC4626);
  shortLongSpell_ERC4626 = <ShortLongSpell_ERC4626>(
    await upgrades.deployProxy(
      ShortLongSpell_ERC4626,
      [bank.address, wApxEth.address, WETH, AUGUSTUS_SWAPPER, TOKEN_TRANSFER_PROXY, admin.address],
      { unsafeAllow: ['delegatecall'] }
    )
  );
  await shortLongSpell_ERC4626.deployed();
  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);

  usdcSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bUSDC.address, 'Interest Bearing USDC', 'ibUSDC', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await usdcSoftVault.deployed();

  daiSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bDAI.address, 'Interest Bearing DAI', 'ibDAI', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await daiSoftVault.deployed();

  crvSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bCRV.address, 'Interest Bearing CRV', 'ibCRV', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await crvSoftVault.deployed();

  linkSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bLINK.address, 'Interest Bearing LINK', 'ibLINK', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await linkSoftVault.deployed();

  wbtcSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bWBTC.address, 'Interest Bearing WBTC', 'ibWBTC', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await wbtcSoftVault.deployed();

  wethSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bWETH.address, 'Interest Bearing WETH', 'ibWETH', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await wethSoftVault.deployed();

  wstETHSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bWstETH.address, 'Interest Bearing WstETH', 'ibWstETH', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await wstETHSoftVault.deployed();

  await softVaultOracle.registerSoftVault(daiSoftVault.address);
  await softVaultOracle.registerSoftVault(wbtcSoftVault.address);
  await softVaultOracle.registerSoftVault(wethSoftVault.address);
  await softVaultOracle.registerSoftVault(wstETHSoftVault.address);
  await softVaultOracle.registerSoftVault(linkSoftVault.address);
  await softVaultOracle.registerSoftVault(crvSoftVault.address);
  await softVaultOracle.registerSoftVault(usdcSoftVault.address);

  // await WERC4626Oracle.registerToken(wApxEth.getApxETH());
  await WERC4626Oracle.registerToken(apxETH.address);

  await oracle.setRoutes(
    [
      daiSoftVault.address,
      wbtcSoftVault.address,
      linkSoftVault.address,
      wstETHSoftVault.address,
      crvSoftVault.address,
      usdcSoftVault.address,
      wethSoftVault.address,
      wApxEth.address,
    ],
    [
      softVaultOracle.address,
      softVaultOracle.address,
      softVaultOracle.address,
      softVaultOracle.address,
      softVaultOracle.address,
      softVaultOracle.address,
      softVaultOracle.address,
      WERC4626Oracle.address,
    ]
  );

  // await shortLongSpell.addStrategy(daiSoftVault.address, MIN_POS_SIZE, MAX_POS_SIZE);
  //
  // await shortLongSpell.setCollateralsMaxLTVs(0, [USDC, USDT, DAI], [MAX_LTV, MAX_LTV, MAX_LTV]);
  //
  // await shortLongSpell.addStrategy(linkSoftVault.address, MIN_POS_SIZE, MAX_POS_SIZE);
  // await shortLongSpell.setCollateralsMaxLTVs(1, [WBTC, DAI, WETH], [MAX_LTV, MAX_LTV, MAX_LTV]);
  // await shortLongSpell.addStrategy(daiSoftVault.address, MIN_POS_SIZE, MAX_POS_SIZE);
  // await shortLongSpell.setCollateralsMaxLTVs(2, [WBTC, DAI, WETH, WstETH], [MAX_LTV, MAX_LTV, MAX_LTV, MAX_LTV]);
  //
  // await shortLongSpell.addStrategy(wbtcSoftVault.address, MIN_POS_SIZE, MAX_POS_SIZE);
  // await shortLongSpell.setCollateralsMaxLTVs(3, [WBTC, DAI, WETH], [MAX_LTV, MAX_LTV, MAX_LTV]);
  // await shortLongSpell.addStrategy(wstETHSoftVault.address, MIN_POS_SIZE, MAX_POS_SIZE);
  // await shortLongSpell.setCollateralsMaxLTVs(4, [WBTC, DAI, WETH, WstETH], [MAX_LTV, MAX_LTV, MAX_LTV, MAX_LTV]);

  console.log('wrapped apx: ', wApxEth.address);
  await shortLongSpell_ERC4626.addStrategy(wApxEth.address, MIN_POS_SIZE, MAX_POS_SIZE);
  await shortLongSpell_ERC4626.setCollateralsMaxLTVs(
    0,
    [DAI, WETH, USDC, WstETH, ApxETH],
    [MAX_LTV, MAX_LTV, MAX_LTV, MAX_LTV, MAX_LTV]
  );

  // Setup Bank
  await bank.whitelistSpells([shortLongSpell_ERC4626.address], [true]);
  await bank.whitelistTokens(
    [USDC, USDT, DAI, CRV, WETH, WBTC, LINK, WstETH, ApxETH],
    [true, true, true, true, true, true, true, true, true]
  );
  await bank.whitelistERC1155([werc20.address, wApxEth.address], true);

  const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
  hardVault = <HardVault>await upgrades.deployProxy(HardVault, [config.address, admin.address], {
    unsafeAllow: ['delegatecall'],
  });

  await bank.addBank(USDC, usdcSoftVault.address, hardVault.address, 9000);
  await bank.addBank(DAI, daiSoftVault.address, hardVault.address, 8500);
  await bank.addBank(CRV, crvSoftVault.address, hardVault.address, 9000);
  await bank.addBank(LINK, linkSoftVault.address, hardVault.address, 9000);
  await bank.addBank(WBTC, wbtcSoftVault.address, hardVault.address, 9000);
  await bank.addBank(WETH, wethSoftVault.address, hardVault.address, 9000);
  await bank.addBank(WstETH, wstETHSoftVault.address, hardVault.address, 9000);

  // Whitelist bank contract on compound
  await comptroller._setCreditLimit(bank.address, bUSDC.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bCRV.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bDAI.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bLINK.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bWBTC.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bWstETH.address, CREDIT_LIMIT);

  await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
  await usdc.transfer(alice.address, utils.parseUnits(strategyDepositInUsd, 6));
  await usdcSoftVault.deposit(utils.parseUnits(vaultLiquidityInUsd, 6));

  await crv.approve(crvSoftVault.address, ethers.constants.MaxUint256);
  await crv.transfer(alice.address, utils.parseUnits(strategyDepositInUsd, 18));
  await crvSoftVault.deposit(utils.parseUnits(vaultLiquidityInUsd, 18));

  await dai.approve(daiSoftVault.address, ethers.constants.MaxUint256);
  await dai.transfer(alice.address, utils.parseUnits(strategyDepositInUsd, 18));
  await daiSoftVault.deposit(utils.parseUnits(vaultLiquidityInUsd, 18));

  const linkDeposit = (parseInt(strategyDepositInUsd) / LINK_PRICE).toFixed(18).toString();
  await link.approve(linkSoftVault.address, ethers.constants.MaxUint256);
  await linkSoftVault.deposit(utils.parseUnits(linkDeposit, 18));

  const wbtcDeposit = (parseInt(strategyDepositInUsd) / BTC_PRICE).toFixed(8).toString();
  await wbtc.approve(wbtcSoftVault.address, ethers.constants.MaxUint256);
  await wbtcSoftVault.deposit(utils.parseUnits(wbtcDeposit, 8));

  const wstETHDeposit = (parseInt(strategyDepositInUsd) / ETH_PRICE).toFixed(18).toString();
  console.log('wstETH Deposit:', wstETHDeposit);
  await wstETH.approve(wstETHSoftVault.address, ethers.constants.MaxUint256);
  await wstETHSoftVault.deposit(utils.parseUnits(wstETHDeposit, 18));

  console.log('CRV Balance:', utils.formatEther(await crv.balanceOf(admin.address)));
  console.log('USDC Balance:', utils.formatUnits(await usdc.balanceOf(admin.address), 6));
  console.log('DAI Balance:', utils.formatEther(await dai.balanceOf(admin.address)));

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
    shortLongSpell: shortLongSpell_ERC4626,
    usdcSoftVault,
    crvSoftVault,
    daiSoftVault,
    linkSoftVault,
    wbtcSoftVault,
    wstETHSoftVault,
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
    //bALCX,
    bWETH,
    bWBTC,
    wApxEth,
  };
};
