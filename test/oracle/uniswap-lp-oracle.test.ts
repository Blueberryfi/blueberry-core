import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { UniswapV2Oracle, IUniswapV2Pair, ChainlinkAdapterOracle, IERC20Metadata } from '../../typechain-types';
import UniPairABI from '../../abi/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol/IUniswapV2Pair.json';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(roughlyNear);

const OneDay = 86400;

describe('Uniswap V2 LP Oracle', () => {
  let uniswapOracle: UniswapV2Oracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;
  before(async () => {
    const [admin] = await ethers.getSigners();
    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(
      ChainlinkAdapterOracle,
      [admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle.setTimeGap([ADDRESS.USDC, ADDRESS.CRV], [OneDay, OneDay]);

    await chainlinkAdapterOracle.setPriceFeeds(
      [ADDRESS.USDC, ADDRESS.CRV],
      [ADDRESS.CHAINLINK_USDC_USD_FEED, ADDRESS.CHAINLINK_CRV_USD_FEED]
    );

    const UniswapOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV2Oracle);
    uniswapOracle = <UniswapV2Oracle>await upgrades.deployProxy(
      UniswapOracleFactory,
      [chainlinkAdapterOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );
    await uniswapOracle.deployed();
  });

  it('USDC/CRV LP Price', async () => {
    const pair = <IUniswapV2Pair>await ethers.getContractAt(UniPairABI, ADDRESS.UNI_V2_USDC_CRV);

    await uniswapOracle.registerPair(pair.address);

    const oraclePrice = await uniswapOracle.callStatic.getPrice(ADDRESS.UNI_V2_USDC_CRV);
    console.log('USDC/CRV LP Price:', utils.formatUnits(oraclePrice, 18));
    // Calculate real lp price manually
    const { reserve0, reserve1 } = await pair.getReserves();
    const totalSupply = await pair.totalSupply();
    const token0 = await pair.token0();
    const token1 = await pair.token1();
    const token0Price = await chainlinkAdapterOracle.callStatic.getPrice(token0);
    const token1Price = await chainlinkAdapterOracle.callStatic.getPrice(token1);
    const token0Contract = <IERC20Metadata>await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token0);
    const token1Contract = <IERC20Metadata>await ethers.getContractAt(CONTRACT_NAMES.IERC20Metadata, token1);
    const token0Decimal = await token0Contract.decimals();
    const token1Decimal = await token1Contract.decimals();

    const token0Amount = token0Price.mul(reserve0).div(BigNumber.from(10).pow(token0Decimal));
    const token1Amount = token1Price.mul(reserve1).div(BigNumber.from(10).pow(token1Decimal));
    const price = token0Amount.add(token1Amount).mul(BigNumber.from(10).pow(18)).div(totalSupply);

    console.log('USDC/CRV LP Price:', utils.formatUnits(oraclePrice, 18), utils.formatUnits(price, 18));
  });
  it('should return 0 when invalid lp address provided', async () => {
    const MockToken = await ethers.getContractFactory(CONTRACT_NAMES.MockERC20);
    const mockToken = await MockToken.deploy('Uniswap Lp Token', 'UNI_LP', 18);
    const price = await uniswapOracle.callStatic.getPrice(mockToken.address);
    expect(price.isZero()).to.be.true;
  });
});
