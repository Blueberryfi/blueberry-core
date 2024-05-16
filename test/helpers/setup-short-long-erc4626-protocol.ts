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
  softVaultOracle: SoftVaultOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueberryBank;
  shortLongSpell: ShortLongSpell;
  usdcSoftVault: SoftVault;
  crvSoftVault: SoftVault;
  hardVault: HardVault;
  feeManager: FeeManager;
  bUSDC: Contract;
  bCRV: Contract;
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
  let softVaultOracle: SoftVaultOracle;
  let WERC4626Oracle: ERC4626Oracle; //TODO: create a derived contract for this called HardVaultOracle that extends ERC4626Oracle
  let oracle: CoreOracle;
  let shortLongSpell_ERC4626: ShortLongSpell_ERC4626;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueberryBank;
  let usdcSoftVault: SoftVault;
  let crvSoftVault: SoftVault;
  let hardVault: HardVault;

  let comptroller: Comptroller;
  let bUSDC: Contract;
  let bCRV: Contract;
  let bWstETH: Contract;
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
  bCRV = bTokens.bCRV;
  bWstETH = bTokens.bWstETH;

  // Deploy Bank
  const Config = await ethers.getContractFactory('ProtocolConfig');
  config = <ProtocolConfig>await upgrades.deployProxy(Config, [treasury.address, admin.address], {
    unsafeAllow: ['delegatecall'],
  });
  await config.deployed();

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

  crvSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bCRV.address, 'Interest Bearing CRV', 'ibCRV', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await crvSoftVault.deployed();

  await softVaultOracle.registerSoftVault(crvSoftVault.address);
  await softVaultOracle.registerSoftVault(usdcSoftVault.address);

  await WERC4626Oracle.registerToken(apxETH.address);

  await oracle.setRoutes(
    [crvSoftVault.address, usdcSoftVault.address, wApxEth.address],
    [softVaultOracle.address, softVaultOracle.address, WERC4626Oracle.address]
  );

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
  await bank.addBank(CRV, crvSoftVault.address, hardVault.address, 9000);

  // Whitelist bank contract on compound
  await comptroller._setCreditLimit(bank.address, bUSDC.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bCRV.address, CREDIT_LIMIT);
  await comptroller._setCreditLimit(bank.address, bWstETH.address, CREDIT_LIMIT);

  await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
  await usdc.transfer(alice.address, utils.parseUnits(strategyDepositInUsd, 6));
  await usdcSoftVault.deposit(utils.parseUnits(vaultLiquidityInUsd, 6));

  await crv.approve(crvSoftVault.address, ethers.constants.MaxUint256);
  await crv.transfer(alice.address, utils.parseUnits(strategyDepositInUsd, 18));
  await crvSoftVault.deposit(utils.parseUnits(vaultLiquidityInUsd, 18));

  console.log('CRV Balance:', utils.formatEther(await crv.balanceOf(admin.address)));
  console.log('USDC Balance:', utils.formatUnits(await usdc.balanceOf(admin.address), 6));
  console.log('DAI Balance:', utils.formatEther(await dai.balanceOf(admin.address)));

  return {
    werc20,
    mockOracle,
    softVaultOracle,
    oracle,
    config,
    feeManager,
    bank,
    shortLongSpell: shortLongSpell_ERC4626,
    usdcSoftVault,
    crvSoftVault,
    hardVault,
    bUSDC,
    bCRV,
    wApxEth,
  };
};
