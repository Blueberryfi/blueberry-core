import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, utils, Contract } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
  BlueberryBank,
  CoreOracle,
  IchiSpell,
  IWETH,
  MockOracle,
  SoftVault,
  IchiVaultOracle,
  WERC20,
  WIchiFarm,
  ProtocolConfig,
  MockIchiVault,
  MockIchiFarm,
  ERC20,
  IUniswapV2Router02,
  MockIchiV2,
  HardVault,
  FeeManager,
  UniV3WrappedLib,
  Comptroller,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { deployBTokens } from './money-market';

/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable prefer-const */
const WETH = ADDRESS.WETH;
const wstETH = ADDRESS.wstETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const UNI_V3_ROUTER = ADDRESS.UNI_V3_ROUTER;
const ETH_PRICE = 1600;

export interface Protocol {
  ichi_USDC_ICHI_Vault: MockIchiVault;
  ichi_USDC_DAI_Vault: MockIchiVault;
  ichiFarm: MockIchiFarm;
  werc20: WERC20;
  wichi: WIchiFarm;
  mockOracle: MockOracle;
  ichiOracle: IchiVaultOracle;
  oracle: CoreOracle;
  config: ProtocolConfig;
  bank: BlueberryBank;
  ichiSpell: IchiSpell;
  usdcSoftVault: SoftVault;
  ichiSoftVault: SoftVault;
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
  // bSUSHI: Contract;
  bBAL: Contract;
  //bALCX: Contract,
  bWETH: Contract;
  bWBTC: Contract;
}

