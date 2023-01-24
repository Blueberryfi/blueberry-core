import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import {
  BlueBerryBank,
  CoreOracle,
  IchiVaultSpell,
  IWETH,
  MockOracle,
  SoftVault,
  IchiLpOracle,
  WERC20,
  WIchiFarm,
  ProtocolConfig,
  IComptroller,
  MockIchiVault,
  MockIchiFarm,
  ERC20,
  IUniswapV2Router02,
  MockIchiV2,
  HardVault
} from '../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../constant';

const CUSDC = ADDRESS.bUSDC;
const CICHI = ADDRESS.bICHI;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const ICHI = ADDRESS.ICHI;
const ICHIV1 = ADDRESS.ICHI_FARM;
const ICHI_VAULT_PID = 0; // ICHI/USDC Vault PoolId
const ETH_PRICE = 1600;

export interface Protocol {
  ichi_USDC_ICHI_Vault: MockIchiVault,
  ichiFarm: MockIchiFarm,
  werc20: WERC20,
  wichi: WIchiFarm,
  mockOracle: MockOracle,
  ichiOracle: IchiLpOracle,
  oracle: CoreOracle,
  config: ProtocolConfig,
  bank: BlueBerryBank,
  spell: IchiVaultSpell,
  usdcSoftVault: SoftVault,
  ichiSoftVault: SoftVault,
  hardVault: HardVault,
}

