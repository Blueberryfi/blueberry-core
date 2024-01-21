import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';

import { ADDRESS } from '../../constant';

async function deployUnitroller() {
  const Unitroller = await ethers.getContractFactory('Unitroller');
  const unitroller = await Unitroller.deploy();

  await unitroller.deployed();
  console.log('Unitroller deployed at: ', unitroller.address);

  return unitroller;
}

async function deployComptroller() {
  const Comptroller = await ethers.getContractFactory('Comptroller');
  const comptroller = await Comptroller.deploy();

  await comptroller.deployed();
  console.log('Comptroller deployed at: ', comptroller.address);

  return comptroller;
}

async function deployBTokenAdmin(admin: string) {
  const BTokenAdmin = await ethers.getContractFactory('BTokenAdmin');
  const bTokenAdmin = await BTokenAdmin.deploy(admin);
  await bTokenAdmin.deployed();
  console.log('BTokenAdmin deployed at: ', bTokenAdmin.address);
  return bTokenAdmin;
}

async function deployInterestRateModel(
  baseRate: number,
  multiplier: BigNumber,
  jump: BigNumber,
  kink1: BigNumber,
  roof: BigNumber,
  admin: string
) {
  const JumpRateModelV2 = await ethers.getContractFactory('JumpRateModelV2');
  const interestRateModel = await JumpRateModelV2.deploy(
    baseRate,
    multiplier.mul(kink1).div(utils.parseEther('1')),
    jump,
    kink1,
    roof,
    admin
  );
  await interestRateModel.deployed();

  return interestRateModel;
}

async function deployBToken(
  underlying: string,
  comptroller: string,
  interestRateModel: string,
  bName: string,
  bSymbol: string,
  bDecimal: number,
  bTokenAdmin: string
) {
  const underlyingToken = await ethers.getContractAt('EIP20Interface', underlying);
  const underlyingTokenDecimal = await underlyingToken.decimals();

  const initialExchangeRate = utils.parseUnits('0.01', 18 + underlyingTokenDecimal - bDecimal);

  const BCollateralCapErc20Delegate = await ethers.getContractFactory('BCollateralCapErc20Delegate');
  const bCollateralCapErc20Delegate = await BCollateralCapErc20Delegate.deploy();
  await bCollateralCapErc20Delegate.deployed();
  const BErc20Delegator = await ethers.getContractFactory('BErc20Delegator');
  const bErc20Delegator = await BErc20Delegator.deploy(
    underlying,
    comptroller,
    interestRateModel,
    initialExchangeRate,
    bName,
    bSymbol,
    bDecimal,
    bTokenAdmin,
    bCollateralCapErc20Delegate.address,
    '0x00'
  );
  await bErc20Delegator.deployed();

  return bErc20Delegator;
}

async function deployWrapped(
  underlying: string,
  comptroller: string,
  interestRateModel: string,
  bName: string,
  bSymbol: string,
  bDecimal: number,
  bTokenAdmin: string
) {
  const underlyingToken = await ethers.getContractAt('EIP20Interface', underlying);
  const underlyingTokenDecimal = await underlyingToken.decimals();

  const initialExchangeRate = utils.parseUnits('0.01', 18 + underlyingTokenDecimal - bDecimal);

  const BWrappedNativeDelegate = await ethers.getContractFactory('BWrappedNativeDelegate');
  const bWrappedNativeDelegate = await BWrappedNativeDelegate.deploy();
  await bWrappedNativeDelegate.deployed();

  const BWrappedNativeDelegator = await ethers.getContractFactory('BWrappedNativeDelegator');
  const bWrappedNativeDelegator = await BWrappedNativeDelegator.deploy(
    underlying,
    comptroller,
    interestRateModel,
    initialExchangeRate,
    bName,
    bSymbol,
    bDecimal,
    bTokenAdmin,
    bWrappedNativeDelegate.address,
    '0x00'
  );
  await bWrappedNativeDelegator.deployed();
  return bWrappedNativeDelegator;
}