export const setupIchiProtocol = async (): Promise<Protocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let dai: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let wichi: WIchiFarm;
  let mockOracle: MockOracle;
  let ichiOracle: IchiVaultOracle;
  let oracle: CoreOracle;
  let ichiSpell: IchiSpell;

  let config: ProtocolConfig;
  let feeManager: FeeManager;
  let bank: BlueberryBank;
  let usdcSoftVault: SoftVault;
  let ichiSoftVault: SoftVault;
  let daiSoftVault: SoftVault;
  let wethSoftVault: SoftVault;
  let hardVault: HardVault;
  let ichiFarm: MockIchiFarm;
  let ichi_USDC_ICHI_Vault: MockIchiVault;
  let ichi_USDC_DAI_Vault: MockIchiVault;

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
  let bTokenAdmin: Contract;

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
  dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
  ichi = <MockIchiV2>await ethers.getContractAt('MockIchiV2', ICHI);
  ichiV1 = <ERC20>await ethers.getContractAt('ERC20', ICHIV1);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

  // Prepare USDC
  // deposit 100 eth -> 100 WETH
  await weth.deposit({ value: utils.parseUnits('100') });

  // swap 30 WETH -> USDC, 30 WETH -> DAI
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
  // Swap 40 weth -> ichi
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  const sushiRouter = <IUniswapV2Router02>(
    await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.SUSHI_ROUTER)
  );
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('40'),
    0,
    [WETH, ICHIV1],
    admin.address,
    ethers.constants.MaxUint256
  );
  await ichiV1.approve(ICHI, ethers.constants.MaxUint256);
  const ichiV1Balance = await ichiV1.balanceOf(admin.address);
  await ichi.convertToV2(ichiV1Balance.div(2));

  const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
  const LibInstance = await LinkedLibFactory.deploy();

  const IchiVault = await ethers.getContractFactory('MockIchiVault', {
    libraries: {
      UniV3WrappedLibContainer: LibInstance.address,
    },
  });
  ichi_USDC_ICHI_Vault = <MockIchiVault>(
    await IchiVault.deploy(ADDRESS.UNI_V3_ICHI_USDC, true, true, admin.address, admin.address, 3600)
  );
  await usdc.approve(ichi_USDC_ICHI_Vault.address, utils.parseUnits('1000', 6));
  await ichi.approve(ichi_USDC_ICHI_Vault.address, utils.parseUnits('1000', 18));
  await ichi_USDC_ICHI_Vault.deposit(utils.parseUnits('1000', 18), utils.parseUnits('1000', 6), admin.address);

  ichi_USDC_DAI_Vault = <MockIchiVault>(
    await IchiVault.deploy(ADDRESS.UNI_V3_USDC_DAI, true, true, admin.address, admin.address, 3600)
  );

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [WETH, USDC, ICHI, DAI, wstETH],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18).mul(5), // $5
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
    ]
  );

  const IchiVaultOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultOracle, {
    libraries: {
      UniV3WrappedLibContainer: LibInstance.address,
    },
  });
  ichiOracle = <IchiVaultOracle>await upgrades.deployProxy(IchiVaultOracle, [mockOracle.address, admin.address], {
    unsafeAllow: ['delegatecall', 'external-library-linking'],
  });

  await ichiOracle.deployed();
  await ichiOracle.setPriceDeviation(ICHI, 500);
  await ichiOracle.setPriceDeviation(USDC, 500);
  await ichiOracle.setPriceDeviation(DAI, 500);
  await ichiOracle.setPriceDeviation(wstETH, 500);

  await ichiOracle.registerVault(ichi_USDC_ICHI_Vault.address);
  await ichiOracle.registerVault(ichi_USDC_DAI_Vault.address);

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });
  await oracle.deployed();

  await oracle.setRoutes(
    [WETH, USDC, ICHI, DAI, wstETH, ichi_USDC_ICHI_Vault.address, ichi_USDC_DAI_Vault.address],
    [
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      mockOracle.address,
      ichiOracle.address,
      ichiOracle.address,
    ]
  );

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

  // Deploy ICHI wrapper
  const MockIchiFarm = await ethers.getContractFactory('MockIchiFarm');
  ichiFarm = <MockIchiFarm>await MockIchiFarm.deploy(
    ADDRESS.ICHI_FARM,
    ethers.utils.parseUnits('1', 9) // 1 ICHI.FARM per block
  );
  // Add new ichi vault to farming pool
  await ichiFarm.add(100, ichi_USDC_ICHI_Vault.address);
  await ichiFarm.add(100, ichi_USDC_DAI_Vault.address);
  await ichiFarm.add(100, admin.address); // fake pool

  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  werc20 = <WERC20>await upgrades.deployProxy(WERC20, [admin.address], { unsafeAllow: ['delegatecall'] });
  await werc20.deployed();

  const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
  wichi = <WIchiFarm>await upgrades.deployProxy(
    WIchiFarm,
    [ADDRESS.ICHI, ADDRESS.ICHI_FARM, ichiFarm.address, admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await wichi.deployed();

  // Deploy ICHI spell
  const IchiSpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiSpell);
  ichiSpell = <IchiSpell>(
    await upgrades.deployProxy(
      IchiSpell,
      [
        bank.address,
        werc20.address,
        WETH,
        wichi.address,
        UNI_V3_ROUTER,
        ADDRESS.AUGUSTUS_SWAPPER,
        ADDRESS.TOKEN_TRANSFER_PROXY,
        admin.address,
      ],
      { unsafeAllow: ['delegatecall'] }
    )
  );
  await ichiSpell.deployed();
  await ichiSpell.addStrategy(ichi_USDC_ICHI_Vault.address, utils.parseUnits('10', 18), utils.parseUnits('2000', 18));
  await ichiSpell.addStrategy(ichi_USDC_DAI_Vault.address, utils.parseUnits('10', 18), utils.parseUnits('2000', 18));
  await ichiSpell.setCollateralsMaxLTVs(0, [USDC, ICHI, DAI, wstETH, WETH], [30000, 30000, 30000, 30000, 30000]);
  await ichiSpell.setCollateralsMaxLTVs(1, [USDC, ICHI, DAI, wstETH, WETH], [30000, 30000, 30000, 30000, 30000]);

  // Setup Bank
  await bank.whitelistSpells([ichiSpell.address], [true]);
  await bank.whitelistTokens([USDC, ICHI, DAI, wstETH, WETH], [true, true, true, true, true]);
  await bank.whitelistERC1155([werc20.address, wichi.address], true);

  const bTokens = await deployBTokens(admin.address);
  comptroller = bTokens.comptroller;
  bUSDC = bTokens.bUSDC;
  bICHI = bTokens.bICHI;
  bCRV = bTokens.bCRV;
  bDAI = bTokens.bDAI;
  bMIM = bTokens.bMIM;
  bLINK = bTokens.bLINK;
  bOHM = bTokens.bOHM;
  // bSUSHI = bTokens.bSUSHI;
  bBAL = bTokens.bBAL;
  //bALCX = bTokens.bALCX;
  bWETH = bTokens.bWETH;
  bWBTC = bTokens.bWBTC;
  bTokenAdmin = bTokens.bTokenAdmin;

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

  ichiSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bICHI.address, 'Interest Bearing ICHI', 'ibICHI', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await ichiSoftVault.deployed();
  await bank.addBank(ICHI, ichiSoftVault.address, hardVault.address, 9000);
  await bTokenAdmin._setSoftVault(bICHI.address, ichiSoftVault.address);

  wethSoftVault = <SoftVault>await upgrades.deployProxy(
    SoftVault,
    [config.address, bWETH.address, 'Interest Bearing WETH', 'ibWETH', admin.address],
    {
      unsafeAllow: ['delegatecall'],
    }
  );
  await wethSoftVault.deployed();

  // Whitelist bank contract on compound
  await comptroller._setCreditLimit(bank.address, bUSDC.address, utils.parseUnits('3000000'));
  await comptroller._setCreditLimit(bank.address, bICHI.address, utils.parseUnits('3000000'));
  await comptroller._setCreditLimit(bank.address, bDAI.address, utils.parseUnits('3000000'));
  await comptroller._setCreditLimit(bank.address, bWETH.address, utils.parseUnits('3000000'));

  await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
  await usdc.transfer(alice.address, utils.parseUnits('500', 6));
  await usdcSoftVault.deposit(utils.parseUnits('5000', 6));

  await ichi.approve(ichiSoftVault.address, ethers.constants.MaxUint256);
  await ichi.transfer(alice.address, utils.parseUnits('500', 18));
  await ichiSoftVault.deposit(utils.parseUnits('5000', 18));

  await dai.approve(daiSoftVault.address, ethers.constants.MaxUint256);
  await dai.transfer(alice.address, utils.parseUnits('500', 18));
  await daiSoftVault.deposit(utils.parseUnits('5000', 18));

  console.log('ICHI Balance:', utils.formatEther(await ichi.balanceOf(admin.address)));
  console.log('USDC Balance:', utils.formatUnits(await usdc.balanceOf(admin.address), 6));
  console.log('DAI Balance:', utils.formatEther(await dai.balanceOf(admin.address)));

  return {
    ichi_USDC_ICHI_Vault,
    ichi_USDC_DAI_Vault,
    ichiFarm,
    werc20,
    wichi,
    mockOracle,
    ichiOracle,
    oracle,
    config,
    feeManager,
    bank,
    ichiSpell,
    usdcSoftVault,
    ichiSoftVault,
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
    // bSUSHI,
    bBAL,
    //bALCX,
    bWETH,
    bWBTC,
  };
};
