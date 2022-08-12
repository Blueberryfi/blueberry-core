import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from "../../constants"
import {
  BalancerPairOracle,
  CoreOracle,
  BlueBerryBank,
  SimpleOracle,
  WERC20,
  ProxyOracle,
  IUniswapV2Pair,
  IComptroller,
  ICEtherEx,
  ERC20,
} from '../../typechain-types';
import { setupBasic } from '../helpers/setup-basic';
import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

describe('Balancer Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let eve: SignerWithAddress;

  let werc20: WERC20;
  let simpleOracle: SimpleOracle;
  let balancerOracle: BalancerPairOracle;
  let coreOracle: CoreOracle;
  let oracle: ProxyOracle;
  let uniPair: IUniswapV2Pair;

  before(async () => {
    [admin, alice, bob, eve] = await ethers.getSigners();

    const WERC20Factory = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
    werc20 = <WERC20>await WERC20Factory.deploy();
    await werc20.deployed();

    const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
    simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
    await simpleOracle.deployed();

    const BalancerPairOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
    balancerOracle = <BalancerPairOracle>await BalancerPairOracleFactory.deploy(simpleOracle.address);
    await balancerOracle.deployed();

    const CoreOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await CoreOracleFactory.deploy();
    await coreOracle.deployed();

    const ProxyOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.ProxyOracle);
    oracle = <ProxyOracle>await ProxyOracleFactory.deploy(coreOracle.address);
    await oracle.deployed();

    uniPair = <IUniswapV2Pair>await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Pair, ADDRESS.UNI_V2_DAI_WETH);
  })

  describe('Basic', async () => {
    beforeEach(async () => {
    })
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
      const lpAddr = ADDRESS.BAL_WETH_DAI_8020;

      const weth = <ERC20>await ethers.getContractAt(CONTRACT_NAMES.ERC20, ADDRESS.WETH);
      const lp = <ERC20>await ethers.getContractAt(CONTRACT_NAMES.ERC20, lpAddr);

      const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
      const werc20 = <WERC20>await WERC20.deploy();
      await werc20.deployed();

      const uniPair = <IUniswapV2Pair>await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Pair, ADDRESS.UNI_V2_DAI_WETH);

      const reserves = await uniPair.getReserves();
      const token0 = await uniPair.token0();

      let wethDaiPrice = ethers.constants.Zero;
      if (token0 === ADDRESS.WETH) {
        wethDaiPrice = BigNumber.from(10).pow(18).mul(reserves.reserve1).div(reserves.reserve0);
      } else {
        wethDaiPrice = BigNumber.from(10).pow(18).mul(reserves.reserve0).div(reserves.reserve1);
      }

      await simpleOracle.setETHPx(
        [ADDRESS.WETH, ADDRESS.DAI],
        [
          BigNumber.from(2).pow(112),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(18)).div(wethDaiPrice)
        ]
      );

      await oracle.setWhitelistERC1155([werc20.address], true);
      await oracle.setTokenFactors(
        [ADDRESS.WETH, ADDRESS.DAI, lpAddr],
        [
          {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000,
          }, {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000,
          }, {
            borrowFactor: 10000,
            collateralFactor: 10000,
            liqIncentive: 10000,
          },
        ]
      );

      await coreOracle.setRoute(
        [ADDRESS.WETH, ADDRESS.DAI, lpAddr],
        [simpleOracle.address, simpleOracle.address, balancerOracle.address]
      );

      const lpPrice = await balancerOracle.getETHPx(lpAddr);

      const lpWethBalance = await weth.balanceOf(lpAddr)

      const lpSupply = await lp.totalSupply();

      expect(lpPrice).to.be.roughlyNear(
        lpWethBalance.mul(5).div(4).mul(BigNumber.from(2).pow(112)).div(lpSupply)
      )
    })
  });
});