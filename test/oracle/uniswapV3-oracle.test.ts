import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constants';
import {
  SimpleOracle,
  UniswapV3AdapterOracle,
  IUniswapV3Pool,
} from '../../typechain-types';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(near);
chai.use(roughlyNear);

describe('Uniswap V3 Oracle', () => {
  let simpleOracle: SimpleOracle;
  let uniswapV3Oracle: UniswapV3AdapterOracle;

  before(async () => {
    const SimpleOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.SimpleOracle
    );
    simpleOracle = <SimpleOracle>await SimpleOracleFactory.deploy();
    await simpleOracle.deployed();

    await simpleOracle.setPrice(
      [ADDRESS.USDC],
      [BigNumber.from(10).pow(18)]  // $1
    )

    const UniswapV3AdapterOracle = await ethers.getContractFactory(
      CONTRACT_NAMES.UniswapV3AdapterOracle
    );
    uniswapV3Oracle = <UniswapV3AdapterOracle>(
      await UniswapV3AdapterOracle.deploy(simpleOracle.address)
    );
    await uniswapV3Oracle.deployed();
    await uniswapV3Oracle.setPoolsStable(
      [ADDRESS.UNI, ADDRESS.ICHI],
      [ADDRESS.UNI_V3_UNI_USDC, ADDRESS.UNI_V3_ICHI_USDC]
    );
    await uniswapV3Oracle.setTimeAgos(
      [ADDRESS.UNI, ADDRESS.ICHI],
      [600, 600]
    ); // timeAgo - 10 mins
  });

  it('$UNI Price', async () => {
    const price = await uniswapV3Oracle.getPrice(ADDRESS.UNI);
    console.log(utils.formatUnits(price, 18));
  });
  it('$ICHI Price', async () => {
    const price = await uniswapV3Oracle.getPrice(ADDRESS.ICHI);
    console.log(utils.formatUnits(price, 18));
  });
});
