import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import chai, { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from "../../constants"
import {
  SimpleOracle,
  UniswapV2Oracle,
  IERC20Ex,
  IUniswapV2Pair,
} from '../../typechain-types';
import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

describe('Uniswap LP Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let eve: SignerWithAddress;

  let simpleOracle: SimpleOracle;
  let uniswapOracle: UniswapV2Oracle;
  before(async () => {
    [admin, alice, bob, eve] = await ethers.getSigners();

    const SimpleOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
    simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
    await simpleOracle.deployed();

    const UniswapOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2Oracle);
    uniswapOracle = <UniswapV2Oracle>await UniswapOracleFactory.deploy(simpleOracle.address);
    await uniswapOracle.deployed();
  })

  describe('Basic', async () => {
    it('get LP supply', async () => {
      const daiAddr = ADDRESS.DAI;
      const usdcAddr = ADDRESS.USDC;
      const usdtAddr = ADDRESS.USDT;
      const wethAddr = ADDRESS.WETH;
      const eth_usdtAddr = ADDRESS.UNI_V2_USDT_WETH;
      const eth_usdcAddr = ADDRESS.UNI_V2_USDC_WETH;
      const usdt_usdcAddr = ADDRESS.UNI_V2_USDT_USDC;
      const uniPairAddr = ADDRESS.UNI_V2_DAI_WETH;

      const weth = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, wethAddr);
      const usdt = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, usdtAddr);
      const eth_usdt = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, eth_usdtAddr);
      const eth_usdc = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, eth_usdcAddr);
      const usdt_usdc = <IERC20Ex>await ethers.getContractAt(CONTRACT_NAMES.IERC20Ex, usdt_usdcAddr);
      const uniPair = <IUniswapV2Pair>await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Pair, uniPairAddr);

      const reserves = await uniPair.getReserves();
      const token0 = await uniPair.token0();

      let wethPrice = ethers.constants.Zero;
      if (token0 === wethAddr) {
        wethPrice = BigNumber.from(10).pow(18).mul(reserves.reserve1).div(reserves.reserve0);
      } else {
        wethPrice = BigNumber.from(10).pow(18).mul(reserves.reserve0).div(reserves.reserve1);
      }

      await simpleOracle.setETHPx(
        [
          daiAddr,
          usdtAddr,
          usdcAddr,
          wethAddr
        ],
        [
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(18)).div(wethPrice),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(30)).div(wethPrice),
          BigNumber.from(2).pow(112).mul(BigNumber.from(10).pow(30)).div(wethPrice),
          BigNumber.from(2).pow(112)
        ]
      );

      const eth_usdt_lp = await uniswapOracle.getETHPx(eth_usdtAddr);
      const eth_usdc_lp = await uniswapOracle.getETHPx(eth_usdcAddr);
      const usdt_usdc_lp = await uniswapOracle.getETHPx(usdt_usdcAddr);

      const eth_usdt_balance = await weth.balanceOf(eth_usdtAddr);
      const eth_usdt_supply = await eth_usdt.totalSupply();

      const eth_usdc_balance = await weth.balanceOf(eth_usdcAddr);
      const eth_usdc_supply = await eth_usdc.totalSupply();

      const usdt_usdc_balance = await usdt.balanceOf(usdt_usdcAddr);
      const px = await simpleOracle.getETHPx(usdtAddr);
      const usdt_usdc_supply = await usdt_usdc.totalSupply();

      expect(eth_usdt_lp).to.be.roughlyNear(
        eth_usdt_balance.mul(2).mul(BigNumber.from(2).pow(112)).div(eth_usdt_supply)
      );
      expect(eth_usdc_lp).to.be.roughlyNear(
        eth_usdc_balance.mul(2).mul(BigNumber.from(2).pow(112)).div(eth_usdc_supply)
      );
      expect(usdt_usdc_lp).to.be.roughlyNear(
        usdt_usdc_balance.mul(2).mul(px).div(usdt_usdc_supply)
      );
    })
  });
});