export async function deployBTokens(admin: string, baseOracle: string) {
  const unitroller = await deployUnitroller();
  const comptroller = await deployComptroller();
  const bTokenAdmin = await deployBTokenAdmin(admin);

  await unitroller._setPendingImplementation(comptroller.address);
  await comptroller._become(unitroller.address);

  const closeFactor = utils.parseEther('0.92');
  const liquidiationIncentive = utils.parseEther('1.08');

  await comptroller._setCloseFactor(closeFactor);
  await comptroller._setLiquidationIncentive(liquidiationIncentive);
  await comptroller._setGuardian(admin);

  const OracleProxy = await ethers.getContractFactory('PriceOracleProxy');
  // Blueberry core oracle address
  const oracle = await OracleProxy.deploy(baseOracle);
  await oracle.deployed();
  console.log('PriceOracleProxy:', oracle.address);

  await comptroller._setPriceOracle(oracle.address);

  let baseRate = 0;
  let multiplier = utils.parseEther('0.2');
  let jump = utils.parseEther('5');
  let kink1 = utils.parseEther('0.7');
  let roof = utils.parseEther('2');
  let IRM = await deployInterestRateModel(baseRate, multiplier, jump, kink1, roof, admin);

  // Deploy USDC
  const bUSDC = await deployBToken(
    ADDRESS.USDC,
    comptroller.address,
    IRM.address,
    'Blueberry USDC',
    'bUSDC',
    6,
    bTokenAdmin.address
  );
  console.log('bUSDC deployed at: ', bUSDC.address);

  // Deploy ICHI Token
  const bICHI = await deployBToken(
    ADDRESS.ICHI,
    comptroller.address,
    IRM.address,
    'Blueberry ICHI',
    'bICHI',
    18,
    bTokenAdmin.address
  );
  console.log('bICHI deployed at: ', bICHI.address);

  // Deploy CRV
  const bCRV = await deployBToken(
    ADDRESS.CRV,
    comptroller.address,
    IRM.address,
    'Blueberry CRV',
    'bCRV',
    18,
    bTokenAdmin.address
  );
  console.log('bCRV deployed at: ', bCRV.address);

  const bDAI = await deployBToken(
    ADDRESS.DAI,
    comptroller.address,
    IRM.address, // IRM.address,
    'Blueberry DAI',
    'bDAI',
    18,
    bTokenAdmin.address
  );
  console.log('bDAI deployed at: ', bDAI.address);

  const bMIM = await deployBToken(
    ADDRESS.MIM,
    comptroller.address,
    IRM.address, // IRM.address,
    'Blueberry MIM',
    'bMIM',
    18,
    bTokenAdmin.address
  );
  console.log('bMIM deployed at: ', bMIM.address);

  const bLINK = await deployBToken(
    ADDRESS.LINK,
    comptroller.address,
    IRM.address, // IRM.address,
    'Blueberry LINK',
    'bLINK',
    18,
    bTokenAdmin.address
  );
  console.log('bLINK deployed at: ', bLINK.address);

  const bOHM = await deployBToken(
    ADDRESS.OHM,
    comptroller.address,
    IRM.address, // IRM.address,
    'Blueberry OHM',
    'bOHM',
    9,
    bTokenAdmin.address
  );
  console.log('bOHM deployed at: ', bOHM.address);

  const bSUSHI = await deployBToken(
    ADDRESS.SUSHI,
    comptroller.address,
    IRM.address, // IRM.address,
    'Blueberry SUSHI',
    'bSUSHI',
    18,
    bTokenAdmin.address
  );
  console.log('bSUSHI deployed at: ', bSUSHI.address);

  const bBAL = await deployBToken(
    ADDRESS.BAL,
    comptroller.address,
    IRM.address,
    'Blueberry BAL',
    'bBAL',
    18,
    bTokenAdmin.address
  );
  console.log('bBAL deployed at: ', bBAL.address);

  //const bALCX = await deployBToken(
  //  ADDRESS.ALCX,
  //  comptroller.address,
  //  IRM.address,
  //  "Blueberry ALCX",
  //  "bALCX",
  //  18,
  //  bTokenAdmin.address
  //);
  //console.log("bALCX deployed at: ", bALCX.address);

  // Deploy WETH
  baseRate = 0;
  multiplier = utils.parseEther('0.125');
  jump = utils.parseEther('2.5');
  kink1 = utils.parseEther('0.8');
  roof = utils.parseEther('2');
  IRM = await deployInterestRateModel(baseRate, multiplier, jump, kink1, roof, admin);
  const bWETH = await deployWrapped(
    ADDRESS.WETH,
    comptroller.address,
    IRM.address,
    'Blueberry Wrapped Ether',
    'bWETH',
    18,
    bTokenAdmin.address
  );
  console.log('bWETH deployed at: ', bWETH.address);

  // Deploy WBTC
  baseRate = 0;
  multiplier = utils.parseEther('0.175');
  jump = utils.parseEther('2');
  kink1 = utils.parseEther('0.8');
  roof = utils.parseEther('2');
  IRM = await deployInterestRateModel(baseRate, multiplier, jump, kink1, roof, admin);
  const bWBTC = await deployBToken(
    ADDRESS.WBTC,
    comptroller.address,
    IRM.address,
    'Blueberry Wrapped Bitcoin',
    'bWBTC',
    8,
    bTokenAdmin.address
  );
  console.log('bWBTC deployed at: ', bWBTC.address);

  const bWstETH = await deployBToken(
    ADDRESS.wstETH,
    comptroller.address,
    IRM.address,
    'Blueberry WstETH',
    'bWstETH',
    18,
    bTokenAdmin.address
  );
  console.log('bWstETH deployed at: ', bWstETH.address);

  // const bCrvStEth = await deployBToken(
  //   ADDRESS.CRV_STETH,
  //   comptroller.address,
  //   IRM.address,
  //   "Blueberry CrvSTETH",
  //   "bCrvSTETH",
  //   18,
  //   bTokenAdmin.address
  // );
  // console.log("bCrvStEth deployed at: ", bCrvStEth.address);

  // const bCrvFrxEth = await deployBToken(
  //   ADDRESS.CRV_FRXETH,
  //   comptroller.address,
  //   IRM.address,
  //   "Blueberry CrvFRXETH",
  //   "bCrvFRXETH",
  //   18,
  //   bTokenAdmin.address
  // );
  // console.log("bCrvFrxEth deployed at: ", bCrvFrxEth.address);

  // const bCrvMim3Crv = await deployBToken(
  //   ADDRESS.CRV_MIM3CRV,
  //   comptroller.address,
  //   IRM.address,
  //   "Blueberry CrvMIM3CRV",
  //   "bCrvMIM3CRV",
  //   18,
  //   bTokenAdmin.address
  // );
  // console.log("bCrvMim3Crv deployed at: ", bCrvMim3Crv.address);

  // const bCrvCvxCrv = await deployBToken(
  //   ADDRESS.CRV_CVXCRV_CRV,
  //   comptroller.address,
  //   IRM.address,
  //   "Blueberry CrvCVXCRV",
  //   "bCrvCVXCRV",
  //   18,
  //   bTokenAdmin.address
  // );
  // console.log("bCrvCvxCrv deployed at: ", bCrvCvxCrv.address);

  await comptroller._supportMarket(bUSDC.address, 0);
  await comptroller._supportMarket(bICHI.address, 0);
  await comptroller._supportMarket(bCRV.address, 0);
  await comptroller._supportMarket(bDAI.address, 0);
  await comptroller._supportMarket(bMIM.address, 0);
  await comptroller._supportMarket(bLINK.address, 0);
  await comptroller._supportMarket(bOHM.address, 0);
  await comptroller._supportMarket(bSUSHI.address, 0);
  await comptroller._supportMarket(bBAL.address, 0);
  //await comptroller._supportMarket(bALCX.address, 0);
  await comptroller._supportMarket(bWETH.address, 0);
  await comptroller._supportMarket(bWBTC.address, 0);
  await comptroller._supportMarket(bWstETH.address, 0);
  //await comptroller._supportMarket(bCrvStEth.address, 0);
  // await comptroller._supportMarket(bCrvFrxEth.address, 0);
  // await comptroller._supportMarket(bCrvMim3Crv.address, 0);
  // await comptroller._supportMarket(bCrvCvxCrv.address, 0);

  return {
    comptroller,
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
    bWstETH,
    // //bCrvStEth,
    // bCrvFrxEth,
    // bCrvMim3Crv,
    // bCrvCvxCrv,
  };
}