export const setupProtocol = async (): Promise<Protocol> => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let ichi: MockIchiV2;
  let ichiV1: ERC20;
  let weth: IWETH;
  let werc20: WERC20;
  let wichi: WIchiFarm;
  let mockOracle: MockOracle;
  let ichiOracle: IchiLpOracle;
  let oracle: CoreOracle;
  let spell: IchiVaultSpell;
  let config: ProtocolConfig;
  let bank: BlueBerryBank;
  let usdcSoftVault: SoftVault;
  let ichiSoftVault: SoftVault;
  let hardVault: HardVault;
  let ichiFarm: MockIchiFarm;
  let ichi_USDC_ICHI_Vault: MockIchiVault;

  [admin, alice, treasury] = await ethers.getSigners();
  usdc = <ERC20>await ethers.getContractAt("ERC20", USDC);
  ichi = <MockIchiV2>await ethers.getContractAt("MockIchiV2", ICHI);
  ichiV1 = <ERC20>await ethers.getContractAt("ERC20", ICHIV1);
  weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

  // Prepare USDC
  // deposit 80 eth -> 80 WETH
  await weth.deposit({ value: utils.parseUnits('80') });

  // swap 40 weth -> usdc
  await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);
  const uniV2Router = <IUniswapV2Router02>await ethers.getContractAt(
    CONTRACT_NAMES.IUniswapV2Router02,
    ADDRESS.UNI_V2_ROUTER
  );
  await uniV2Router.swapExactTokensForTokens(
    utils.parseUnits('40'),
    0,
    [WETH, USDC],
    admin.address,
    ethers.constants.MaxUint256
  )
  // Swap 40 weth -> ichi
  await weth.approve(ADDRESS.SUSHI_ROUTER, ethers.constants.MaxUint256);
  const sushiRouter = <IUniswapV2Router02>await ethers.getContractAt(
    CONTRACT_NAMES.IUniswapV2Router02,
    ADDRESS.SUSHI_ROUTER
  );
  await sushiRouter.swapExactTokensForTokens(
    utils.parseUnits('40'),
    0,
    [WETH, ICHIV1],
    admin.address,
    ethers.constants.MaxUint256
  )
  await ichiV1.approve(ICHI, ethers.constants.MaxUint256);
  const ichiV1Balance = await ichiV1.balanceOf(admin.address);
  await ichi.convertToV2(ichiV1Balance.div(2));
  console.log("ICHI Balance:", utils.formatEther(await ichi.balanceOf(admin.address)));

  const LinkedLibFactory = await ethers.getContractFactory("UniV3WrappedLib");
  const LibInstance = await LinkedLibFactory.deploy();

  const IchiVault = await ethers.getContractFactory("MockIchiVault", {
    libraries: {
      UniV3WrappedLibMockup: LibInstance.address
    }
  });
  ichi_USDC_ICHI_Vault = await IchiVault.deploy(
    ADDRESS.UNI_V3_ICHI_USDC,
    true,
    true,
    admin.address,
    admin.address,
    3600
  )
  await usdc.approve(ichi_USDC_ICHI_Vault.address, utils.parseUnits("100", 6));
  await ichi.approve(ichi_USDC_ICHI_Vault.address, utils.parseUnits("100", 18));
  await ichi_USDC_ICHI_Vault.deposit(utils.parseUnits("100", 18), utils.parseUnits("100", 6), admin.address)

  const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
  werc20 = <WERC20>await upgrades.deployProxy(WERC20);
  await werc20.deployed();

  const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
  mockOracle = <MockOracle>await MockOracle.deploy();
  await mockOracle.deployed();
  await mockOracle.setPrice(
    [WETH, USDC, ICHI],
    [
      BigNumber.from(10).pow(18).mul(ETH_PRICE),
      BigNumber.from(10).pow(18), // $1
      BigNumber.from(10).pow(18).mul(5), // $5
    ],
  )

  const IchiLpOracle = await ethers.getContractFactory(CONTRACT_NAMES.IchiLpOracle);
  ichiOracle = <IchiLpOracle>await IchiLpOracle.deploy(mockOracle.address);
  await ichiOracle.deployed();

  const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
  oracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);
  await oracle.deployed();

  await oracle.setWhitelistERC1155([werc20.address, ichi_USDC_ICHI_Vault.address], true);
  await oracle.setTokenSettings(
    [WETH, USDC, ICHI, ichi_USDC_ICHI_Vault.address],
    [{
      liqThreshold: 9000,
      route: mockOracle.address,
    }, {
      liqThreshold: 8000,
      route: mockOracle.address,
    }, {
      liqThreshold: 9000,
      route: mockOracle.address,
    }, {
      liqThreshold: 10000,
      route: ichiOracle.address,
    }]
  )

  // Deploy Bank
  const Config = await ethers.getContractFactory("ProtocolConfig");
  config = <ProtocolConfig>await upgrades.deployProxy(Config, [treasury.address]);
  // config.startVaultWithdrawFee();

  const BlueBerryBank = await ethers.getContractFactory(CONTRACT_NAMES.BlueBerryBank);
  bank = <BlueBerryBank>await upgrades.deployProxy(BlueBerryBank, [oracle.address, config.address]);
  await bank.deployed();

  // Deploy ICHI wrapper and spell
  const MockIchiFarm = await ethers.getContractFactory("MockIchiFarm");
  ichiFarm = <MockIchiFarm>await MockIchiFarm.deploy(
    ADDRESS.ICHI_FARM,
    ethers.utils.parseUnits("1", 9) // 1 ICHI.FARM per block
  );
  const WIchiFarm = await ethers.getContractFactory(CONTRACT_NAMES.WIchiFarm);
  wichi = <WIchiFarm>await upgrades.deployProxy(WIchiFarm, [
    ADDRESS.ICHI,
    ADDRESS.ICHI_FARM,
    ichiFarm.address
  ]);
  await wichi.deployed();

  const ICHISpell = await ethers.getContractFactory(CONTRACT_NAMES.IchiVaultSpell);
  spell = <IchiVaultSpell>await upgrades.deployProxy(ICHISpell, [
    bank.address,
    werc20.address,
    WETH,
    wichi.address
  ])
  await spell.deployed();
  await spell.addStrategy(ichi_USDC_ICHI_Vault.address, utils.parseUnits("2000", 18));
  await spell.addCollateralsSupport(
    0,
    [USDC, ICHI],
    [30000, 30000]
  );
  await spell.setWhitelistLPTokens([ichi_USDC_ICHI_Vault.address], [true]);
  await oracle.setWhitelistERC1155([wichi.address], true);

  // Setup Bank
  await bank.whitelistSpells(
    [spell.address],
    [true]
  )
  await bank.whitelistTokens([USDC, ICHI], [true, true]);

  const HardVault = await ethers.getContractFactory(CONTRACT_NAMES.HardVault);
  hardVault = <HardVault>await upgrades.deployProxy(HardVault, [
    config.address,
  ])
  // Deposit 10k USDC to compound
  const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
  usdcSoftVault = <SoftVault>await upgrades.deployProxy(SoftVault, [
    config.address,
    CUSDC,
    "Interest Bearing USDC",
    "ibUSDC"
  ])
  await usdcSoftVault.deployed();
  await bank.addBank(USDC, CUSDC, usdcSoftVault.address, hardVault.address);

  ichiSoftVault = <SoftVault>await upgrades.deployProxy(SoftVault, [
    config.address,
    CICHI,
    "Interest Bearing ICHI",
    "ibICHI"
  ]);
  await ichiSoftVault.deployed();
  await bank.addBank(ICHI, CICHI, ichiSoftVault.address, hardVault.address);

  await usdc.approve(usdcSoftVault.address, ethers.constants.MaxUint256);
  await usdc.transfer(alice.address, utils.parseUnits("500", 6));
  await usdcSoftVault.deposit(utils.parseUnits("10000", 6));

  await ichi.approve(ichiSoftVault.address, ethers.constants.MaxUint256);
  await ichi.transfer(alice.address, utils.parseUnits("500", 18));
  await ichiSoftVault.deposit(utils.parseUnits("10000", 6));

  // Whitelist bank contract on compound
  const compound = <IComptroller>await ethers.getContractAt("IComptroller", ADDRESS.BLB_COMPTROLLER, admin);
  await compound._setCreditLimit(bank.address, CUSDC, utils.parseUnits("3000000"));
  await compound._setCreditLimit(bank.address, CICHI, utils.parseUnits("3000000"));

  // Add new ichi vault to farming pool
  await ichiFarm.add(100, ichi_USDC_ICHI_Vault.address);
  await ichiFarm.add(100, admin.address); // fake pool

  return {
    ichi_USDC_ICHI_Vault,
    ichiFarm,
    werc20,
    wichi,
    mockOracle,
    ichiOracle,
    oracle,
    config,
    bank,
    spell,
    usdcSoftVault,
    ichiSoftVault,
    hardVault,
  }
}