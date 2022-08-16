import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from "../../constants"
import {
  CoreOracle,
  CurveOracle,
  SimpleOracle,
  WERC20,
  ProxyOracle,
  IComptroller,
  ICEtherEx,
  ICErc20,
  ICurvePool,
  ICurveRegistry,
  IERC20Ex,
} from '../../typechain-types';

describe('Curve Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let eve: SignerWithAddress;

  let werc20: WERC20;
  let simpleOracle: SimpleOracle;
  let coreOracle: CoreOracle;
  let oracle: ProxyOracle;
  let curveOracle: CurveOracle;
  before(async () => {
    [admin, alice, bob, eve] = await ethers.getSigners();

    const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
    werc20 = <WERC20>await WERC20.deploy();
    await werc20.deployed();

    const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
    simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
    await simpleOracle.deployed();

    const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
    await coreOracle.deployed();

    const ProxyOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
    oracle = <ProxyOracle>await ProxyOracleFactory.deploy(coreOracle.address);
    await oracle.deployed();
  })

  describe('Basic', async () => {
    it('setup bank hack', async () => {
      const controllerAddr = "0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258";
      const crethAddr = "0xD06527D5e56A3495252A528C4987003b712860eE";

      const controller = <IComptroller>await ethers.getContractAt(CONTRACT_NAMES.IComptroller, controllerAddr);
      const creth = <ICEtherEx>await ethers.getContractAt(CONTRACT_NAMES.ICEtherEx, crethAddr);

      // TODO: not implemented yet

      // await creth.mint({ 'value': ethers.utils.parseEther('100') });
      // await creth.connect(eve).transfer(bank.address, creth.balanceOf(eve));

      // await controller.connect(bank.address).enterMarkets([creth.address]);
    });
    it('bank oracle price testing', async () => {
      const daiAddr = ADDRESS.DAI;
      const usdcAddr = ADDRESS.USDC;
      const usdtAddr = ADDRESS.USDT;
      const lpAddr = ADDRESS.CRV_3Crv;
      const curvepoolAddr = ADDRESS.CRV_3Crv_POOL;
      const curveregistryAddr = ADDRESS.CRV_GAUGE;

      const curvepool = <ICurvePool>await ethers.getContractAt(CONTRACT_NAMES.ICurvePool, curvepoolAddr);

      await simpleOracle.setETHPx(
        [
          daiAddr,
          usdtAddr,
          usdcAddr,
          lpAddr
        ],
        [
          BigNumber.from(2).pow(112).div(600),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(12)).div(600),
          BigNumber.from(2).pow(112).div(600),
        ]
      )

      const CurveOracle = await ethers.getContractFactory(CONTRACT_NAMES.CurveOracle);
      curveOracle = <CurveOracle>await CurveOracle.deploy(simpleOracle.address, curveregistryAddr);
      await curveOracle.deployed();

      await curveOracle.registerPool(lpAddr);
      await oracle.setWhitelistERC1155([werc20.address], true);

      await coreOracle.setRoute(
        [
          daiAddr,
          usdcAddr,
          usdtAddr,
          lpAddr
        ],
        [
          simpleOracle.address,
          simpleOracle.address,
          simpleOracle.address,
          curveOracle.address
        ],
      );
      await oracle.setTokenFactors(
        [
          daiAddr,
          usdcAddr,
          usdtAddr,
          lpAddr
        ],
        [
          {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000
          }, {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000
          }, {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000
          }, {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000
          },
        ]
      );
      const lpPrice = await curveOracle.getETHPx(lpAddr)
      const daiPrice = await simpleOracle.getETHPx(daiAddr)
      const usdtPrice = await simpleOracle.getETHPx(usdtAddr)
      const usdcPrice = await simpleOracle.getETHPx(usdcAddr)

      const virtualPrice = await curvepool.get_virtual_price();

      expect(lpPrice).to.be.roughlyNear(
        virtualPrice.mul(BigNumber.from(10).pow(6)).mul(BigNumber.from(2).pow(112).div(600)).mul(BigNumber.from(10).pow(12)).div(BigNumber.from(10).pow(18)).div(BigNumber.from(10).pow(18))
      );
    })
  });
});