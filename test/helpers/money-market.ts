import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';
import { blueberryMarkets } from '../../test/helpers/markets';
import { ADDRESS } from '../../constant';

async function deployUnitroller() {
  const Unitroller = await ethers.getContractFactory('Unitroller');
  const unitroller = await Unitroller.deploy();

  await unitroller.deployed();

  return unitroller;
}

async function deployComptroller() {
  const Comptroller = await ethers.getContractFactory('Comptroller');
  const comptroller = await Comptroller.deploy();

  await comptroller.deployed();

  return comptroller;
}

async function deployBTokenAdmin(admin: string) {
  const BTokenAdmin = await ethers.getContractFactory('BTokenAdmin');
  const bTokenAdmin = await BTokenAdmin.deploy(admin);
  await bTokenAdmin.deployed();
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
  let bTokens = [];

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

  await comptroller._setPriceOracle(oracle.address);

  // TODO: Fix to add both interest rate models.
  let baseRate = 0;
  let multiplier = utils.parseEther('0.2');
  let jump = utils.parseEther('5');
  let kink1 = utils.parseEther('0.7');
  let roof = utils.parseEther('2');
  let IRM = await deployInterestRateModel(baseRate, multiplier, jump, kink1, roof, admin);
  
  for (let i = 0; i < blueberryMarkets.length; i++) {
    const market = blueberryMarkets[i];

    let bToken = await deployBToken(
      market.underlyingAddress, // Underlying token
      comptroller.address, // Comptroller
      IRM.address, // Interest rate model
      market.bTokenName, // bToken name
      market.bTokenSymbol, // bToken symbol
      8, // bToken decimal
      bTokenAdmin.address // bToken admin
    );

    await comptroller._supportMarket(bToken.address, 0);

    bTokens.push(bToken);
  }

  return {
    comptroller,
    bTokens
  };
}
